#!/usr/bin/env perl

################################################################################
##
## RAGE1 - Retro Adventure Game Engine, release 1
## (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
## 
## This code is published under a GNU GPL license version 3 or later.  See
## LICENSE file in the distribution for details.
## 
################################################################################

use warnings;
use strict;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib";

require RAGE::Config;
require RAGE::PNGFileUtils;
require RAGE::FileUtils;
require RAGE::Arkos2;
require RAGE::BTileUtils;
require RAGE::AssetBackend;
use RAGE::Datagen::ColorTokens qw( resolve_color_tokens );
use RAGE::Datagen::Util qw( optional_hex_decode pixels_to_byte integer_in_range );
use RAGE::Datagen::Context;
use RAGE::Datagen::PngDispatch qw( dispatch_png_asset_handling );
use RAGE::Datagen::BuildFeatures qw(
    add_build_feature is_build_feature_enabled add_default_build_features
    input_backend_for_platform get_gfx_backend
);
use RAGE::Datagen::Validate qw( check_game_config_is_valid run_consistency_checks );
use RAGE::Datagen::Sprites qw( validate_and_compile_sprite generate_sprites );
use RAGE::Datagen::Btiles qw( validate_and_compile_btile generate_btiles );
use RAGE::Datagen::Screens qw(
    validate_screen compile_screen
    generate_screens generate_map generate_global_screen_data
);
use RAGE::Datagen::FlowRules qw(
    find_existing_rule_index validate_and_compile_rule
    generate_flow_rules generate_game_events_rule_table
);
use RAGE::Datagen::Entities qw(
    validate_and_compile_hero generate_hero generate_bullets
    generate_items generate_crumb_types
);
use RAGE::Datagen::GameConfig qw(
    generate_game_functions generate_game_areas generate_h_header
    generate_h_ending generate_game_config generate_misc_data
    generate_conditional_build_features generate_configuration_values
);
use RAGE::Datagen::Codesets qw(
    generate_c_home_header generate_c_banked_header
    generate_c_banked_data_128_header generate_global_codeset_data
    generate_codeset_headers generate_codeset_functions
    generate_custom_function_tables generate_binary_data_items
    generate_tracker_data
);
use RAGE::Datagen::Dependencies qw(
    create_dataset_dependencies fix_feature_dependencies
    derive_cpc_audio_backend_features
);
use RAGE::Datagen::Parser qw( read_input_data );

use Data::Dumper;
use List::MoreUtils qw( zip uniq );
use Getopt::Std;
use File::Path qw( make_path );
use File::Copy;
use File::Basename;
use GD;

STDOUT->autoflush(1);
STDERR->autoflush(1);

# NOTE (Task 6 Phase 2): the ~41 shared globals that used to be declared here
# (model arrays, name->index hashes, $game_config, $cfg, the base addresses,
# the emit accumulators, etc.) now live inside the $ctx object below as the
# canonical storage.  datagen.pl's own code reads/writes them as $ctx->{field};
# the RAGE::Datagen::* modules take $ctx as their first positional arg and
# reach the same fields as $ctx->{field} (the transitional main:: aliasing
# bridge has been removed).  %codeset_function_name_to_index stays a plain
# datagen.pl lexical (used only here, in dump_internal_data).
my %codeset_function_name_to_index;

# file names
my $c_file_game_data		= 'game_data.c';
my $asm_file_game_data		= 'asm_game_data.asm';
my $h_file_game_data		= 'game_data.h';
my $h_file_build_features	= 'features.h';
my $c_file_banked_data_128	= 'banked/128/game_data_128.c';
# AU5: on CPC-flat there is no banking; the tracker song/FX data + tables land
# in a top-level generated C file (picked up by the cpc-flat $(GENERATED_DIR)/*.c
# glob) instead of banked/128/game_data_128.c.
my $c_file_tracker_cpc		= 'game_data_tracker_cpc.c';

# global directories ($build_dir is a $ctx field; see the context block below)
my $output_dest_dir;
my $game_src_dir;

# codesets and datasets have their source files in their own directory for each one
my $codeset_src_dir_format	= 'codesets/codeset_%s.src';
my $c_file_codeset_format	= 'codesets/codeset_%s.src/main.c';
my $asm_file_codeset_format	= 'codesets/codeset_%s.src/codeset_data.asm';

my $dataset_src_dir_format	= 'datasets/dataset_%s.src';
my $c_file_dataset_format	= 'datasets/dataset_%s.src/main.c';
my $asm_file_dataset_format	= 'datasets/dataset_%s.src/dataset_data.asm';

# dump file for internal state
my $dump_file = 'internal_state.dmp';

######################################################
## Task 6 Phase 2: shared-state context (canonical storage)
######################################################
# RAGE::Datagen::Context now OWNS the ~41 shared globals (model arrays, name->
# index hashes, $game_config, emit accumulators, base addresses, etc.) as the
# canonical storage.  datagen.pl's own code reads/writes them as $ctx->{field};
# the RAGE::Datagen::* modules take $ctx as their first positional arg and reach
# the same fields as $ctx->{field} (Phase 2: the transitional main:: aliasing
# bridge has been removed — $ctx is now threaded explicitly through every
# module sub).  The 7 seeded fields below preserve the non-empty initial values
# those globals used to have; every other field defaults to []/{}/undef inside
# new().  $ctx must be constructed BEFORE any code that uses the fields runs (it
# is — this block precedes the subs and main()).  $ctx is scaffolding, not game
# state: intentionally NOT added to the $all_state dump in dump_internal_data
# (it only holds the globals already dumped there individually).
my $ctx = RAGE::Datagen::Context->new(
    screen_name_to_index => { '__NO_SCREEN__' => 0 },
    syntax               => { valid_whens => [ 'enter_screen', 'exit_screen', 'game_loop' ] },
    valid_game_functions => [ qw( menu intro game_end game_over user_init user_game_init user_game_loop crumb_action custom ) ],
    valid_trackers       => [ qw( arkos2 vortex2 ) ],
    dataset_base_address => 0x5B00,
    codeset_base_address => 0xC000,
    codeset_valid_banks  => [ 6 ],
);

######################################################
## Configuration syntax definitions and lists
######################################################

# $syntax is declared earlier (in the global program state section) so the
# Task 6 Stage 2 context scaffold can alias it for extracted RAGE::Datagen::*
# modules; see the Screens extraction (Step 8).

# @valid_game_functions is declared earlier (in the global program state
# section, next to $syntax) so the Task 6 Stage 2 context scaffold can alias it
# for the extracted GameConfig module; see the GameConfig extraction.

######################################
## A1-7: generic FG/BG colour token vocabulary (README §5.10)
######################################
# Platform-neutral colour-token resolution (FG_/BG_/BRIGHT compounds ->
# ZX INK_*/PAPER_*/BRIGHT, byte-identical pass-through for unknown tokens)
# moved to RAGE::Datagen::ColorTokens (Task 6 Stage 2 leaf extraction);
# resolve_color_tokens() is imported at the top of this file.  See README §5.10.

######################################
## Build Feature functions
######################################

# @default_build_features + add_build_feature / is_build_feature_enabled /
# input_backend_for_platform / get_gfx_backend / add_default_build_features moved
# to RAGE::Datagen::BuildFeatures (Task 6 Stage 2 extraction); imported at the
# top of this file.  %conditional_build_features stays a datagen.pl global
# (reached there via the scaffold alias).

# Task 5: per-platform asset-generation backend (memoised). ZX is the default /
# first backend (byte-identical to the pre-refactor output); CPC platforms get
# the CPC mode-1 backend. Selected from the PLATFORM build features.
my $_asset_backend;
sub asset_backend {
    my $ctx = shift;
    return $_asset_backend if defined $_asset_backend;
    my $is_cpc = is_build_feature_enabled( $ctx, 'PLATFORM_CPC_FLAT' )
              || is_build_feature_enabled( $ctx, 'PLATFORM_CPC464' )
              || is_build_feature_enabled( $ctx, 'PLATFORM_CPC_BANKED' )
              || is_build_feature_enabled( $ctx, 'PLATFORM_CPC6128' );
    $_asset_backend = RAGE::AssetBackend->create( platform => $is_cpc ? 'cpc' : 'zx' );
    return $_asset_backend;
}

# add_default_build_features moved to RAGE::Datagen::BuildFeatures (Task 6
# Stage 2 extraction); imported at the top of this file.

##########################################
## Input data parsing and state machine
##########################################

# optional_hex_decode moved to RAGE::Datagen::Util (Task 6 Stage 2 leaf extraction)

# read_input_data (the .gdata parser/state-machine) moved to RAGE::Datagen::Parser (Task 6 Stage 2 extraction, final step); imported at the top of this file.  It populates the model globals (reached via the scaffold aliases) and calls the validate_and_compile_* / dispatch_png_asset_handling / build-feature helpers imported from their RAGE::Datagen::* modules.

######################################
## Per-platform PNG asset dispatcher
######################################

# dispatch_png_asset_handling (+ helper _cpc_mono_dispatch) moved to
# RAGE::Datagen::PngDispatch (Task 6 Stage 2 extraction); dispatch_png_asset_handling
# is imported at the top of this file. See README §5.9 / A3-1.

######################################
## BTile functions
######################################

# validate_and_compile_btile + generate_btiles moved to RAGE::Datagen::Btiles
# (Task 6 Stage 2 extraction); both are imported at the top of this file. The
# model arrays / emit accumulators they use live in the $ctx object (threaded
# in as their first arg). asset_backend() stays here (shared with the Sprite
# emitter) and btile_deduplicate_arena_best() lives in main:: (loaded by
# RAGE::BTileUtils) — both are called as main::... from the module
# (asset_backend with $ctx threaded in).

#####################################
## Sprite functions
#####################################

# validate_and_compile_sprite + generate_sprite (and the dataset-level
# generate_sprites) moved to RAGE::Datagen::Sprites (Task 6 Stage 2 extraction);
# validate_and_compile_sprite + generate_sprites are imported at the top of this
# file. The model arrays / emit accumulators they use live in the $ctx object
# (threaded in as their first arg); asset_backend() stays here (shared with the
# BTile emitter) and is called as main::asset_backend( $ctx ) from the module.

######################################
## Map Screen functions
######################################

# validate_screen, compile_screen (+ its internal helper compile_screen_data)
# and generate_screen moved to RAGE::Datagen::Screens (Task 6 Stage 2
# extraction); validate_screen, compile_screen, generate_screens, generate_map
# and generate_global_screen_data are imported at the top of this file. The
# model arrays / name->index hashes / emit accumulators / $syntax they use stay
# datagen.pl globals (reached via the scaffold aliases); add_build_feature and
# is_build_feature_enabled are imported by the module from BuildFeatures.

###################################
## Hero functions
###################################

# validate_and_compile_hero, generate_hero, generate_bullets, generate_items
# and generate_crumb_types moved to RAGE::Datagen::Entities (Task 6 Stage 2
# extraction); all are imported at the top of this file.  The model arrays /
# $hero / name->index hashes / emit accumulators (@h_game_data_lines,
# @c_game_data_lines) they use stay datagen.pl globals (reached via the
# scaffold aliases); add_build_feature is imported by the module from
# BuildFeatures.

########################
## Game functions
########################

# generate_game_functions moved to RAGE::Datagen::GameConfig (Task 6 Stage 2
# extraction); imported at the top of this file.

###########################
## Game Area functions
###########################

# generate_game_areas (and its module-private helper generate_single_game_area)
# moved to RAGE::Datagen::GameConfig (Task 6 Stage 2 extraction);
# generate_game_areas is imported at the top of this file.

###################################
## flowgen rule functions
###################################

# find_existing_rule_index, validate_and_compile_rule, generate_flow_rules and
# generate_game_events_rule_table moved to RAGE::Datagen::FlowRules (Task 6
# Stage 2 extraction); the first three plus generate_game_events_rule_table are
# imported at the top of this file.  Internal helpers generate_rule_checks /
# generate_rule_actions and the $check_data_output_format /
# $action_data_output_format tables moved with them (module-private).  The
# model arrays / name->index hashes / custom-function tables / $max_flow_var_id
# / $syntax / emit accumulator they use stay datagen.pl globals (reached via the
# scaffold aliases); add_build_feature is imported by the module from
# BuildFeatures, Compare from Data::Compare.

###################################
## Utility functions
###################################

# pixels_to_byte moved to RAGE::Datagen::Util (Task 6 Stage 2 leaf extraction)

#################################
## Consistency Checks Functions
#################################

# check_game_config_is_valid + run_consistency_checks (and the internal
# check_screen_{sprites,btiles,items}_are_valid helpers) moved to
# RAGE::Datagen::Validate (Task 6 Stage 2 extraction); check_game_config_is_valid
# and run_consistency_checks are imported at the top of this file. The model
# arrays + $game_config they inspect/mutate stay datagen.pl globals (reached
# there via the scaffold aliases).

#############################
## General Output Functions
#############################

# generate_c_home_header and generate_c_banked_header moved to
# RAGE::Datagen::Codesets (Task 6 Stage 2 extraction); imported at the top of
# this file.

# generate_btiles moved to RAGE::Datagen::Btiles (Task 6 Stage 2 extraction);
# imported at the top of this file.  See the validate_and_compile_btile note in
# the BTile functions section above for the scaffold bindings / callbacks.

# generate_sprites moved to RAGE::Datagen::Sprites (Task 6 Stage 2 extraction);
# imported at the top of this file.

# generate_screens + generate_map moved to RAGE::Datagen::Screens (Task 6
# Stage 2 extraction); imported at the top of this file.  See the Map Screen
# functions note above for the scaffold bindings.

# generate_h_header and generate_h_ending moved to RAGE::Datagen::GameConfig
# (Task 6 Stage 2 extraction); imported at the top of this file.

# generate_game_config moved to RAGE::Datagen::GameConfig (Task 6 Stage 2
# extraction); imported at the top of this file.

# this function generates screen data that needs to be stored in the home
# dataset at all times: screen->dataset mapping, screen state asset tables,
# etc.

# generate_global_screen_data moved to RAGE::Datagen::Screens (Task 6 Stage 2
# extraction); imported at the top of this file.  Generates home-dataset screen
# data: screen->dataset mapping table + per-screen asset-state tables.

# generate_misc_data and generate_conditional_build_features moved to
# RAGE::Datagen::GameConfig (Task 6 Stage 2 extraction); imported at the top of
# this file.

## CODESET information
# generate_global_codeset_data, all_codesets_except_home,
# generate_codeset_headers, generate_codeset_functions,
# generate_custom_function_tables, generate_binary_data_items,
# generate_c_banked_data_128_header and generate_tracker_data moved to
# RAGE::Datagen::Codesets (Task 6 Stage 2 extraction); imported at the top of
# this file.  all_codesets_except_home stays module-private there (only called
# by generate_codeset_headers / generate_codeset_functions).

# generate_game_events_rule_table moved to RAGE::Datagen::FlowRules (Task 6
# Stage 2 extraction); imported at the top of this file.

# generate_configuration_values moved to RAGE::Datagen::GameConfig (Task 6
# Stage 2 extraction); imported at the top of this file.

# this function is called from main
sub generate_game_data {

    # generate header lines for all output files
    generate_c_home_header( $ctx ) and print ".";
    generate_c_banked_data_128_header( $ctx ) and print ".";
    generate_h_header( $ctx ) and print ".";

    # generate data - each function is free to add lines to the .c or .h
    # files

    # dataset items. All dataset are generated, including 'home'
    # 'home' dataset will be treated specially at output
    for my $dataset ( keys %{ $ctx->{dataset_dependency} } ) {
        generate_c_banked_header( $ctx, $dataset );
        generate_btiles( $ctx, $dataset );
        generate_sprites( $ctx, $dataset );
        generate_flow_rules( $ctx, $dataset );
        generate_screens( $ctx, $dataset );
        generate_map( $ctx, $dataset );
        print ".";
    }

    # home bank items
    generate_hero( $ctx ) and print ".";
    generate_bullets( $ctx ) and print ".";
    generate_items( $ctx ) and print ".";
    generate_crumb_types( $ctx ) and print ".";
    generate_global_screen_data( $ctx ) and print ".";
    generate_game_areas( $ctx ) and print ".";
    generate_game_config( $ctx ) and print ".";
    generate_misc_data( $ctx ) and print ".";
    generate_game_events_rule_table( $ctx ) and print ".";

    # tracker items
    generate_tracker_data( $ctx ) and print ".";

    # codeset items
    generate_codeset_headers( $ctx ) and print ".";
    generate_codeset_functions( $ctx ) and print ".";
    generate_global_codeset_data( $ctx ) and print ".";
    # binary data items, may be stored in codesets
    generate_binary_data_items( $ctx ) and print ".";

    # this must be generated after codesets, it needs the codeset function
    # call macros
    generate_game_functions( $ctx ) and print ".";

    # generate custom function tables
    generate_custom_function_tables( $ctx ) and print ".";

    # generate conditional build features
    generate_conditional_build_features( $ctx ) and print ".";

    # generate configuration values that need to be carried over to the game_data.h file
    generate_configuration_values( $ctx ) and print ".";

    # generate ending lines if needed
    generate_h_ending( $ctx ) and print ".";
    print "\n";
}

sub output_game_data {
    my $output_fh;

    # output .c file for home bank and dataset
    open( $output_fh, ">:encoding(UTF-8)", $c_file_game_data ) or
        die "Could not open $c_file_game_data for writing\n";
    print $output_fh join( "", @{ $ctx->{c_game_data_lines} }, @{ $ctx->{c_dataset_lines}->{'home'} } );
    close $output_fh;

    # output .asm file for home bank and dataset
    open( $output_fh, ">:encoding(UTF-8)", $asm_file_game_data ) or
        die "Could not open $asm_file_game_data for writing\n";
    print $output_fh join( "", @{ $ctx->{asm_dataset_lines}->{'home'} } );
    close $output_fh;

    # output banked datasets
    foreach my $dataset ( sort grep { /\d+/ } keys %{ $ctx->{c_dataset_lines} } ) {

        # create the destination directory
        my $dst_dir = sprintf( $output_dest_dir . '/' . $dataset_src_dir_format, $dataset );
        if ( ! -d $dst_dir ) {
            make_path( $dst_dir ) or
                die "** Could not create destination directory $dst_dir\n";
        }

        # output .c file for banked datasets
        my $c_file_dataset = ( defined( $output_dest_dir ) ? $output_dest_dir . '/' : '' ) . sprintf( $c_file_dataset_format, $dataset );
        open( $output_fh, ">:encoding(UTF-8)", $c_file_dataset ) or
            die "Could not open $c_file_dataset for writing\n";
        print $output_fh join( "", @{ $ctx->{c_dataset_lines}->{ $dataset } } );
        close $output_fh;

        # output .asm file for banked datasets
        my $asm_file_dataset = ( defined( $output_dest_dir ) ? $output_dest_dir . '/' : '' ) . sprintf( $asm_file_dataset_format, $dataset );
        open( $output_fh, ">:encoding(UTF-8)", $asm_file_dataset ) or
            die "Could not open $asm_file_dataset for writing\n";
        print $output_fh join( "", @{ $ctx->{asm_dataset_lines}->{ $dataset } } );
        close $output_fh;
    }

    # output banked codesets
    my @files_to_copy;
    foreach my $codeset ( sort grep { /\d+/ } keys %{ $ctx->{c_codeset_lines} } ) {

        # create the destination directory
        my $dst_dir = sprintf( $output_dest_dir . '/' . $codeset_src_dir_format, $codeset );
        if ( ! -d $dst_dir ) {
            make_path( $dst_dir ) or
                die "** Could not create destination directory $dst_dir\n";
        }

        # note the files to be moved to the codeset source dir
        my $src_codeset_dir = sprintf( "%s/codeset_%d", $game_src_dir, $codeset );
        foreach my $src_file ( glob( "$src_codeset_dir/*" ) ) {
            my $basename = basename( $src_file );
            push @files_to_copy, {
                src => $src_file,
                dst => $dst_dir . '/' . $basename,
            };
        }

#        foreach my $function ( @{ $codeset_functions_by_codeset{ $codeset } } ) {
#            if ( not defined( $files_to_copy{ $function->{'file'} } ) ) {
#                $files_to_copy{ $function->{'file'} } = {
#                    src => $game_src_dir . '/' . $function->{'file'},
#                    dst => $dst_dir . '/' . $function->{'file'},
#                };
#            }
#        }

        # output .c file for the codeset
        my $c_file_codeset = ( defined( $output_dest_dir ) ? $output_dest_dir . '/' : '' ) . sprintf( $c_file_codeset_format, $codeset );
        open( $output_fh, ">:encoding(UTF-8)", $c_file_codeset ) or
            die "Could not open $c_file_codeset for writing\n";
        print $output_fh join( "", @{ $ctx->{c_codeset_lines}->{ $codeset } } );
        close $output_fh;

        # output .asm file for banked codesets
        my $asm_file_codeset = ( defined( $output_dest_dir ) ? $output_dest_dir . '/' : '' ) . sprintf( $asm_file_codeset_format, $codeset );
        open( $output_fh, ">:encoding(UTF-8)", $asm_file_codeset ) or
            die "Could not open $asm_file_codeset for writing\n";
        print $output_fh join( "", @{ $ctx->{asm_codeset_lines}->{ $codeset } } );
        close $output_fh;
    }

    # move the source files for functions associated to this codeset to the dest dir
    # only if compiling for 128K
    if ( $ctx->{game_config}->{'zx_target'} eq '128' ) {
        foreach my $file ( @files_to_copy ) {
            my $src_file = $file->{'src'};
            my $dst_file = $file->{'dst'};
            move( $src_file, $dst_file ) or
                die "** Could not move $src_file to $dst_file\n";
        }
    }

    # output generated banked data for 128 mode
    if ( $ctx->{game_config}->{'zx_target'} eq '128' ) {
        open( $output_fh, ">:encoding(UTF-8)", $c_file_banked_data_128 ) or
            die "Could not open $c_file_banked_data_128 for writing\n";
        print $output_fh join( "", @{ $ctx->{c_banked_data_128_lines} } );
        close $output_fh;
    }

    # AU5: output generated tracker data for CPC-flat into a top-level C file
    # (no banking). Only written when there is actual tracker data to emit.
    if ( defined( $ctx->{game_config}->{'platform'} ) and
         $ctx->{game_config}->{'platform'} =~ /^cpc/ and
         scalar( @{ $ctx->{c_tracker_cpc_lines} } ) ) {
        open( $output_fh, ">:encoding(UTF-8)", $c_file_tracker_cpc ) or
            die "Could not open $c_file_tracker_cpc for writing\n";
        print $output_fh join( "", @{ $ctx->{c_tracker_cpc_lines} } );
        close $output_fh;
    }


    # output game_data.h file
    open( $output_fh, ">:encoding(UTF-8)", $h_file_game_data ) or
        die "Could not open $h_file_game_data for writing\n";
    print $output_fh join( "", @{ $ctx->{h_game_data_lines} } );
    close $output_fh;

    # output features.h file
    open( $output_fh, ">:encoding(UTF-8)", $h_file_build_features ) or
        die "Could not open $h_file_build_features for writing\n";
    print $output_fh join( "", @{ $ctx->{h_build_features_lines} } );
    close $output_fh;

}

# calculates dataset_dependency structure:
# dataset_dependency: a hash dataset_id => {
#    btiles	=> [ ... ],	# index of btiles that must go in this dataset
#    sprites	=> [ ... ],	# ...ditto for sprites...
#    rules	=> [ ... ],	# ...rules...
#    screens	=> [ ... ],	# ...screens...
# }
#
# All values in the above listrefs are indexes into the global tables for
# each asset type (the all_<something> variables).

# create_dataset_dependencies moved to RAGE::Datagen::Dependencies (Task 6 Stage 2 extraction); imported at the top of this file.

# fixes dependencies between build features.  put here all exceptions and
# mangling needed for build features that need/exclude others, etc.
# AU4-3: derive CPC audio backend macros (Phase AU4 of
# doc/multiplatform-plan/audio.md). CPC has only the AY backend (no
# beeper). On CPC, Arkos2 is the only tracker — vortex2 is a ZX-only
# tracker and is rejected at validation time (check_game_config_is_valid).
#
#   PLATFORM cpc464 + TRACKER            -> MUSIC: CPC_AY
#                                          (+ CPC_AY SFX if FX_CHANNEL set)
#
# The always-present beeper-SFX compat shims that satisfy the engine's
# unconditional audio_sfx_beeper_*() calls live in audio_cpc_ay.h and are
# pulled in for EVERY CPC build by audio.h's CPC platform predicate — they
# need no feature macro of their own.
#
# This is its own sub (not inlined in fix_feature_dependencies) because the
# screen-less CPC fast path in main() bypasses fix_feature_dependencies; it
# calls this directly so the AU4-3 macros are emitted on minimal CPC games too.
# derive_cpc_audio_backend_features moved to RAGE::Datagen::Dependencies (Task 6 Stage 2 extraction); imported at the top of this file.

# fix_feature_dependencies moved to RAGE::Datagen::Dependencies (Task 6 Stage 2 extraction); imported at the top of this file.

# creates a dump of internal data so that other tools (e.g.  FLOWGEN) can
# load it and use the parsed data. Use "-c" option to dump the internal data
sub dump_internal_data {
    open DUMP, ">$dump_file" or
        die "Could not open $dump_file for writing\n";

    my $all_state = {
        btiles				=> $ctx->{all_btiles},
        btile_name_to_index		=> $ctx->{btile_name_to_index},
        screens				=> $ctx->{all_screens},
        screen_name_to_index		=> $ctx->{screen_name_to_index},
        sprites				=> $ctx->{all_sprites},
        sprite_name_to_index		=> $ctx->{sprite_name_to_index},
        all_items			=> $ctx->{all_items},
        item_name_to_index		=> $ctx->{item_name_to_index},
        all_crumb_types			=> $ctx->{all_crumb_types},
        crumb_type_name_to_index	=> $ctx->{crumb_type_name_to_index},
        all_rules			=> $ctx->{all_rules},
        hero				=> $ctx->{hero},
        game_config			=> $ctx->{game_config},
        dataset_dependency		=> $ctx->{dataset_dependency},
        all_codeset_functions		=> $ctx->{all_codeset_functions},
        codeset_function_name_to_index	=> \%codeset_function_name_to_index,
        codeset_functions_by_codeset	=> $ctx->{codeset_functions_by_codeset},
        check_custom_functions		=> $ctx->{check_custom_functions},
        action_custom_functions		=> $ctx->{action_custom_functions},
        conditional_build_features	=> $ctx->{conditional_build_features},
        game_events_rule_table		=> $ctx->{game_events_rule_table},
    };

    print DUMP Data::Dumper->Dump( [ $all_state ], [ 'all_state' ] );
    close DUMP;
}

#########################
## Main loop
#########################

# get tool configuration
print "Reading configuration...\n";
$ctx->{cfg} = rage1_get_config();

our ( $opt_b, $opt_d, $opt_c, $opt_t, $opt_s, $opt_p );
getopts("b:d:ct:s:p:");
if ( defined( $opt_d ) ) {
    $c_file_game_data		= "$opt_d/$c_file_game_data";
    $asm_file_game_data		= "$opt_d/$asm_file_game_data";
    $h_file_game_data		= "$opt_d/$h_file_game_data";
    $h_file_build_features	= "$opt_d/$h_file_build_features";
    $c_file_banked_data_128	=  "$opt_d/$c_file_banked_data_128";
    $c_file_tracker_cpc		=  "$opt_d/$c_file_tracker_cpc";
    $dump_file = "$opt_d/$dump_file";
    $output_dest_dir = $opt_d;
}
$ctx->{build_dir} = $opt_b || 'build';
$game_src_dir = $opt_s || 'build/game_src';

# T1-8: -p <platform> is the canonical CLI flag (zx48 | zx128 | cpc464);
# legacy -t (numeric ZX_TARGET 48 | 128) is kept as a permanent silent alias
# per README §5.6. If -p is given, it overrides -t. If both are absent, the
# build target is inferred later from PLATFORM/ZX_TARGET in the game's
# .gdata files (read_input_data).
# T2-6: cpc464 added; $forced_build_target stays 0 for CPC (no ZX_TARGET
# concept); the PLATFORM directive in the .gdata handles feature emission.
if ( defined( $opt_p ) ) {
    my $p = lc( $opt_p );
    if    ( $p eq 'zx48'  ) { $ctx->{forced_build_target} = 48;  }
    elsif ( $p eq 'zx128' ) { $ctx->{forced_build_target} = 128; }
    elsif ( $p eq 'cpc464' ) {
        # T2-6: CPC464 — no ZX_TARGET; features are emitted from the PLATFORM
        # directive in the game's .gdata.  $forced_build_target remains 0.
        $ctx->{forced_build_target} = 0;
    }
    elsif ( $p eq 'cpc6128' ) {
        # T3-7: CPC6128 (cpc-banked) — same as cpc464: no ZX_TARGET; the PLATFORM
        # directive drives feature emission. $forced_build_target stays 0.
        $ctx->{forced_build_target} = 0;
    }
    elsif ( $p =~ /^cpc/  ) {
        die "** Error: datagen.pl -p $opt_p: accepted CPC platforms are 'cpc464' | 'cpc6128'.\n";
    }
    else {
        die "** Error: datagen.pl -p $opt_p: accepted values are zx48 | zx128 | cpc464 | cpc6128.\n";
    }
} else {
    $ctx->{forced_build_target} = $opt_t || 0;
}

# add default build features - these will be updated/modified later
print "Adding default build features...\n";
add_default_build_features( $ctx );

# read, validate and compile input
print "Reading input data files...\n";
read_input_data( $ctx );

# T2-6: CPC platforms may have a minimal .gdata set (NAME + PLATFORM only,
# no screens/hero/btiles). The full ZX-specific pipeline (dataset deps,
# game data generation) requires a hero and at least one screen and cannot
# run cleanly on a bare CPC skeleton.  When the game has no screens defined,
# skip straight to output_game_data (which only outputs features.h and the
# minimal game_data.h stub).  The full engine integration — and a real
# RAGE1-style gdata set for CPC — is deferred to Phase G7/IN5/AU4.
my $is_cpc_platform = ( defined( $ctx->{game_config}->{'platform'} ) and
                        $ctx->{game_config}->{'platform'} =~ /^cpc/ );
my $has_screens     = scalar( @{ $ctx->{all_screens} } ) > 0;

if ( $is_cpc_platform and not $has_screens ) {
    print "CPC platform with no screens: using minimal features-only output pipeline.\n";
    # For a CPC skeleton (NAME + PLATFORM only, no screens/hero/btiles),
    # emit only features.h plus empty stub files for game_data.h/.c/.asm.
    # The full ZX dataset/codeset/hero pipeline cannot run without a hero
    # and screens; it will be integrated in Phase G7/IN5/AU4 when the CPC
    # HAL backends land and cpc-hello gains a real RAGE1 gdata set.
    #
    # AU4-3: this fast path bypasses run_consistency_checks AND
    # fix_feature_dependencies, where the CPC-audio validation and macro
    # derivation live. Run the config-level (screen-independent) parts here so
    # they are not dead code on screen-less CPC games (every CPC game today):
    #   - check_game_config_is_valid: tracker validation incl. the
    #     vortex2-on-CPC rejection. It only inspects $game_config (no screens/
    #     hero/btiles), so it runs cleanly on a bare skeleton. The screen-
    #     dependent checks in run_consistency_checks are deliberately NOT run.
    #   - derive_cpc_audio_backend_features: emits AUDIO_*_BACKEND_CPC_AY.
    my $cfg_errors = check_game_config_is_valid( $ctx );
    die sprintf( "*** %d errors were found in configuration\n", $cfg_errors )
        if ( $cfg_errors );
    # Derive the CPC-AY macros BEFORE generate_conditional_build_features, which
    # snapshots %conditional_build_features into the features.h output lines.
    derive_cpc_audio_backend_features( $ctx );
    # R4: emit the GFX_BACKEND macro on the screen-less CPC fast path too.
    # In the full pipeline this is done by generate_game_config (line ~3700),
    # which the fast path bypasses — so a screen-less CPC game that selects a
    # GFX_BACKEND (e.g. JSP) would otherwise never get the
    # BUILD_FEATURE_GFX_BACKEND_<X> macro and the gfx backend would self-#ifdef
    # out. Mirror that emission here (canonical + legacy SPRITE_ENGINE alias,
    # per README §5.6).
    my $r4_engine_upper = uc( get_gfx_backend( $ctx ) );
    add_build_feature( $ctx, 'GFX_BACKEND_'   . $r4_engine_upper );
    add_build_feature( $ctx, 'SPRITE_ENGINE_' . $r4_engine_upper );
    generate_conditional_build_features( $ctx );
    # Emit minimal stub game_data.h.
    # R4: also emit DEFAULT_BG_ATTR — engine/src/gfx.c's init_gfx() references
    # GFX_DEFAULT_BG_ATTR (= DEFAULT_BG_ATTR).  In the full pipeline this comes
    # from generate_game_config (line ~3706), which this fast path bypasses, so
    # a CPC game that LINKS the real gfx HAL (minimal_cpc, R4) would otherwise
    # fail to compile.  Inert on CPC (two-layer colour model) but must be
    # defined.  Default to 0 when the game declared no DEFAULT_BG_ATTR.
    my $r4_bg_attr = defined( $ctx->{game_config}->{'default_bg_attr'} )
                     ? $ctx->{game_config}->{'default_bg_attr'} : '0';
    push @{ $ctx->{h_game_data_lines} }, "// CPC minimal stub — no full RAGE1 engine integration\n";
    push @{ $ctx->{h_game_data_lines} }, "#ifndef _GAME_DATA_H\n#define _GAME_DATA_H\n";
    push @{ $ctx->{h_game_data_lines} }, sprintf( "#define DEFAULT_BG_ATTR ( %s )\n", $r4_bg_attr );
    push @{ $ctx->{h_game_data_lines} }, "#endif // _GAME_DATA_H\n";
    # Emit minimal stub .c file (empty translation unit)
    push @{ $ctx->{c_game_data_lines} }, "// CPC minimal stub — no RAGE1 engine integration at Phase T2\n";
    # Initialise dataset/codeset hashrefs so output_game_data does not crash
    $ctx->{c_dataset_lines}   = { 'home' => [] };
    $ctx->{asm_dataset_lines} = { 'home' => [] };
    $ctx->{c_codeset_lines}   = {};
    $ctx->{asm_codeset_lines} = {};
    print "Writing output files...\n";
    output_game_data;
} else {
    # run consistency checks
    print "Running consistency checks...\n";
    run_consistency_checks( $ctx );

    # process data dependencies
    print "Computing dataset dependencies...\n";
    create_dataset_dependencies( $ctx );
    fix_feature_dependencies( $ctx );

    # B7 step 9.3: per-platform banked-asset ORG addresses.  The context
    # defaults (dataset 0x5B00 / codeset 0xC000) are the ZX 128 values; on
    # cpc-banked the engine decompresses each dataset to BANKED_DATASET_BASE_ADDRESS
    # (0x8000, page C) and runs codesets from CODESET_ASSETS_BASE (0x4000, the
    # swap window) — so the emitted dataset/codeset .asm `org` must match those
    # engine macros (engine/include/rage1/dataset.h + memory.h) or the banked
    # binaries' internal pointers resolve to the wrong runtime addresses.  ZX /
    # cpc-flat keep the defaults (byte-identical).
    if ( is_build_feature_enabled( $ctx, 'PLATFORM_CPC_BANKED' ) ) {
        $ctx->{dataset_base_address} = 0x8000;
        $ctx->{codeset_base_address} = 0x4000;
    }

    # generate output
    print "Generating game data...";
    generate_game_data;
    print "Writing output files...\n";
    output_game_data;
}

# dump internal data if required to do so
dump_internal_data
    if ( $opt_c );

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

use Data::Dumper;
use List::MoreUtils qw( zip uniq );
use Getopt::Std;
use File::Path qw( make_path );
use File::Copy;
use File::Basename;
use GD;

STDOUT->autoflush(1);
STDERR->autoflush(1);

# configuration read from etc/rage1-config.yaml file
my $cfg;

# final destination address for compilation of datasets and codesets
my $dataset_base_address = 0x5B00;
my $codeset_base_address = 0xC000;

# banks reserved for codesets. Bank 4 is reserved for engine code
my @codeset_valid_banks = ( 6, );	# non-contended

# global program state
# if you add any global variable here, don't forget to add a reference to it
# also in $all_state variable in dump_internal_data function at the end of
# the script
my @all_btiles;
my %btile_name_to_index;

my @all_screens;
my %screen_name_to_index = ( '__NO_SCREEN__', 0 );

my @all_sprites;
my %sprite_name_to_index;

my @all_items;
my %item_name_to_index;

my @all_rules;
my $max_flow_var_id = undef;

my @game_events_rule_table;

my @all_crumb_types;
my %crumb_type_name_to_index;

# lists of custom function checks and actions
my %check_custom_function_id;
my @check_custom_functions;
my %action_custom_function_id;
my @action_custom_functions;

my @all_codeset_functions;
my %codeset_function_name_to_index;
my %codeset_functions_by_codeset;

my $hero;
my $game_config;

# dataset dependency: stores which assets go into each dataset
my %dataset_dependency;

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

# global directories
my $output_dest_dir;
my $game_src_dir;
my $build_dir;

# codesets and datasets have their source files in their own directory for each one
my $codeset_src_dir_format	= 'codesets/codeset_%s.src';
my $c_file_codeset_format	= 'codesets/codeset_%s.src/main.c';
my $asm_file_codeset_format	= 'codesets/codeset_%s.src/codeset_data.asm';

my $dataset_src_dir_format	= 'datasets/dataset_%s.src';
my $c_file_dataset_format	= 'datasets/dataset_%s.src/main.c';
my $asm_file_dataset_format	= 'datasets/dataset_%s.src/dataset_data.asm';

# dump file for internal state
my $dump_file = 'internal_state.dmp';

# valid values for Tracker type
my @valid_trackers = qw( arkos2 vortex2 );

# output lines for each of the files
my @c_game_data_lines;
my $c_dataset_lines;	# hashref: dataset_id => [ C dataset lines ]
my $asm_dataset_lines;	# hashref: dataset_id => [ C dataset lines ]
my $c_codeset_lines;	# hashref: codeset_id => [ C codeset lines ]
my $asm_codeset_lines;	# hashref: codeset_id => [ C codeset lines ]
my @h_game_data_lines;
my @h_build_features_lines;
my @c_banked_data_128_lines;
# AU5: CPC-flat tracker data lines (songs/FX byte-array externs + tables),
# written to a top-level generated C file. On CPC the @c_banked_data_128_lines
# accumulator is redirected here (see generate_tracker_data).
my @c_tracker_cpc_lines;

# misc vars
my $forced_build_target;
my %conditional_build_features;

# config syntax vocabulary (valid WHEN names for flow-rule tables).  Declared
# here (ahead of the Task 6 Stage 2 scaffold below) so it can be aliased into
# main:: for the extracted Screens/FlowRules modules.
my $syntax = {
    valid_whens => [ 'enter_screen', 'exit_screen', 'game_loop' ],
};

# valid game-function slots (valid GAME_FUNCTION names).  Declared here (ahead
# of the Task 6 Stage 2 scaffold below) so it can be aliased into main:: for the
# extracted GameConfig module; see the GameConfig extraction.
my @valid_game_functions = qw( menu intro game_end game_over user_init user_game_init user_game_loop crumb_action custom );

######################################################
## Task 6 Stage 2: shared-state context + extraction scaffold
######################################################
# RAGE::Datagen::Context holds references to the datagen.pl globals that subs
# extracted into RAGE::Datagen::* modules need to reach.  install_main_aliases()
# is a TEMPORARY scaffold: it aliases each held ref into main:: under the same
# name so an extracted sub can read/write the global by fully-qualified name
# (e.g. $main::game_config), keeping every extraction a mechanical, byte-
# preserving code move.  The context grows one entry per extraction step (only
# the state that step's module touches); see lib/RAGE/Datagen/Context.pm.
# $datagen_ctx is scaffolding, not game state: intentionally NOT added to the
# $all_state dump in dump_internal_data (it only holds refs to globals already
# dumped there).
my $datagen_ctx = RAGE::Datagen::Context->new(
    game_config               => \$game_config,                 # PngDispatch (Step 3), BuildFeatures (Step 4), Validate (Step 5)
    conditional_build_features => \%conditional_build_features,  # BuildFeatures (Step 4)
    all_btiles                => \@all_btiles,                   # Validate (Step 5)
    all_screens               => \@all_screens,                  # Validate (Step 5)
    all_sprites               => \@all_sprites,                  # Validate (Step 5), Sprites (Step 6)
    all_items                 => \@all_items,                    # Validate (Step 5)
    c_dataset_lines           => \$c_dataset_lines,              # Sprites (Step 6) — emit accumulator
    dataset_dependency        => \%dataset_dependency,           # Sprites (Step 6)
    h_game_data_lines         => \@h_game_data_lines,            # Btiles (Step 7) — header emit accumulator
    btile_name_to_index       => \%btile_name_to_index,         # Btiles (Step 7)
    sprite_name_to_index      => \%sprite_name_to_index,         # Screens (Step 8)
    screen_name_to_index      => \%screen_name_to_index,         # Screens (Step 8)
    all_crumb_types           => \@all_crumb_types,              # Screens (Step 8)
    syntax                    => \$syntax,                       # Screens (Step 8) — flow-rule WHEN vocabulary
    all_rules                 => \@all_rules,                    # FlowRules (Step 9)
    max_flow_var_id           => \$max_flow_var_id,              # FlowRules (Step 9) — shared with feature emitter
    check_custom_function_id  => \%check_custom_function_id,     # FlowRules (Step 9)
    check_custom_functions    => \@check_custom_functions,       # FlowRules (Step 9)
    action_custom_function_id => \%action_custom_function_id,    # FlowRules (Step 9)
    action_custom_functions   => \@action_custom_functions,      # FlowRules (Step 9)
    game_events_rule_table    => \@game_events_rule_table,       # FlowRules (Step 9)
    hero                      => \$hero,                         # Entities (Step 10)
    c_game_data_lines         => \@c_game_data_lines,            # Entities (Step 10) — main C emit accumulator
    cfg                       => \$cfg,                          # GameConfig (Step 11) — engine config (interrupts_128)
    build_dir                 => \$build_dir,                    # GameConfig (Step 11) — custom-charset file path
    h_build_features_lines    => \@h_build_features_lines,       # GameConfig (Step 11) — features.h emit accumulator
    valid_game_functions      => \@valid_game_functions,         # GameConfig (Step 11) — valid GAME_FUNCTION slots
    asm_dataset_lines         => \$asm_dataset_lines,            # Codesets (Step 11b) — ASM dataset emit accumulator
    c_codeset_lines           => \$c_codeset_lines,              # Codesets (Step 11b) — C codeset emit accumulator
    asm_codeset_lines         => \$asm_codeset_lines,            # Codesets (Step 11b) — ASM codeset emit accumulator
    c_banked_data_128_lines   => \@c_banked_data_128_lines,      # Codesets (Step 11b) — banked-128 C emit accumulator
    c_tracker_cpc_lines       => \@c_tracker_cpc_lines,          # Codesets (Step 11b) — CPC tracker C emit accumulator
    all_codeset_functions     => \@all_codeset_functions,        # Codesets (Step 11b)
    codeset_functions_by_codeset => \%codeset_functions_by_codeset, # Codesets (Step 11b)
    codeset_valid_banks       => \@codeset_valid_banks,          # Codesets (Step 11b) — codeset bank assignment
    dataset_base_address      => \$dataset_base_address,         # Codesets (Step 11b) — dataset org address
    codeset_base_address      => \$codeset_base_address,         # Codesets (Step 11b) — codeset org address
);
$datagen_ctx->install_main_aliases;

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
    return $_asset_backend if defined $_asset_backend;
    my $is_cpc = is_build_feature_enabled( 'PLATFORM_CPC_FLAT' )
              || is_build_feature_enabled( 'PLATFORM_CPC464' )
              || is_build_feature_enabled( 'PLATFORM_CPC_BANKED' )
              || is_build_feature_enabled( 'PLATFORM_CPC6128' );
    $_asset_backend = RAGE::AssetBackend->create( platform => $is_cpc ? 'cpc' : 'zx' );
    return $_asset_backend;
}

# add_default_build_features moved to RAGE::Datagen::BuildFeatures (Task 6
# Stage 2 extraction); imported at the top of this file.

##########################################
## Input data parsing and state machine
##########################################

# optional_hex_decode moved to RAGE::Datagen::Util (Task 6 Stage 2 leaf extraction)

sub read_input_data {
    # possible states: NONE, BTILE, SCREEN, SPRITE, HERO, GAME_CONFIG, RULE
    # initial state
    my $state = 'NONE';
    my $cur_btile = undef;
    my $cur_screen = undef;
    my $cur_sprite = undef;
    my $cur_rule = undef;

    # read and process input
    # A2-4: generalised PATCH directives — each *_patching flag suppresses
    # the normal "push new struct + register in name_to_index" path at the
    # matching END_*, and (for BTILE/SPRITE/HERO) skips re-running
    # validate_and_compile_* on the already-compiled entity. See README §5.11
    # for the semantics contract.
    my $screen_patching     = 0;
    my $btile_patching      = 0;
    my $sprite_patching     = 0;
    my $hero_patching       = 0;
    my $game_config_patching = 0;
    my $pending_split_lines;

    # after option processing, the remaining ags are the files to process
    my @files = @ARGV;
    my $num_files = scalar( @files );
    my $num_files_read = 0;

    foreach my $file ( @files ) {

        my $current_line = 0;

        open GDATA, $file or
            die "** Error: could not open $file for reading\n";

        while (my $line = <GDATA>) {

            $current_line++;

            # cleanup the line
            chomp $line;
            $line =~ s/^\s*//g;		# remove leading blanks
            $line =~ s/\/\/.*$//g;	# remove comments (//...)
            $line =~ s/\s*$//g;		# remove trailing blanks
            next if $line eq '';		# ignore blank lines

            # if there were previous pending split lines (ending in '\'), add
            # them to the beginning of the current line
            if ( defined( $pending_split_lines ) ) {
                $line = $pending_split_lines . $line;
                $pending_split_lines = undef;
            }

            # if the current line ends in '\', save it for next iteration
            if ( $line =~ /\\$/ ) {
                $line =~ s/\\$//g;	# remove trailing '\' char
                $pending_split_lines = $line;
                next;
            }

            # process the line
            if ( $state eq 'NONE' ) {
                if ( $line =~ /^BEGIN_BTILE$/ ) {
                    $state = 'BTILE';
                    $cur_btile = undef;
                    next;
                }
                if ( $line =~ /^BEGIN_SCREEN$/ ) {
                    $state = 'SCREEN';
                    # we start with empty lists, and with one reserved
                    # asset_state: the first one (0) for this screen, with all
                    # flags reset
                    $cur_screen = { btiles => [ ], items => [ ], hotzones => [ ], sprites => [ ], asset_states => [ { value => 0, comment => 'Screen state' } ] };
                    next;
                }
                if ( $line =~ /^PATCH_SCREEN\s+NAME=(.+)$/ ) {
                    my $name = $1;
                    if ( not defined( $screen_name_to_index{ $name } ) ) {
                        die "PATCH_SCREEN: $file, line $current_line: '$name' is not the name of an existing screen\n";
                    }
                    $state = 'SCREEN';
                    $screen_patching = 1;
                    $cur_screen = $all_screens[ $screen_name_to_index{ $name } ];
                    next;
                }
                # A2-4: generalised PATCH directives (README §5.11).
                # All four mirror PATCH_SCREEN: look up the existing entity in
                # its name-index, enter the matching parser state with $cur_*
                # pointing at the already-loaded struct (no copy), and set the
                # matching *_patching flag so the END_* handler skips push +
                # name_to_index registration. Loaded entities must already
                # exist (Makefile contract: regular files first, patches last).
                if ( $line =~ /^PATCH_GAME_CONFIG$/ ) {
                    if ( not defined( $game_config ) ) {
                        die "PATCH_GAME_CONFIG: $file, line $current_line: GAME_CONFIG has not been loaded yet\n";
                    }
                    $state = 'GAME_CONFIG';
                    $game_config_patching = 1;
                    next;
                }
                if ( $line =~ /^PATCH_BTILE\s+NAME=(.+)$/ ) {
                    my $name = $1;
                    if ( not defined( $btile_name_to_index{ $name } ) ) {
                        die "PATCH_BTILE: $file, line $current_line: '$name' is not the name of an existing BTILE\n";
                    }
                    $state = 'BTILE';
                    $btile_patching = 1;
                    $cur_btile = $all_btiles[ $btile_name_to_index{ $name } ];
                    next;
                }
                if ( $line =~ /^PATCH_SPRITE\s+NAME=(.+)$/ ) {
                    my $name = $1;
                    if ( not defined( $sprite_name_to_index{ $name } ) ) {
                        die "PATCH_SPRITE: $file, line $current_line: '$name' is not the name of an existing SPRITE\n";
                    }
                    $state = 'SPRITE';
                    $sprite_patching = 1;
                    $cur_sprite = $all_sprites[ $sprite_name_to_index{ $name } ];
                    next;
                }
                if ( $line =~ /^PATCH_HERO\s+NAME=(.+)$/ ) {
                    my $name = $1;
                    if ( not defined( $hero ) ) {
                        die "PATCH_HERO: $file, line $current_line: HERO has not been loaded yet\n";
                    }
                    if ( ( $hero->{'name'} // '' ) ne $name ) {
                        die "PATCH_HERO: $file, line $current_line: '$name' is not the name of the loaded HERO (loaded: '" . ( $hero->{'name'} // '<unnamed>' ) . "')\n";
                    }
                    $state = 'HERO';
                    $hero_patching = 1;
                    next;
                }
                if ( $line =~ /^BEGIN_SPRITE$/ ) {
                    $state = 'SPRITE';
                    $cur_sprite = undef;
                    next;
                }
                if ( $line =~ /^BEGIN_HERO$/ ) {
                    if ( defined( $hero ) ) {
                        die "HERO: $file, line $current_line: a HERO is already defined, there can be only one\n";
                    }
                    $state = 'HERO';
                    $cur_sprite = undef;
                    next;
                }
                if ( $line =~ /^BEGIN_GAME_CONFIG$/ ) {
                    if ( defined( $game_config ) ) {
                        die "GAME_CONFIG: $file, line $current_line: a GAME_CONFIG is already defined, there can be only one\n";
                    }
                    $state = 'GAME_CONFIG';
                    next;
                }
                if ( $line =~ /^BEGIN_RULE$/ ) {
                    $state = 'RULE';
                    $cur_rule = undef;
                    next;
                }
                die "Syntax error: $file, line $current_line: '$line' not recognized (global section)\n";

            } elsif ( $state eq 'BTILE' ) {

                if ( $line =~ /^NAME\s+(\w+)$/ ) {
                    $cur_btile->{'name'} = $1;
                    next;
                }
                if ( $line =~ /^DATASET\s+(\w+)$/ ) {
                    $cur_btile->{'dataset'} = $1;
                    next;
                }
                if ( $line =~ /^ROWS\s+(\d+)$/ ) {
                    $cur_btile->{'rows'} = $1;
                    next;
                }
                if ( $line =~ /^COLS\s+(\d+)$/ ) {
                    $cur_btile->{'cols'} = $1;
                    next;
                }
                if ( $line =~ /^PIXELS\s+([\.#]+)$/ ) {
                    push @{$cur_btile->{'pixels'}}, $1;
                    next;
                }
                if ( $line =~ /^ATTR\s+(.+)$/ ) {
                    push @{$cur_btile->{'attr'}}, $1;
                    next;
                }
                if ( $line =~ /^PNG_DATA\s+(.*)$/ ) {
                    my $args = $1;
                    my $vars = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    # A3-2: route PNG asset handling through the
                    # per-platform dispatcher (BTILE branch).
                    my $platform = $game_config->{'platform'};
                    my $png = dispatch_png_asset_handling( $platform,
                        'load_png_file', $build_dir . '/' . $vars->{'file'} ) or
                        die "** Error: $file, line $current_line: could not load PNG file " . $build_dir . '/' . $vars->{'file'} . "\n";

                    if ( $vars->{'png_rotate'} || 0 ) {
                        $png = dispatch_png_asset_handling( $platform,
                            'png_rotate', $png, $vars->{'png_rotate'} );
                    }
                    if ( $vars->{'png_hmirror'} || 0 ) {
                        $png = dispatch_png_asset_handling( $platform,
                            'png_hmirror', $png );
                    }
                    if ( $vars->{'png_vmirror'} || 0 ) {
                        $png = dispatch_png_asset_handling( $platform,
                            'png_vmirror', $png );
                    }

                    dispatch_png_asset_handling( $platform,
                        'map_png_colors_to_zx_colors', $png );

                    my $data = dispatch_png_asset_handling( $platform,
                        'png_to_pixels_and_attrs',
                        $png,
                        $vars->{'xpos'}, $vars->{'ypos'},
                        $vars->{'width'}, $vars->{'height'},
                    );
                    $cur_btile->{'pixels'} = $data->{'pixels'};
                    $cur_btile->{'png_attr'} = $data->{'attrs'};
                    next;
                }
                if ( $line =~ /^FRAMES\s+(\d+)$/ ) {
                    $cur_btile->{'frames'} = $1;
                    next;
                }
                if ( $line =~ /^SEQUENCE\s+(.*)$/ ) {
                    my $args = $1;
                    my $vars = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    my $index = defined( $cur_btile->{'sequences'} ) ? scalar( @{ $cur_btile->{'sequences'} } ) : 0 ;
                    push @{ $cur_btile->{'sequences'} }, $vars;
                    $cur_btile->{'sequence_name_to_index'}{ $vars->{'name'} } = $index;
                    next;
                }
                if ( $line =~ /^END_BTILE$/ ) {
                    if ( not $btile_patching ) {
                        validate_and_compile_btile( $cur_btile );
                        my $index = scalar( @all_btiles );
                        push @all_btiles, $cur_btile;
                        $btile_name_to_index{ $cur_btile->{'name'} } = $index;
                    } else {
                        # A2-4: PATCH_BTILE — entity already validated and
                        # compiled at first load; skip re-validation to avoid
                        # double-compiling pixel_bytes/sequences derived data.
                        $btile_patching = 0;
                    }
                    $state = 'NONE';
                    next;
                }
                die "Syntax error: $file, line $current_line: '$line' not recognized (BTILE section)\n";

            } elsif ( $state eq 'SPRITE' ) {

                if ( $line =~ /^NAME\s+(\w+)$/ ) {
                    $cur_sprite->{'name'} = $1;
                    next;
                }
                if ( $line =~ /^ROWS\s+(\d+)$/ ) {
                    $cur_sprite->{'rows'} = $1;
                    next;
                }
                if ( $line =~ /^COLS\s+(\d+)$/ ) {
                    $cur_sprite->{'cols'} = $1;
                    next;
                }
                if ( $line =~ /^FRAMES\s+(\d+)$/ ) {
                    $cur_sprite->{'frames'} = $1;
                    next;
                }
                if ( $line =~ /^REAL_PIXEL_WIDTH\s+(\d+)$/ ) {
                    $cur_sprite->{'real_pixel_width'} = $1;
                    next;
                }
                if ( $line =~ /^REAL_PIXEL_HEIGHT\s+(\d+)$/ ) {
                    $cur_sprite->{'real_pixel_height'} = $1;
                    next;
                }
                if ( $line =~ /^PIXELS\s+([\.#]+)$/ ) {
                    push @{$cur_sprite->{'pixels'}}, $1;
                    next;
                }
                if ( $line =~ /^MASK\s+(.+)$/ ) {
                    push @{$cur_sprite->{'mask'}}, $1;
                    next;
                }
                if ( $line =~ /^PNG_DATA\s+(.*)$/ ) {
                    my $args = $1;
                    my $vars = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    # A3-2: route PNG asset handling through the
                    # per-platform dispatcher (SPRITE PNG_DATA branch).
                    my $platform = $game_config->{'platform'};
                    my $fgcolor = uc( $vars->{'fgcolor'} );
                    my $png = dispatch_png_asset_handling( $platform,
                        'load_png_file', $build_dir . '/' . $vars->{'file'} ) or
                        die "** Error: $file, line $current_line: could not load PNG file " . $build_dir . '/' . $vars->{'file'} . "\n";

                    dispatch_png_asset_handling( $platform,
                        'map_png_colors_to_zx_colors', $png );

                    my $pix = dispatch_png_asset_handling( $platform,
                        'pick_pixel_data_by_color_from_png',
                        $png, $vars->{'xpos'}, $vars->{'ypos'}, $vars->{'width'}, $vars->{'height'}, $fgcolor,
                        ( $vars->{'hmirror'} || 0 ), ( $vars->{'vmirror'} || 0 )
                        );
                    push @{$cur_sprite->{'pixels'}}, @{ $pix };
                    next;
                }
                if ( $line =~ /^PNG_MASK\s+(.*)$/ ) {
                    my $args = $1;
                    my $vars = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    # A3-2: route PNG asset handling through the
                    # per-platform dispatcher (SPRITE PNG_MASK branch).
                    my $platform = $game_config->{'platform'};
                    my $maskcolor = uc( $vars->{'maskcolor'} );
                    my $png = dispatch_png_asset_handling( $platform,
                        'load_png_file', $build_dir . '/' . $vars->{'file'} ) or
                        die "** Error: $file, line $current_line: could not load PNG file " . $build_dir . '/' . $vars->{'file'} . "\n";

                    dispatch_png_asset_handling( $platform,
                        'map_png_colors_to_zx_colors', $png );

                    my $msk = dispatch_png_asset_handling( $platform,
                        'pick_pixel_data_by_color_from_png',
                        $png, $vars->{'xpos'}, $vars->{'ypos'}, $vars->{'width'}, $vars->{'height'}, $maskcolor,
                        ( $vars->{'hmirror'} || 0 ), ( $vars->{'vmirror'} || 0 )
                        );
                    push @{$cur_sprite->{'mask'}}, @{ $msk };
                    next;
                }
                if ( $line =~ /^ATTR\s+(.+)$/ ) {
                    push @{$cur_sprite->{'attr'}}, $1;
                    next;
                }
                if ( $line =~ /^SEQUENCE\s+(.*)$/ ) {
                    my $args = $1;
                    my $vars = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    my $index = defined( $cur_sprite->{'sequences'} ) ? scalar( @{ $cur_sprite->{'sequences'} } ) : 0 ;
                    push @{ $cur_sprite->{'sequences'} }, $vars;
                    $cur_sprite->{'sequence_name_to_index'}{ $vars->{'name'} } = $index;
                    next;
                }
                if ( $line =~ /^END_SPRITE$/ ) {
                    if ( not $sprite_patching ) {
                        validate_and_compile_sprite( $cur_sprite );
                        $sprite_name_to_index{ $cur_sprite->{'name'}} = scalar( @all_sprites );
                        push @all_sprites, $cur_sprite;
                    } else {
                        # A2-4: PATCH_SPRITE — entity already validated and
                        # compiled at first load; skip re-validation to avoid
                        # double-compiling pixel_bytes/mask_bytes/sequences.
                        $sprite_patching = 0;
                    }
                    $state = 'NONE';
                    next;
                }
                die "Syntax error: $file, line $current_line: '$line' not recognized (SPRITE section)\n";

            } elsif ( $state eq 'SCREEN' ) {

                if ( $line =~ /^NAME\s+(\w+)$/ ) {
                    $cur_screen->{'name'} = $1;
                    next;
                }
                if ( $line =~ /^DATASET\s+(\w+)$/ ) {
                    $cur_screen->{'dataset'} = $1;
                    next;
                }
                if ( $line =~ /^TITLE\s+"(.+)"$/ ) {
                    $cur_screen->{'title'} = $1;
                    add_build_feature( 'SCREEN_TITLES' );
                    next;
                }
                if ( $line =~ /^DECORATION\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = "$1 TYPE=DECORATION";
                    my $item = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };

                    # check if it can change state during the game, and assign a
                    # state slot if it can
                    if ( defined( $item->{'active'} ) and ( $item->{'can_change_state'} || 0 ) ) {
                        $item->{'asset_state_index'} = scalar( @{ $cur_screen->{'asset_states'} } );
                        push @{ $cur_screen->{'asset_states'} }, { value => $item->{'active'}, comment => "Decoration '$item->{name}'" } ;
                    } else {
                        $item->{'asset_state_index'} = 'ASSET_NO_STATE';
                    }

                    my $index = scalar( @{ $cur_screen->{'btiles'} } );
                    push @{ $cur_screen->{'btiles'} }, $item;
                    $cur_screen->{'btile_name_to_index'}{ $item->{'name'} } = $index;
                    next;
                }
                if ( $line =~ /^HARMFUL\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = "$1 TYPE=HARMFUL";
                    my $item = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };

                    # check if it can change state during the game, and assign a
                    # state slot if it can
                    if ( defined( $item->{'active'} ) and ( $item->{'can_change_state'} || 0 ) ) {
                        $item->{'asset_state_index'} = scalar( @{ $cur_screen->{'asset_states'} } );
                        push @{ $cur_screen->{'asset_states'} }, { value => $item->{'active'}, comment => "Harmful '$item->{name}'" } ;
                    } else {
                        $item->{'asset_state_index'} = 'ASSET_NO_STATE';
                    }

                    my $index = scalar( @{ $cur_screen->{'btiles'} } );
                    push @{ $cur_screen->{'btiles'} }, $item;
                    $cur_screen->{'btile_name_to_index'}{ $item->{'name'} } = $index;
                    next;
                }
                if ( $line =~ /^OBSTACLE\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = "$1 TYPE=OBSTACLE";
                    my $item = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };

                    # check if it can change state during the game, and assign a
                    # state slot if it can
                    if ( defined( $item->{'active'} ) and ( $item->{'can_change_state'} || 0 ) ) {
                        $item->{'asset_state_index'} = scalar( @{ $cur_screen->{'asset_states'} } );
                        push @{ $cur_screen->{'asset_states'} }, { value => $item->{'active'}, comment => "Obstacle '$item->{name}'" };
                    } else {
                        $item->{'asset_state_index'} = 'ASSET_NO_STATE';
                    }

                    my $index = scalar( @{ $cur_screen->{'btiles'} } );
                    push @{ $cur_screen->{'btiles'} }, $item;
                    $cur_screen->{'btile_name_to_index'}{ $item->{'name'} } = $index;
                    next;
                }
                if ( $line =~ /^ENEMY\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    my $item = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };

                    # enemies can always change state (=killed or disabled), so assign a state slot
                    $item->{'asset_state_index'} = scalar( @{ $cur_screen->{'asset_states'} } );
                    # if 'active' is defined, respect its value. If it is not, assume active=1
                    if ( defined( $item->{'active'} ) ) {
                        push @{ $cur_screen->{'asset_states'} }, { value => ($item->{'active'} ? 'F_ENEMY_ACTIVE' : 0), comment => "Enemy '$item->{name}'" } ;
                    } else {
                        push @{ $cur_screen->{'asset_states'} }, { value => 'F_ENEMY_ACTIVE', comment => "Enemy '$item->{name}'" };
                    }

                    my $index = defined( $cur_screen->{'enemies'} ) ? scalar( @{ $cur_screen->{'enemies'} } ) : 0;
                    push @{ $cur_screen->{'enemies'} }, $item;
                    $cur_screen->{'enemy_name_to_index'}{ $item->{'name'} } = $index;
                    next;
                }
                if ( $line =~ /^HERO\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    $cur_screen->{'hero'} = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    next;
                }
                if ( $line =~ /^ITEM\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    my $item = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    $item->{'screen'} = $cur_screen->{'name'};
                    my $item_index = scalar( @all_items );
                    push @all_items, $item;
                    push @{ $cur_screen->{'items'} }, $item_index;
                    $item_name_to_index{ $item->{'name'} } = $item_index;
                    add_build_feature( 'HERO_CHECK_TILES_BELOW' );
                    add_build_feature( 'INVENTORY' );
                    next;
                }
                if ( $line =~ /^CRUMB\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    my $item = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };

                    if ( not defined( $crumb_type_name_to_index{ $item->{'type'} } ) ) {
                        die "CRUMB: $file, line $current_line: undefined crumb TYPE '$item->{type}'\n";
                    }

                    # crumbs can change state (=grabbed), so assign a state slot
                    $item->{'asset_state_index'} = scalar( @{ $cur_screen->{'asset_states'} } );
                    push @{ $cur_screen->{'asset_states'} }, { value => 'F_CRUMB_ACTIVE', comment => "Crumb '$item->{name}'" };

                    push @{ $cur_screen->{'crumbs'} }, $item;

                    add_build_feature( 'HERO_CHECK_TILES_BELOW' );
                    add_build_feature( 'CRUMBS' );
                    next;
                }
                if ( $line =~ /^HOTZONE\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    my $item = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };

                    # check if it can change state during the game, and assign a
                    # state slot if it can
                    if ( defined( $item->{'active'} ) and ( $item->{'can_change_state'} || 0 ) ) {
                        $item->{'asset_state_index'} = scalar( @{ $cur_screen->{'asset_states'} } );
                        push @{ $cur_screen->{'asset_states'} }, { value => $item->{'active'}, comment => "Hotzone '$item->{name}'" };
                    } else {
                        $item->{'asset_state_index'} = 'ASSET_NO_STATE';
                    }

                    my $index = scalar( @{ $cur_screen->{'hotzones'} } );
                    push @{ $cur_screen->{'hotzones'} }, $item;
                    $cur_screen->{'hotzone_name_to_index'}{ $item->{'name'} } = $index;
                    next;
                }
                if ( $line =~ /^BACKGROUND\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    $cur_screen->{'background'} = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    next;
                }
                if ( $line =~ /^DEFINE\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    my $item = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    $cur_screen->{'digraphs'}{ $item->{'digraph'} } = $item;
                    next;
                }
                if ( $line =~ /^SCREEN_DATA\s+"(.*)"$/ ) {
                    push @{ $cur_screen->{'screen_data'} }, $1;
                    next;
                }
                if ( $line =~ /^END_SCREEN$/ ) {
                    validate_screen( $cur_screen );
                    if ( not $screen_patching ) {
                        compile_screen( $cur_screen );
                        $screen_name_to_index{ $cur_screen->{'name'}} = scalar( @all_screens );
                        push @all_screens, $cur_screen;
                    } else {
                        $screen_patching = 0;
                    }
                    $state = 'NONE';
                    next;
                }
                die "Syntax error: $file, line $current_line: '$line' not recognized (SCREEN section)\n";

            } elsif ( $state eq 'HERO' ) {

                if ( $line =~ /^NAME\s+(\w+)$/ ) {
                    $hero->{'name'} = $1;
                    next;
                }
                if ( $line =~ /^LIVES\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    $hero->{'lives'} = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    next;
                }
                if ( $line =~ /^DAMAGE_MODE\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    $hero->{'damage_mode'} = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    add_build_feature( 'HERO_ADVANCED_DAMAGE_MODE' );
                    if ( defined( $hero->{'damage_mode'}{'health_display_function'} ) ) {
                        add_build_feature( 'HERO_ADVANCED_DAMAGE_MODE_USE_HEALTH_DISPLAY_FUNCTION' );
                    }
                    next;
                }
                if ( $line =~ /^HSTEP\s+([\d\.]+)$/ ) {
                    $hero->{'hstep'} = $1;
                    next;
                }
                if ( $line =~ /^VSTEP\s+([\d\.]+)$/ ) {
                    $hero->{'vstep'} = $1;
                    next;
                }
                if ( $line =~ /^ANIMATION_DELAY\s+(\d+)$/ ) {
                    $hero->{'animation_delay'} = $1;
                    next;
                }
                if ( $line =~ /^SPRITE\s+(\w+)$/ ) {
                    $hero->{'sprite'} = $1;
                    next;
                }
                if ( $line =~ /^SEQUENCE_UP\s+(\w+)$/ ) {
                    $hero->{'sequence_up'} = $1;
                    next;
                }
                if ( $line =~ /^SEQUENCE_DOWN\s+(\w+)$/ ) {
                    $hero->{'sequence_down'} = $1;
                    next;
                }
                if ( $line =~ /^SEQUENCE_LEFT\s+(\w+)$/ ) {
                    $hero->{'sequence_left'} = $1;
                    next;
                }
                if ( $line =~ /^SEQUENCE_RIGHT\s+(\w+)$/ ) {
                    $hero->{'sequence_right'} = $1;
                    next;
                }
                if ( $line =~ /^STEADY_FRAMES\s+(.*)$/ ) {
                    my $args = $1;
                    my $vars = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    $hero->{'steady_frames'} = $vars;
                    next;
                }
                if ( $line =~ /^BULLET\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    $hero->{'bullet'} = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    next;
                }
                if ( $line =~ /^END_HERO$/ ) {
                    if ( not $hero_patching ) {
                        validate_and_compile_hero( $hero );
                    } else {
                        # A2-4: PATCH_HERO — hero already validated/compiled
                        # at first load; skip re-validation.
                        $hero_patching = 0;
                    }
                    $state = 'NONE';
                    next;
                }
                die "Syntax error: $file, line $current_line: '$line' not recognized (HERO section)\n";

            } elsif ( $state eq 'GAME_CONFIG' ) {

                if ( $line =~ /^NAME\s+(\w+)$/ ) {
                    $game_config->{'name'} = $1;
                    next;
                }
                # A1-1: PLATFORM <name> — preferred multiplatform directive.
                # Accepted values: zx48, zx128, cpc464 (T2-6 adds cpc464).
                # Always emits BOTH PLATFORM_* and legacy ZX_TARGET_* macros
                # for ZX targets so existing engine #ifdefs keep working.
                # For cpc464 (T2-6) emits PLATFORM_CPC464 + PLATFORM_CPC_FLAT.
                if ( $line =~ /^PLATFORM\s+(\w+)$/ ) {
                    my $platform = lc( $1 );
                    if ( $platform ne 'zx48' and $platform ne 'zx128' and $platform ne 'cpc464' ) {
                        die "PLATFORM: $file, line $current_line: PLATFORM must be one of: zx48, zx128, cpc464\n";
                    }
                    # T2-6: CPC464 handling — emit machine-identity AND memory-model macros.
                    if ( $platform eq 'cpc464' ) {
                        $game_config->{'platform'} = $platform;
                        # No ZX_TARGET for CPC; skip derived_zx_target.
                        add_build_feature( 'PLATFORM_CPC464' );      # machine identity
                        add_build_feature( 'PLATFORM_CPC_FLAT' );    # memory model
                        # IN5-3: input backend is forced by PLATFORM (cpc* -> CPC).
                        add_build_feature( input_backend_for_platform( $platform ) );
                        next;
                    }
                    my $derived_zx_target = ( $platform eq 'zx48' ) ? '48' : '128';
                    # CLI override (-t) still wins; it carries 48|128 from
                    # the Makefile (kept legacy for A1-4 compatibility).
                    if ( $forced_build_target ) {
                        $derived_zx_target = $forced_build_target;
                        $platform = ( $forced_build_target eq '48' ) ? 'zx48' : 'zx128';
                    }
                    $game_config->{'zx_target'} = $derived_zx_target;
                    $game_config->{'platform'}  = $platform;
                    add_build_feature( sprintf( "ZX_TARGET_%s", $derived_zx_target ) );
                    add_build_feature( sprintf( "PLATFORM_%s", uc( $platform ) ) );
                    # IN5-3: input backend is forced by PLATFORM (zx* -> ZX).
                    add_build_feature( input_backend_for_platform( $platform ) );
                    next;
                }
                # A1-2: ZX_TARGET is a permanent silent alias for PLATFORM
                # (per README §5.6). Same emission as PLATFORM — both
                # macros are always emitted so the two spellings produce
                # byte-identical builds.
                if ( $line =~ /^ZX_TARGET\s+(\w+)$/ ) {
                    if ( $forced_build_target ) {
                        $game_config->{'zx_target'} = $forced_build_target;
                    } else {
                        $game_config->{'zx_target'} = $1;
                    }
                    if ( ( $game_config->{'zx_target'} ne '48' ) and
                        ( $game_config->{'zx_target'} ne '128' ) ) {
                            die "ZX_TARGET: $file, line $current_line: ZX_TARGET must be either 48 or 128\n";
                        }
                    # internal mapping ZX_TARGET 48|128 -> PLATFORM zx48|zx128
                    $game_config->{'platform'} = ( $game_config->{'zx_target'} eq '48' ) ? 'zx48' : 'zx128';
                    add_build_feature( sprintf( "ZX_TARGET_%s", $game_config->{'zx_target'} ) );
                    add_build_feature( sprintf( "PLATFORM_ZX%s", $game_config->{'zx_target'} ) );
                    # IN5-3: input backend is forced by PLATFORM (zx* -> ZX).
                    add_build_feature( input_backend_for_platform( $game_config->{'platform'} ) );
                    next;
                }
                # GFX_BACKEND is the canonical name; SPRITE_ENGINE is the
                # legacy alias, accepted indefinitely as a silent synonym
                # (per doc/multiplatform-plan/gfx.md §5.6 / README §5.6).
                if ( $line =~ /^(GFX_BACKEND|SPRITE_ENGINE)\s+(\w+)$/ ) {
                    my $keyword = $1;
                    my $engine = lc($2);
                    # Valid backends: 'sp1' (ZX SP1) and 'jsp' (the realtime-shift
                    # sprite engine, used for both ZX and CPC). The interim CPC
                    # 'cpctel' backend was retired in Phase 4J R10 — byte-aligned
                    # CPC sprite libs cannot do 1-px horizontal movement, so JSP
                    # is the CPC sprite engine (see cpc-renderer.md).
                    die "$keyword: $file, line $current_line: must be 'SP1' or 'JSP'\n"
                        if $engine ne 'sp1' and $engine ne 'jsp';
                    $game_config->{'gfx_backend'} = $engine;
                    next;
                }
                if ( $line =~ /^DEFAULT_BG_ATTR\s+(.*)$/ ) {
                    # A1-7: resolve generic FG_/BG_ tokens to their ZX
                    # INK_*/PAPER_*/BRIGHT/FLASH form (byte-identical;
                    # legacy spellings pass through unchanged).
                    $game_config->{'default_bg_attr'} = resolve_color_tokens( $1 );
                    next;
                }
                if ( $line =~ /^HERO\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    $game_config->{'hero'} = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    next;
                }
                if ( $line =~ /^SCREEN\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    $game_config->{'screen'} = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    next;
                }
                if ( $line =~ /^GAME_FUNCTION\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    my $item = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };

                    # check that codeset is a valid value
                    if ( defined( $item->{'codeset'} ) ) {
                        if ( $item->{'codeset'} > ( scalar( @codeset_valid_banks ) - 1 ) ) {
                            die sprintf( "CODESET: $file, line $current_line: CODESET must be in range 0..%d\n", scalar(@codeset_valid_banks ) - 1 );
                        }
                    } else {
                        $item->{'codeset'} = 'home';
                    }

                    # add the needed codeset-related fields.  if a function has
                    # no codeset directive, it goes to the 'home' codeset
                    my $codeset = $item->{'codeset'};
                    if ( not defined( $codeset_functions_by_codeset{ $codeset } ) ) {
                        $codeset_functions_by_codeset{ $codeset } = [];
                    }
                    $item->{'local_index'} = scalar( @{ $codeset_functions_by_codeset{ $codeset } } );

                    # add the function to the codeset lists
                    push @all_codeset_functions, $item;
                    push @{ $codeset_functions_by_codeset{ $codeset } }, $item;

                    # check that the type is a valid function type
                    if ( not scalar( grep { lc( $item->{'type'} ) eq $_ } @valid_game_functions ) ) {
                        die sprintf( "GAME_FUNCTION:  $file, line $current_line: Invalid game function type: %s\n", lc( $item->{'type'} ) );
                    }

                    # add the function to the game config
                    if ( lc( $item->{'type'} ) eq 'custom' ) {
                        push @{ $game_config->{'game_functions'}{'custom'} }, $item;
                    } else {
                        $game_config->{'game_functions'}{ lc( $item->{'type'} ) } = $item;
                    }

                    # adjust build feature
                    if ( $codeset ne 'home' ) {
                        add_build_feature( 'CODESETS' );
                    }
                    next;
                }
                if ( $line =~ /^SOUND\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    my $vars = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    foreach my $k ( keys %$vars ) {
                        $game_config->{'sounds'}{ $k } = $vars->{ $k };
                    }
                    next;
                }
                # CPC_PALETTE — comma-separated CPC firmware colour indices.
                # Drove the (R10-retired) cpct_img2tileset full-colour converter
                # palette; the keyword is still accepted (parsed and stored) for
                # backward compatibility but is currently inert.  CPC-only;
                # ignored on ZX builds.  Per assets.md Q5 / §5.10.
                if ( $line =~ /^CPC_PALETTE\s+([\d,\s]+)$/ ) {
                    ( my $pal = $1 ) =~ s/\s+//g;   # strip whitespace
                    $game_config->{'cpc_palette'} = $pal;
                    next;
                }
                if ( $line =~ /^(GAME_AREA|LIVES_AREA|INVENTORY_AREA|DEBUG_AREA|TITLE_AREA)\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my ( $directive, $args ) = ( $1, $2 );
                    $game_config->{ lc( $directive ) } = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    add_build_feature( 'SCREEN_AREA_' . $directive );
                    next;
                }
                if ( $line =~ /^LOADING_SCREEN\s+(.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    $game_config->{'loading_screen'} = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    if ( scalar( grep { defined } map { $game_config->{'loading_screen'}{ $_ } } qw( png scr ) ) != 1 ) {
                        die "LOADING_SCREEN: $file, line $current_line: exactly one of PNG or SCR options (but not both) must be specified\n";
                    }
                    add_build_feature( "LOADING_SCREEN" );
                    if ( $game_config->{'loading_screen'}{'wait_any_key'} ) {
                        add_build_feature( "LOADING_SCREEN_WAIT_ANY_KEY" );
                    }
                    next;
                }
                if ( $line =~ /^CUSTOM_CHARSET\s+(.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    $game_config->{'custom_charset'} = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    if ( not defined( $game_config->{'custom_charset'}{'file'} ) ) {
                        die "CUSTOM_CHARSET: $file, line $current_line: FILE must be specified\n";
                    }
                    if ( defined( $game_config->{'custom_charset'}{'range'} ) ) {
                        if ( $game_config->{'custom_charset'}{'range'} !~ m/^\d+\-\d+$/ ) {
                            die "CUSTOM_CHARSET: $file, line $current_line: RANGE option must be integers MM-NN\n";
                        }
                    }
                    add_build_feature( "CUSTOM_CHARSET" );
                    next;
                }
                if ( $line =~ /^BINARY_DATA\s+(.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    my $blob_info = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    if ( not defined( $blob_info->{'file'} ) ) {
                        die "BINARY_DATA: $file, line $current_line: FILE must be specified\n";
                    }
                    if ( not defined( $blob_info->{'symbol'} ) ) {
                        die "BINARY_DATA: $file, line $current_line: SYMBOL must be specified\n";
                    }
                    if ( defined( $blob_info->{'compress'} ) ) {
                        if ( $blob_info->{'compress'} !~ m/^[01]$/ ) {
                            die "BINARY_DATA: $file, line $current_line: COMPRESS option must be 0 or 1\n";
                        }
                    }
                    if ( not defined( $blob_info->{'codeset'} ) ) {
                        $blob_info->{'codeset'} = 'home';
                    }
                    # there can be more than one instance of BINARY_DATA for
                    # different pieces of data
                    push @{ $game_config->{'binary_data'} }, $blob_info;
                    next;
                }
                if ( $line =~ /^CRUMB_TYPE\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    my $item = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };

                    # check mandatory fields
                    if ( not defined( $item->{'name'} ) ) {
                        die "CRUMB_TYPE: $file, line $current_line: NAME field is mandatory\n";
                    }

                    if ( not defined( $item->{'btile'} ) ) {
                        die "CRUMB_TYPE:  $file, line $current_line: BTILE field is mandatory\n";
                    }

                    # if an action_function is defined, do some checks
                    if ( defined( $item->{'action_function' } ) ) {

                        my $action_function = {
                            name	=> $item->{'action_function' },
                            codeset	=> ( $item->{'codeset'} || 'home' ),
                            type	=> 'crumb_action',
                        };

                        # check that codeset is a valid value
                        if ( ( $action_function->{'codeset'} ne 'home' ) and ( $action_function->{'codeset'} > ( scalar( @codeset_valid_banks ) - 1 ) ) ) {
                            die sprintf( "CRUMB_TYPE: $file, line $current_line: CODESET must be in range 0..%d\n", scalar(@codeset_valid_banks ) - 1 );
                        }

                        # add the needed codeset-related fields.  if a function has
                        # no codeset directive, it goes to the 'home' codeset
                        my $codeset = $action_function->{'codeset'};
                        if ( not defined( $codeset_functions_by_codeset{ $codeset } ) ) {
                            $codeset_functions_by_codeset{ $codeset } = [];
                        }
                        $action_function->{'local_index'} = scalar( @{ $codeset_functions_by_codeset{ $codeset } } );

                        # add the function to the codeset lists
                        push @all_codeset_functions, $action_function;
                        push @{ $codeset_functions_by_codeset{ $codeset } }, $action_function;

                    }

                    # if an inventory mask is defined keep it, otherwise set it to 0
                    if ( not defined( $item->{'required_items'} ) ) {
                        $item->{'required_items'} = 0;
                    }

                    # add the crumb type to the global list
                    my $index = scalar( @all_crumb_types );
                    push @all_crumb_types, $item;
                    $crumb_type_name_to_index{ $item->{'name'} } = $index;
                    next;	# $line
                }
                if ( $line =~ /^TRACKER\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    my $item = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };

                    if ( not defined( $game_config->{'tracker'} ) ) {
                        $game_config->{'tracker'} = $item;
                    } else {
                        $game_config->{'tracker'} = { %{ $game_config->{'tracker'} }, %$item };
                    }

                    add_build_feature( 'TRACKER' );
                    ( defined( $item->{'type'} ) and grep { $item->{'type'} eq $_ } @valid_trackers ) or
                        die "TRACKER: TYPE is mandatory, must be one of ".join(",",@valid_trackers)."\n";
                    add_build_feature( 'TRACKER_'.uc( $item->{'type'} ) );

                    if ( ( lc( $item->{'type'} ) eq 'vortex2' ) and
                        ( defined( $item->{'fx_channel'} ) or defined( $item->{'fx_volume'} ) ) ) {
                        die "TRACKER: tracker type vortex2 does not support Sound FX\n";
                    }

                    if ( defined( $item->{'fx_channel'} ) ) {
                        if ( not grep { $_ == $item->{'fx_channel'} } ( 0, 1, 2 ) ) {
                            die "TRACKER: $file, line $current_line: FX_CHANNEL can only be 0, 1 or 2\n";
                        }
                        add_build_feature( 'TRACKER_SOUNDFX' );
                        if ( defined( $item->{'fx_volume'} ) ) {
                            if ( not grep { $_ == $item->{'fx_volume'} } ( 0 .. 16 ) ) {
                                die "TRACKER: $file, line $current_line: FX_VOLUME must be in range 0-16\n";
                            }
                        } else {
                            # fx_volume is always defined
                            $item->{'fx_volume'} = 16;	# default value
                        }
                    }
                    next;
                }
                if ( $line =~ /^TRACKER_SONG\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    my $item = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    if ( not defined( $item->{'name'} ) ) {
                        die "TRACKER_SONG: $file, line $current_line: missing NAME argument\n";
                    }
                    if ( not defined( $item->{'file'} ) ) {
                        die "TRACKER_SONG: $file, line $current_line: missing FILE argument\n";
                    }
                    my $index = defined( $game_config->{'tracker'}{'songs'} ) ?
                        scalar( @{ $game_config->{'tracker'}{'songs'} } ) : 0;
                    $item->{'song_index'} = $index;
                    push @{ $game_config->{'tracker'}{'songs'} }, $item;
                    $game_config->{'tracker'}{'song_index'}{ $item->{'name'} } = $index;
                    next;
                }
                if ( $line =~ /^TRACKER_FXTABLE\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    my $item = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    if ( not defined( $item->{'file'} ) ) {
                        die "TRACKER_FXTABLE: $file, line $current_line: missing FILE argument\n";
                    }
                    $game_config->{'tracker'}{'fxtable'} = $item;
                    next;
                }
                if ( $line =~ /^COLOR\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    my $item = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    if ( not defined( $item->{'mode'} ) ) {
                        die "COLOR: $file, line $current_line: missing MODE argument\n";
                    }
                    # A1-7: resolve generic FG_/BG_ tokens in the
                    # GAMEAREA_ATTR value to their ZX form. Legacy
                    # INK_*/PAPER_*/BRIGHT/FLASH spellings pass through
                    # byte-identically.
                    if ( defined( $item->{'gamearea_attr'} ) ) {
                        $item->{'gamearea_attr'} = resolve_color_tokens( $item->{'gamearea_attr'} );
                    }
                    $game_config->{'color'} = $item;
                    next;
                }
                if ( $line =~ /^CUSTOM_STATE_DATA\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    my $item = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    if ( not defined( $item->{'size'} ) ) {
                        die "CUSTOM_STATE_DATA: $file, line $current_line: missing SIZE argument\n";
                    }
                    $game_config->{'custom_state_data'} = $item;
                    add_build_feature( 'CUSTOM_STATE_DATA' );
                    next;
                }
                if ( $line =~ /^SINGLE_USE_BLOB\s+(.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    my $item = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    if ( not defined( $item->{'name'} ) ) {
                        die "SINGLE_USE_BLOB: $file, line $current_line: missing NAME argument\n";
                    }
                    if ( not defined( $item->{'load_address'} ) ) {
                        die "SINGLE_USE_BLOB: $file, line $current_line: missing LOAD_ADDRESS argument\n";
                    }
                    push @{ $game_config->{'single_use_blobs'} }, $item;
                    add_build_feature( 'SINGLE_USE_BLOB' );
                    next;
                }
                # A1-7: BEGIN_CPC_COLOR_MAP ... END_CPC_COLOR_MAP block.
                # Per README §5.10 / §5.6, the block is platform-overlay-
                # scoped: ZX builds parse and silently drop it. Phase A5
                # CPC bring-up will consume the parsed map. OQ-A9
                # (canonical FG/BG → CPC firmware-colour mapping) must
                # be verified before CPC bring-up uses these values.
                if ( $line =~ /^BEGIN_CPC_COLOR_MAP$/ ) {
                    $state = 'CPC_COLOR_MAP';
                    $game_config->{'cpc_color_map'} ||= {};
                    next;
                }
                if ( $line =~ /^END_GAME_CONFIG$/ ) {
                    # A2-4: PATCH_GAME_CONFIG — every directive above is
                    # replace-by-key, so just clear the flag and return to
                    # NONE state. No push / register step in this section.
                    $game_config_patching = 0;
                    $state = 'NONE';
                    next;
                }
                die "Syntax error: $file, line $current_line: '$line' not recognized (GAME_CONFIG section)\n";

            } elsif ( $state eq 'CPC_COLOR_MAP' ) {
                # A1-7: each line maps one colour token (with or without
                # BRIGHT) to an explicit CPC firmware-colour number.
                # Format:  <COLOR_TOKEN>   FW=<n>
                # Unspecified tokens fall back to the canonical table
                # (README §5.10). ZX builds keep the map but never emit
                # it. CPC builds will consume it in Phase A5.
                if ( $line =~ /^END_CPC_COLOR_MAP$/ ) {
                    $state = 'GAME_CONFIG';
                    # A1-7: heads-up warning on ZX builds — the block is
                    # parsed and stored but never emitted to features.h /
                    # game_data.h on ZX. Authors usually want this in a
                    # CPC overlay's game_config/, not in shared .gdata.
                    my $platform = $game_config->{'platform'} // '';
                    if ( $platform =~ /^zx/ or $platform eq '' ) {
                        warn "CPC_COLOR_MAP: $file: block defined on a non-CPC build (platform=" .
                             ( $platform || '<unset>' ) .
                             "); parsed and dropped. Move it to a CPC overlay's game_config/ to take effect.\n";
                    }
                    next;
                }
                if ( $line =~ /^(\w+)\s+FW=(\d+)$/ ) {
                    my ( $tok, $fw ) = ( uc( $1 ), $2 + 0 );
                    if ( $fw < 0 or $fw > 26 ) {
                        die "CPC_COLOR_MAP: $file, line $current_line: FW must be a CPC firmware-colour number 0..26 (got $fw)\n";
                    }
                    $game_config->{'cpc_color_map'}{ $tok } = $fw;
                    next;
                }
                die "Syntax error: $file, line $current_line: '$line' not recognized (CPC_COLOR_MAP section)\n";

            } elsif ( $state eq 'RULE' ) {
                if ( $line =~ /^SCREEN\s+(\w+)$/ ) {
                    # if screen is __EVENTS__ then this rule goes into the game events rule table
                    $cur_rule->{'screen'} = $1;
                    next;
                }
                if ( $line =~ /^WHEN\s+(\w+)$/ ) {
                    # the WHEN clause is ignored if screen is __EVENTS__
                    $cur_rule->{'when'} = lc( $1 );
                    next;
                }
                if ( $line =~ /^CHECK\s+(.+)$/ ) {
                    push @{$cur_rule->{'check'}}, $1;
                    next;
                }
                if ( $line =~ /^DO\s+(.+)$/ ) {
                    push @{$cur_rule->{'do'}}, $1;
                    next;
                }
                if ( $line =~ /^END_RULE$/ ) {
                    # validate rule before deduplicating it
                    validate_and_compile_rule( $cur_rule );

                    # we must delete WHEN and SCREEN for deduplicating rules,
                    # but we must keep them for properly storing the rule
                    my $when = $cur_rule->{'when'} || '<undefined>';
                    delete $cur_rule->{'when'};
                    my $screen = $cur_rule->{'screen'};
                    delete $cur_rule->{'screen'};

                    # find an identical rule if it exists
                    my $found = find_existing_rule_index( $cur_rule );
                    my $index;
                    # use it if found, otherwise add the new one to the global rule list
                    if ( defined( $found ) ) {
                        $index = $found;
                    } else {
                        $index = scalar( @all_rules );
                        push @all_rules, $cur_rule;
                    }

                    # add the rule index to the proper screen rule table, or the events rule table
                    if ( $screen eq '__EVENTS__' ) {
                        push @game_events_rule_table, $index;
                    } else {
                        push @{ $all_screens[ $screen_name_to_index{ $screen } ]{'rules'}{ $when } }, $index;
                    }

                    # clean up for next rule
                    $cur_rule = undef;
                    $state = 'NONE';
                    next;
                }
                die "Syntax error: $file, line $current_line: '$line' not recognized (RULE section)\n";

            } else {
                die "Unknown state '$state'\n";
            }
        }

        # close input file
        close GDATA;

        # do accounting and show progress
        $num_files_read++;
        if ( not ( $num_files_read % 159 ) ) {
            printf "\rGDATA files read: %d/%d", $num_files_read, $num_files;
        }
    }	# end foreach my $file
    printf "\rGDATA files read: %d/%d\n", $num_files_read, $num_files;
}

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
# model arrays / emit accumulators they use stay datagen.pl globals (reached
# there via the scaffold aliases: @main::all_btiles, %main::dataset_dependency,
# %main::btile_name_to_index, %main::conditional_build_features,
# @main::h_game_data_lines, $main::c_dataset_lines); asset_backend() stays here
# (shared with the Sprite emitter) and btile_deduplicate_arena_best() lives in
# main:: (loaded by RAGE::BTileUtils) — both are called as main::... from the
# module.

#####################################
## Sprite functions
#####################################

# validate_and_compile_sprite + generate_sprite (and the dataset-level
# generate_sprites) moved to RAGE::Datagen::Sprites (Task 6 Stage 2 extraction);
# validate_and_compile_sprite + generate_sprites are imported at the top of this
# file. The model arrays / emit accumulators they use stay datagen.pl globals
# (reached there via the scaffold aliases); asset_backend() stays here (shared
# with the BTile emitter) and is called as main::asset_backend() from the module.

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
    generate_c_home_header and print ".";
    generate_c_banked_data_128_header and print ".";
    generate_h_header and print ".";

    # generate data - each function is free to add lines to the .c or .h
    # files

    # dataset items. All dataset are generated, including 'home'
    # 'home' dataset will be treated specially at output
    for my $dataset ( keys %dataset_dependency ) {
        generate_c_banked_header( $dataset );
        generate_btiles( $dataset );
        generate_sprites( $dataset );
        generate_flow_rules( $dataset );
        generate_screens( $dataset );
        generate_map( $dataset );
        print ".";
    }

    # home bank items
    generate_hero and print ".";
    generate_bullets and print ".";
    generate_items and print ".";
    generate_crumb_types and print ".";
    generate_global_screen_data and print ".";
    generate_game_areas and print ".";
    generate_game_config and print ".";
    generate_misc_data and print ".";
    generate_game_events_rule_table and print ".";

    # tracker items
    generate_tracker_data and print ".";

    # codeset items
    generate_codeset_headers and print ".";
    generate_codeset_functions and print ".";
    generate_global_codeset_data and print ".";
    # binary data items, may be stored in codesets
    generate_binary_data_items and print ".";

    # this must be generated after codesets, it needs the codeset function
    # call macros
    generate_game_functions and print ".";

    # generate custom function tables
    generate_custom_function_tables and print ".";

    # generate conditional build features
    generate_conditional_build_features and print ".";

    # generate configuration values that need to be carried over to the game_data.h file
    generate_configuration_values and print ".";

    # generate ending lines if needed
    generate_h_ending and print ".";
    print "\n";
}

sub output_game_data {
    my $output_fh;

    # output .c file for home bank and dataset
    open( $output_fh, ">", $c_file_game_data ) or
        die "Could not open $c_file_game_data for writing\n";
    print $output_fh join( "", @c_game_data_lines, @{ $c_dataset_lines->{'home'} } );
    close $output_fh;

    # output .asm file for home bank and dataset
    open( $output_fh, ">", $asm_file_game_data ) or
        die "Could not open $asm_file_game_data for writing\n";
    print $output_fh join( "", @{ $asm_dataset_lines->{'home'} } );
    close $output_fh;

    # output banked datasets
    foreach my $dataset ( sort grep { /\d+/ } keys %$c_dataset_lines ) {

        # create the destination directory
        my $dst_dir = sprintf( $output_dest_dir . '/' . $dataset_src_dir_format, $dataset );
        if ( ! -d $dst_dir ) {
            make_path( $dst_dir ) or
                die "** Could not create destination directory $dst_dir\n";
        }

        # output .c file for banked datasets
        my $c_file_dataset = ( defined( $output_dest_dir ) ? $output_dest_dir . '/' : '' ) . sprintf( $c_file_dataset_format, $dataset );
        open( $output_fh, ">", $c_file_dataset ) or
            die "Could not open $c_file_dataset for writing\n";
        print $output_fh join( "", @{ $c_dataset_lines->{ $dataset } } );
        close $output_fh;

        # output .asm file for banked datasets
        my $asm_file_dataset = ( defined( $output_dest_dir ) ? $output_dest_dir . '/' : '' ) . sprintf( $asm_file_dataset_format, $dataset );
        open( $output_fh, ">", $asm_file_dataset ) or
            die "Could not open $asm_file_dataset for writing\n";
        print $output_fh join( "", @{ $asm_dataset_lines->{ $dataset } } );
        close $output_fh;
    }

    # output banked codesets
    my @files_to_copy;
    foreach my $codeset ( sort grep { /\d+/ } keys %$c_codeset_lines ) {

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
        open( $output_fh, ">", $c_file_codeset ) or
            die "Could not open $c_file_codeset for writing\n";
        print $output_fh join( "", @{ $c_codeset_lines->{ $codeset } } );
        close $output_fh;

        # output .asm file for banked codesets
        my $asm_file_codeset = ( defined( $output_dest_dir ) ? $output_dest_dir . '/' : '' ) . sprintf( $asm_file_codeset_format, $codeset );
        open( $output_fh, ">", $asm_file_codeset ) or
            die "Could not open $asm_file_codeset for writing\n";
        print $output_fh join( "", @{ $asm_codeset_lines->{ $codeset } } );
        close $output_fh;
    }

    # move the source files for functions associated to this codeset to the dest dir
    # only if compiling for 128K
    if ( $game_config->{'zx_target'} eq '128' ) {
        foreach my $file ( @files_to_copy ) {
            my $src_file = $file->{'src'};
            my $dst_file = $file->{'dst'};
            move( $src_file, $dst_file ) or
                die "** Could not move $src_file to $dst_file\n";
        }
    }

    # output generated banked data for 128 mode
    if ( $game_config->{'zx_target'} eq '128' ) {
        open( $output_fh, ">", $c_file_banked_data_128 ) or
            die "Could not open $c_file_banked_data_128 for writing\n";
        print $output_fh join( "", @c_banked_data_128_lines );
        close $output_fh;
    }

    # AU5: output generated tracker data for CPC-flat into a top-level C file
    # (no banking). Only written when there is actual tracker data to emit.
    if ( defined( $game_config->{'platform'} ) and
         $game_config->{'platform'} =~ /^cpc/ and
         scalar( @c_tracker_cpc_lines ) ) {
        open( $output_fh, ">", $c_file_tracker_cpc ) or
            die "Could not open $c_file_tracker_cpc for writing\n";
        print $output_fh join( "", @c_tracker_cpc_lines );
        close $output_fh;
    }


    # output game_data.h file
    open( $output_fh, ">", $h_file_game_data ) or
        die "Could not open $h_file_game_data for writing\n";
    print $output_fh join( "", @h_game_data_lines );
    close $output_fh;

    # output features.h file
    open( $output_fh, ">", $h_file_build_features ) or
        die "Could not open $h_file_build_features for writing\n";
    print $output_fh join( "", @h_build_features_lines );
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
        btiles				=> \@all_btiles,
        btile_name_to_index		=> \%btile_name_to_index,
        screens				=> \@all_screens,
        screen_name_to_index		=> \%screen_name_to_index,
        sprites				=> \@all_sprites,
        sprite_name_to_index		=> \%sprite_name_to_index,
        all_items			=> \@all_items,
        item_name_to_index		=> \%item_name_to_index,
        all_crumb_types			=> \@all_crumb_types,
        crumb_type_name_to_index	=> \%crumb_type_name_to_index,
        all_rules			=> \@all_rules,
        hero				=> $hero,
        game_config			=> $game_config,
        dataset_dependency		=> \%dataset_dependency,
        all_codeset_functions		=> \@all_codeset_functions,
        codeset_function_name_to_index	=> \%codeset_function_name_to_index,
        codeset_functions_by_codeset	=> \%codeset_functions_by_codeset,
        check_custom_functions		=> \@check_custom_functions,
        action_custom_functions		=> \@action_custom_functions,
        conditional_build_features	=> \%conditional_build_features,
        game_events_rule_table		=> \@game_events_rule_table,
    };

    print DUMP Data::Dumper->Dump( [ $all_state ], [ 'all_state' ] );
    close DUMP;
}

#########################
## Main loop
#########################

# get tool configuration
print "Reading configuration...\n";
$cfg = rage1_get_config();

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
$build_dir = $opt_b || 'build';
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
    if    ( $p eq 'zx48'  ) { $forced_build_target = 48;  }
    elsif ( $p eq 'zx128' ) { $forced_build_target = 128; }
    elsif ( $p eq 'cpc464' ) {
        # T2-6: CPC464 — no ZX_TARGET; features are emitted from the PLATFORM
        # directive in the game's .gdata.  $forced_build_target remains 0.
        $forced_build_target = 0;
    }
    elsif ( $p =~ /^cpc/  ) {
        die "** Error: datagen.pl -p $opt_p: accepted CPC platform is 'cpc464' (Phase T3 adds cpc6128).\n";
    }
    else {
        die "** Error: datagen.pl -p $opt_p: accepted values are zx48 | zx128 | cpc464.\n";
    }
} else {
    $forced_build_target = $opt_t || 0;
}

# add default build features - these will be updated/modified later
print "Adding default build features...\n";
add_default_build_features;

# read, validate and compile input
print "Reading input data files...\n";
read_input_data;

# T2-6: CPC platforms may have a minimal .gdata set (NAME + PLATFORM only,
# no screens/hero/btiles). The full ZX-specific pipeline (dataset deps,
# game data generation) requires a hero and at least one screen and cannot
# run cleanly on a bare CPC skeleton.  When the game has no screens defined,
# skip straight to output_game_data (which only outputs features.h and the
# minimal game_data.h stub).  The full engine integration — and a real
# RAGE1-style gdata set for CPC — is deferred to Phase G7/IN5/AU4.
my $is_cpc_platform = ( defined( $game_config->{'platform'} ) and
                        $game_config->{'platform'} =~ /^cpc/ );
my $has_screens     = scalar( @all_screens ) > 0;

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
    my $cfg_errors = check_game_config_is_valid;
    die sprintf( "*** %d errors were found in configuration\n", $cfg_errors )
        if ( $cfg_errors );
    # Derive the CPC-AY macros BEFORE generate_conditional_build_features, which
    # snapshots %conditional_build_features into the features.h output lines.
    derive_cpc_audio_backend_features;
    # R4: emit the GFX_BACKEND macro on the screen-less CPC fast path too.
    # In the full pipeline this is done by generate_game_config (line ~3700),
    # which the fast path bypasses — so a screen-less CPC game that selects a
    # GFX_BACKEND (e.g. JSP) would otherwise never get the
    # BUILD_FEATURE_GFX_BACKEND_<X> macro and the gfx backend would self-#ifdef
    # out. Mirror that emission here (canonical + legacy SPRITE_ENGINE alias,
    # per README §5.6).
    my $r4_engine_upper = uc( get_gfx_backend() );
    add_build_feature( 'GFX_BACKEND_'   . $r4_engine_upper );
    add_build_feature( 'SPRITE_ENGINE_' . $r4_engine_upper );
    generate_conditional_build_features;
    # Emit minimal stub game_data.h.
    # R4: also emit DEFAULT_BG_ATTR — engine/src/gfx.c's init_gfx() references
    # GFX_DEFAULT_BG_ATTR (= DEFAULT_BG_ATTR).  In the full pipeline this comes
    # from generate_game_config (line ~3706), which this fast path bypasses, so
    # a CPC game that LINKS the real gfx HAL (minimal_cpc, R4) would otherwise
    # fail to compile.  Inert on CPC (two-layer colour model) but must be
    # defined.  Default to 0 when the game declared no DEFAULT_BG_ATTR.
    my $r4_bg_attr = defined( $game_config->{'default_bg_attr'} )
                     ? $game_config->{'default_bg_attr'} : '0';
    push @h_game_data_lines, "// CPC minimal stub — no full RAGE1 engine integration\n";
    push @h_game_data_lines, "#ifndef _GAME_DATA_H\n#define _GAME_DATA_H\n";
    push @h_game_data_lines, sprintf( "#define DEFAULT_BG_ATTR ( %s )\n", $r4_bg_attr );
    push @h_game_data_lines, "#endif // _GAME_DATA_H\n";
    # Emit minimal stub .c file (empty translation unit)
    push @c_game_data_lines, "// CPC minimal stub — no RAGE1 engine integration at Phase T2\n";
    # Initialise dataset/codeset hashrefs so output_game_data does not crash
    $c_dataset_lines   = { 'home' => [] };
    $asm_dataset_lines = { 'home' => [] };
    $c_codeset_lines   = {};
    $asm_codeset_lines = {};
    print "Writing output files...\n";
    output_game_data;
} else {
    # run consistency checks
    print "Running consistency checks...\n";
    run_consistency_checks;

    # process data dependencies
    print "Computing dataset dependencies...\n";
    create_dataset_dependencies;
    fix_feature_dependencies;

    # generate output
    print "Generating game data...";
    generate_game_data;
    print "Writing output files...\n";
    output_game_data;
}

# dump internal data if required to do so
dump_internal_data
    if ( $opt_c );

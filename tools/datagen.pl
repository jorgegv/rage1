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

use Data::Dumper;
use List::MoreUtils qw( zip uniq );
use Getopt::Std;
use Data::Compare;
use File::Path qw( make_path );
use File::Copy;
use File::Basename;

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

# misc vars
my $forced_build_target;
my %conditional_build_features;

######################################################
## Configuration syntax definitions and lists
######################################################

my $syntax = {
    valid_whens => [ 'enter_screen', 'exit_screen', 'game_loop' ],
};

my @valid_game_functions = qw( menu intro game_end game_over user_init user_game_init user_game_loop crumb_action custom );

######################################
## Build Feature functions
######################################

# build features that always selected no matter what
my @default_build_features = qw(
    BTILE_2BIT_TYPE_MAP
    GAME_TIME
);

sub add_build_feature {
    my $f = shift;
    $conditional_build_features{ $f }++;
}

sub is_build_feature_enabled {
    my $f = shift;
    return defined( $conditional_build_features{ $f } );
}

sub add_default_build_features {
    foreach my $f ( @default_build_features ) {
        add_build_feature( $f );
    }
}

##########################################
## Input data parsing and state machine
##########################################

sub optional_hex_decode {
    my $value = shift;
    if ( $value =~ m/^0x[0-9a-f]+$/i ) {
        return hex( $value );
    }
    if ( $value =~ m/^\$([0-9a-f]+)$/i ) {
        return hex( $1 );
    }
    return $value;
}

sub read_input_data {
    # possible states: NONE, BTILE, SCREEN, SPRITE, HERO, GAME_CONFIG, RULE
    # initial state
    my $state = 'NONE';
    my $cur_btile = undef;
    my $cur_screen = undef;
    my $cur_sprite = undef;
    my $cur_rule = undef;

    # read and process input
    my $screen_patching = 0;
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
                    my $png = load_png_file( $build_dir . '/' . $vars->{'file'} ) or
                        die "** Error: $file, line $current_line: could not load PNG file " . $build_dir . '/' . $vars->{'file'} . "\n";

                    if ( $vars->{'png_rotate'} || 0 ) {
                        $png = png_rotate( $png, $vars->{'png_rotate'} );
                    }
                    if ( $vars->{'png_hmirror'} || 0 ) {
                        $png = png_hmirror( $png );
                    }
                    if ( $vars->{'png_vmirror'} || 0 ) {
                        $png = png_vmirror( $png );
                    }

                    map_png_colors_to_zx_colors( $png );

                    my $data = png_to_pixels_and_attrs(
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
                    validate_and_compile_btile( $cur_btile );
                    my $index = scalar( @all_btiles );
                    push @all_btiles, $cur_btile;
                    $btile_name_to_index{ $cur_btile->{'name'} } = $index;
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
                    my $fgcolor = uc( $vars->{'fgcolor'} );
                    my $png = load_png_file( $build_dir . '/' . $vars->{'file'} ) or
                        die "** Error: $file, line $current_line: could not load PNG file " . $build_dir . '/' . $vars->{'file'} . "\n";

                    map_png_colors_to_zx_colors( $png );

                    push @{$cur_sprite->{'pixels'}}, @{ pick_pixel_data_by_color_from_png(
                        $png, $vars->{'xpos'}, $vars->{'ypos'}, $vars->{'width'}, $vars->{'height'}, $fgcolor,
                        ( $vars->{'hmirror'} || 0 ), ( $vars->{'vmirror'} || 0 )
                        ) };
                    next;
                }
                if ( $line =~ /^PNG_MASK\s+(.*)$/ ) {
                    my $args = $1;
                    my $vars = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    my $maskcolor = uc( $vars->{'maskcolor'} );
                    my $png = load_png_file( $build_dir . '/' . $vars->{'file'} ) or
                        die "** Error: $file, line $current_line: could not load PNG file " . $build_dir . '/' . $vars->{'file'} . "\n";

                    map_png_colors_to_zx_colors( $png );

                    push @{$cur_sprite->{'mask'}}, @{ pick_pixel_data_by_color_from_png(
                        $png, $vars->{'xpos'}, $vars->{'ypos'}, $vars->{'width'}, $vars->{'height'}, $maskcolor,
                        ( $vars->{'hmirror'} || 0 ), ( $vars->{'vmirror'} || 0 )
                        ) };
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
                    validate_and_compile_sprite( $cur_sprite );
                    $sprite_name_to_index{ $cur_sprite->{'name'}} = scalar( @all_sprites );
                    push @all_sprites, $cur_sprite;
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
                    validate_and_compile_hero( $hero );
                    $state = 'NONE';
                    next;
                }
                die "Syntax error: $file, line $current_line: '$line' not recognized (HERO section)\n";

            } elsif ( $state eq 'GAME_CONFIG' ) {

                if ( $line =~ /^NAME\s+(\w+)$/ ) {
                    $game_config->{'name'} = $1;
                    next;
                }
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
                    add_build_feature( sprintf( "ZX_TARGET_%s", $game_config->{'zx_target'} ) );
                    next;
                }
                if ( $line =~ /^DEFAULT_BG_ATTR\s+(.*)$/ ) {
                    $game_config->{'default_bg_attr'} = $1;
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
                if ( $line =~ /^END_GAME_CONFIG$/ ) {
                    $state = 'NONE';
                    next;
                }
                die "Syntax error: $file, line $current_line: '$line' not recognized (GAME_CONFIG section)\n";

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
## BTile functions
######################################

sub validate_and_compile_btile {
    my $tile = shift;

    # FRAMES is not mandatory for BTILEs
    if ( not defined( $tile->{'frames'} ) ) {
        $tile->{'frames'} = 1;
    }

    defined( $tile->{'name'} ) or
        die "Btile has no NAME\n";
    defined( $tile->{'rows'} ) or
        die "Btile '$tile->{name}' has no ROWS\n";
    defined( $tile->{'cols'} ) or
        die "Btile '$tile->{name}' has no COLS\n";
    defined( $tile->{'pixels'} ) or
        die "Btile '$tile->{name}' has no PIXELS\n";
    defined( $tile->{'attr'} ) or defined( $tile->{'png_attr'} ) or
        die "Btile '$tile->{name}' has no ATTR or PNG_ATTRS\n";
    my $num_attrs = $tile->{'rows'} * $tile->{'cols'} * $tile->{'frames'};
    if ( defined( $tile->{'attr'} ) ) {
        ( scalar( @{$tile->{'attr'}} ) == $num_attrs ) or
            die "Btile '$tile->{name}' should have $num_attrs ATTR elements\n";
    } else {
        ( scalar( @{$tile->{'png_attr'}} ) == $num_attrs ) or
            die "Btile '$tile->{name}' should have $num_attrs elements in PNG_ATTR\n";
    }
    ( scalar( @{$tile->{'pixels'}} ) == $tile->{'rows'} * 8 * $tile->{'frames'} ) or
        die "Btile '$tile->{name}' should have ".( $tile->{'rows'} * 8 * $tile->{'frames'} )." PIXELS elements\n";
    foreach my $p ( @{$tile->{'pixels'}} ) {
        ( length( $p ) == $tile->{'cols'} * 2 * 8 ) or
            die "Btile PIXELS line should be of length ".( $tile->{'rows'} * 2 * 8 );
    }

    # compile pixel string data to numeric data for output
    my $cur_row = 0;
    my $byte_count = 0;
    foreach my $p ( @{$tile->{'pixels'}} ) {
        my @parts = unpack("(A16)*", $p );
        my $cur_col = 0;
        foreach my $b ( @parts ) {
            push @{$tile->{'pixel_bytes'}[ $cur_row * $tile->{'cols'} + $cur_col++ ] },
                pixels_to_byte( $b );
            if ( not ( ++$byte_count % ( 8 * $tile->{'cols'} ) ) ) { $cur_row++; }
        }
    }

    # compile animation sequences
    foreach my $seq ( @{ $tile->{'sequences'} } ) {
        $seq->{'frame_list'} = [ split( /,/, $seq->{'frames'} ) ];
    }
}

#####################################
## Sprite functions
#####################################

sub validate_and_compile_sprite {
    my $sprite = shift;
    defined( $sprite->{'name'} ) or
        die "Sprite has no NAME\n";
    defined( $sprite->{'rows'} ) or
        die "Sprite '$sprite->{name}' has no ROWS\n";
    defined( $sprite->{'cols'} ) or
        die "Sprite '$sprite->{name}' has no COLS\n";
    defined( $sprite->{'pixels'} ) or
        die "Sprite '$sprite->{name}' has no PIXELS\n";
#    defined( $sprite->{'attr'} ) or
#        die "Sprite '$sprite->{name}' has no ATTR\n";
    defined( $sprite->{'frames'} ) or
        die "Sprite '$sprite->{name}' has no FRAMES\n";
    defined( $sprite->{'mask'} ) or
        die "Sprite '$sprite->{name}' has no MASK\n";
    my $num_attrs = $sprite->{'rows'} * $sprite->{'cols'};
#    ( scalar( @{$sprite->{'attr'}} ) == $num_attrs ) or
#        die "Sprite should have $num_attrs ATTR elements\n";
    ( scalar( @{$sprite->{'pixels'}} ) == $sprite->{'rows'} * 8 * $sprite->{'frames'} ) or
        die "Sprite should have ".( $sprite->{'rows'} * 8 * $sprite->{'frames'} )." PIXELS elements\n";
    ( scalar( @{$sprite->{'mask'}} ) == $sprite->{'rows'} * 8 * $sprite->{'frames'} ) or
        die "Sprite should have ".( $sprite->{'rows'} * 8 * $sprite->{'frames'} )." MASK elements\n";
    foreach my $p ( @{$sprite->{'pixels'}} ) {
        ( length( $p ) == $sprite->{'cols'} * 2 * 8 ) or
            die "Sprite '$sprite->{name}': PIXELS line should be of length ".( $sprite->{'rows'} * 2 * 8 );
    }
    foreach my $p ( @{$sprite->{'mask'}} ) {
        ( length( $p ) == $sprite->{'cols'} * 2 * 8 ) or
            die "Sprite '$sprite->{name}': MASK line should be of length ".( $sprite->{'rows'} * 2 * 8 );
    }

    # compile PIXELS string data to numeric data for output
    my $cur_row = 0;
    my $byte_count = 0;
    foreach my $p ( @{$sprite->{'pixels'}} ) {
        my @parts = unpack("(A16)*", $p );
        my $cur_col = 0;
        foreach my $b ( @parts ) {
            push @{$sprite->{'pixel_bytes'}[ $cur_row * $sprite->{'cols'} + $cur_col++ ] },
                pixels_to_byte( $b );
            if ( not ( ++$byte_count % ( 8 * $sprite->{'cols'} ) ) ) { $cur_row++; }
        }
    }

    # compile MASK string data to numeric data for output
    $cur_row = 0;
    $byte_count = 0;
    foreach my $p ( @{$sprite->{'mask'}} ) {
        my @parts = unpack("(A16)*", $p );
        my $cur_col = 0;
        foreach my $b ( @parts ) {
            push @{$sprite->{'mask_bytes'}[ $cur_row * $sprite->{'cols'} + $cur_col++ ] },
                pixels_to_byte( $b );
            if ( not ( ++$byte_count % ( 8 * $sprite->{'cols'} ) ) ) { $cur_row++; }
        }
    }

    # Always define the sequence 'Main', with all frames in order, first to last
    my $index = ( defined( $sprite->{'sequences'} ) ? scalar( @{ $sprite->{'sequences'} } ) : 0 );
    push @{ $sprite->{'sequences'} },
        { 'name' => 'Main', 'frames' => join( ',', 0 .. ( $sprite->{'frames'} - 1 ) ) };
    if ( scalar( grep { $_->{'name'} eq 'Main' } @{ $sprite->{'sequences'} } ) != 1 ) {
        die "Sprite '$sprite->{name}': SEQUENCE name 'Main' is reserved and should not be used\n";
    }
    $sprite->{'sequence_name_to_index'}{'Main'} = $index;

    # if the sprite has no 'sequence_delay' parameter, define as 1 (minimum;
    # 0 means 256, which is 5 seconds!)
    if ( not defined( $sprite->{'sequence_delay'} ) ) {
        $sprite->{'sequence_delay'} = 1;
    }

    # compile animation sequences
    foreach my $seq ( @{ $sprite->{'sequences'} } ) {
        $seq->{'frame_list'} = [ split( /,/, $seq->{'frames'} ) ];
    }
}

# SP1 pixel format for a masked sprite:
#  * Column oriented
#  * Each column:
#    * 8 x (0xff,0x00) pairs (blank first row)
#    * 8 x (mask,byte) pairs x M chars of the column
#    * 8 x (0xff,0x00) pairs (blank last row)
#  * Repeat for N columns
sub generate_sprite {
    my ( $sprite, $dataset ) = @_;
    my $sprite_rows = $sprite->{'rows'};
    my $sprite_cols = $sprite->{'cols'};
    my $sprite_frames = $sprite->{'frames'};
    my $sprite_name = $sprite->{'name'};

    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "// Sprite '%s'\n// Pixel and mask data ordered by column (required by SP1)\n\n", $sprite->{'name'} );

    # prepare mask and bytes lists
    my @col_bytes;
    my @mask_bytes;
    foreach my $frm ( 0 .. ( $sprite_frames - 1 ) ) {
        foreach my $col ( 0 .. ( $sprite_cols - 1 ) ) {
            push @col_bytes, (0) x 8;		# initial row with blank pixels and transparent mask
            push @mask_bytes, (0xff) x 8;
            foreach my $row ( 0 .. ( $sprite_rows - 1 ) ) {
                push @col_bytes, @{ $sprite->{'pixel_bytes'}[ ( $frm * $sprite_rows * $sprite_cols ) + $row * $sprite_cols + $col ] };
                push @mask_bytes,@{ $sprite->{'mask_bytes'}[ ( $frm * $sprite_rows * $sprite_cols ) + $row * $sprite_cols + $col ] };
            }
        }
    }
    push @col_bytes, (0) x 8;		# final row with blank pixels and transparent mask
    push @mask_bytes, (0xff) x 8;

    # group mask and pixel bytes by 16-byte lines for easier reading
    my @groups_of_2m;
    my $group_cnt = 0;
    my $byte_cnt = 0;
    foreach my $b ( zip( @mask_bytes, @col_bytes ) ) {
        push @{$groups_of_2m[ $group_cnt ]}, $b;
        $byte_cnt++;
        if ( not $byte_cnt % 16 ) {
            $group_cnt++;
        }
    }

    # output mask/pixel lines
    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "uint8_t sprite_%s_data[] = {\n%s\n};\n",
        $sprite->{'name'},
        join( ",\n", map { join( ", ", map { sprintf( "0x%02x", $_ ) } @{$_} ) } @groups_of_2m ) );

    # output list of pointers to frames
    my @frame_offsets;
    my $ptr = 16;	# initial frame: 8 bytes pixel + 8 bytes mask for the top blank row
    foreach ( 0 .. ( $sprite->{'frames'} - 1 ) ) {
        push @frame_offsets, $ptr;
        $ptr += 16 * ( $sprite->{'rows'} + 1 ) * $sprite->{'cols'};
    }
    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "uint8_t *sprite_%s_frames[] = {\n%s\n};\n",
        $sprite_name,
        join( ",\n", 
            map { sprintf( "\t&sprite_%s_data[%d]", $sprite_name, $_ ) }
            @frame_offsets
        ) );

    # output list of animation sequences
    if ( scalar( @{ $sprite->{'sequences'} } ) ) {
        push @{ $c_dataset_lines->{ $dataset } }, join( "", map {
            sprintf( "uint8_t sprite_%s_sequence_%s[%d] = { %s };\n",
                $sprite_name, $_->{'name'}, scalar( @{ $_->{'frame_list'} } ), join( ',', @{ $_->{'frame_list'} } ) );
        } @{ $sprite->{'sequences'} } );
        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "struct animation_sequence_s sprite_%s_sequences[%d] = {\n\t",
            $sprite_name, scalar( @{ $sprite->{'sequences'} } ) );
        push @{ $c_dataset_lines->{ $dataset } }, join( ",\n\t", map {
            sprintf( "{ %d, &sprite_%s_sequence_%s[0] }", scalar( @{ $_->{'frame_list'} } ), $sprite_name, $_->{'name'} );
        } @{ $sprite->{'sequences'} } );
        push @{ $c_dataset_lines->{ $dataset } }, "\n};\n\n";

    }

    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "// End of Sprite '%s'\n\n", $sprite_name );
}

######################################
## Map Screen functions
######################################

sub validate_screen {
    my $screen = shift;
    defined( $screen->{'name'} ) or
        die "Screen has no NAME\n";
    defined( $screen->{'hero'} ) or
        die "Screen '$screen->{name}' has no Hero\n";

    # check for reserved names
    if ( uc( $screen->{'name'} ) eq '__EVENTS__' ) {
        die "SCREEN: The screen name __EVENTS__ is reserved for internal purposes and cannot be used\n";
    }

    # if no dataset is specified, store the screen in home dataset
    if ( not defined( $screen->{'dataset'} ) ) {
        $screen->{'dataset'} = 'home';	# must be lowercase
    }

    # check each enemy
    foreach my $s ( @{$screen->{'enemies'}} ) {
        # set movement flags
        $s->{'movement_flags'} = join( " | ", 0,
            map { "F_ENEMY_MOVE_" . uc($_) }
            grep { $s->{$_} }
            qw( bounce change_sequence_horiz change_sequence_vert )
            );
        # define default animation sequences if none given
        if ( not defined( $s->{'sequence_a'} ) ) {
            $s->{'sequence_a'} = 'Main';
        }
        if ( not defined( $s->{'sequence_b'} ) ) {
            $s->{'sequence_b'} = 'Main';
        }
        if ( not defined( $s->{'initial_sequence'} ) ) {
            $s->{'initial_sequence'} = 'Main';
        }
        # check that it has an associated sprite
        defined( $s->{'sprite'} ) or
            die "SCREEN $screen->{name}: ENEMY $s->{name} has no associated sprite\n";
        # check that defined sequences exist for the given sprite
        foreach my $seq_param ( qw( sequence_a sequence_b initial_sequence ) ) {
            if ( defined( $s->{ $seq_param } ) and
                not defined( $all_sprites[ $sprite_name_to_index{ $s->{'sprite'} } ]{'sequence_name_to_index'}{ $s->{ $seq_param } } ) ) {
                    die "SCREEN $screen->{name}: ENEMY $s->{name}: sequence specified with ".uc($seq_param)." is not defined\n";
            }
        }
    }
}

sub compile_screen {
    my $screen = shift;
    # compile SCREEN_DATA lines
    compile_screen_data( $screen );

    ( scalar( @{$screen->{'btiles'}} ) > 0 ) or
        die "SCREEN: Screen '$screen->{name}' has no Btiles\n";

    # check if HARMFUL btiles are used and enable the BUILD_FEATURE
    foreach my $btile ( @{$screen->{'btiles'} } ) {
        if ( $btile->{'type'} eq 'HARMFUL' ) {
            add_build_feature( 'HARMFUL_BTILES' );
            add_build_feature( 'HERO_CHECK_TILES_BELOW' );
        }
    }

    # check if animated btiles are used, ensure all have the needed
    # paremeters and add build feature
    foreach my $btile ( @{$screen->{'btiles'} } ) {
        if ( defined( $btile->{'animation_delay'} ) or
            defined( $btile->{'sequence_delay'} ) or
            defined( $btile->{'sequence'} ) ) {

            # if any of the above are used, all of them must be specified
            if ( defined( $btile->{'animation_delay'} ) and
                defined( $btile->{'sequence_delay'} ) and
                defined( $btile->{'sequence'} ) ) {
                add_build_feature( 'ANIMATED_BTILES' );
                $btile->{'is_animated'} = 1;
            } else {
                die "SCREEN: Animated BTILES must define SEQUENCE, ANIMATION_DELAY and SEQUENCE_DELAY\n";
            }
        } else {
            $btile->{'is_animated'} = 0;
        }
    }

}

# SCREEN_DATA and DEFINE compilation
sub compile_screen_data {
    my $screen = shift;

    # map: digraph -> btile, type, row, col
    # this has been previously generated via the DEFINE directives
    my $screen_digraphs = $screen->{'digraphs'};
    my $screen_digraph_counters;

    # DATA and DEST arrays (see MAP-SCREEN-DATA-DESIGN.md)
    my $screen_data;
    my $screen_dest;
    # list of btiles generated from the SCREEN_DATA
    my @screen_btiles;

    # if no SCREEN_DATA lines exist, nothing to compile, return
    return if not defined( $screen->{'screen_data'} );

    # check that there are the right number of rows and columns according to GAME_AREA
    my $game_area_width = $game_config->{'game_area'}{'right'} - $game_config->{'game_area'}{'left'} + 1;
    my $game_area_height = $game_config->{'game_area'}{'bottom'} - $game_config->{'game_area'}{'top'} + 1;
    my $game_area_top = $game_config->{'game_area'}{'top'};
    my $game_area_left = $game_config->{'game_area'}{'left'};
    ( scalar( @{ $screen->{'screen_data'} } ) == $game_area_height ) or
        die "Screen '$screen->{name}': there must be exactly $game_area_height SCREEN_DATA lines\n";
    foreach my $sd ( @{ $screen->{'screen_data'} } ) {
        ( length( $sd ) == ( 2 * $game_area_width ) ) or
            die "Screen '$screen->{name}': SCREEN_DATA lines must be exactly ".( 2 * $game_area_height )." characters long\n";
    }

    # populate the DEST array
    foreach my $r ( 0 .. ( $game_area_height - 1 ) ) {
        foreach my $c ( 0 .. ( $game_area_width - 1 ) ) {
            $screen_dest->[ $r ][ $c ] = '  ';
        }
    }

    # populate the DATA array
    my $row = 0;
    foreach my $sd ( @{$screen->{'screen_data'}} ) {
        $screen_data->[$row++] = [ ( $sd =~ m/.{2}/g ) ];
    }

    # process the DATA array
    foreach my $r ( 0 .. ( $game_area_height - 1 ) ) {
        foreach my $c ( 0 .. ( $game_area_width - 1 ) ) {

            # ignore the cell if there is no tile in input data
            next if ( $screen_data->[ $r ][ $c ] eq '  ' );

            # there is a tile in DATA, so process it
            my $data_dg = $screen_data->[ $r ][ $c ];
            my $dest_dg = $screen_dest->[ $r ][ $c ];

            # if there is no tile in DEST, this is the first time we see the tile
            if ( $dest_dg eq '  ' ) {

                # make sure there is a tile DEFINEd with that digraph
                ( defined( $screen_digraphs->{ $data_dg } ) ) or
                    die "Screen '$screen->{name}': digraph '$data_dg' is undefined\n";

                # "paint" the tile in the DEST array
                my $btile = $all_btiles[ $btile_name_to_index{ $screen_digraphs->{ $data_dg }{'btile'} } ];
                foreach my $i ( 0 .. ( $btile->{'rows'} - 1 ) ) {
                    foreach my $j ( 0 .. ( $btile->{'cols'} - 1 ) ) {
                        $screen_dest->[ $r + $i ][ $c + $j ] = $data_dg;
                    }
                }

                # ...and add the tile to the tile list - we add a generated name
                push @screen_btiles, { 
                    name => sprintf( "%s_%03d",
                        $screen_digraphs->{ $data_dg }{'name'},
                        ( $screen_digraph_counters->{ $screen_digraphs->{ $data_dg }{'name'} }++ || 1 )
                        ),
                    btile => $screen_digraphs->{ $data_dg }{'btile'},
                    type => $screen_digraphs->{ $data_dg }{'type'},
                    row => $game_area_top + $r,
                    col => $game_area_left + $c,
                    active => 1,
                    asset_state_index => 'ASSET_NO_STATE',	# all tiles are immutable by default
                };

            # else if there is a tile in DEST and it is different from the one in DATA...
            } elsif ( $dest_dg ne $data_dg ) {

                # die: we do not allow overlapping btiles (for the moment)
                die "Screen '$screen->{name}': overlapping btiles at row=$r, col=$c\n";

            # and finally, if the tile in DEST and DATA match, ignore since it's correct (they should match)
            }
        }
    }

    # finally, check that both DATA and DEST array elements match one by one
    foreach my $r ( 0 .. ( $game_area_height - 1 ) ) {
        foreach my $c ( 0 .. ( $game_area_width - 1 ) ) {
            ( $screen_data->[ $r ][ $c ] eq $screen_dest->[ $r ][ $c ] ) or
                die "Screen '$screen->{name}': mismatching btiles at row=$r, col=$c\n";
        }
    }

    # at this point, all is correct and we have the list of btiles generated
    # from the SCREEN_DATA and DEFINE lines.  Add then to the general btile
    # list for the screen.
    push @{ $screen->{'btiles'} }, @screen_btiles;

}


sub generate_screen {
    my ( $screen, $dataset ) = @_;

    # generate the lists of dataset screens, sprites
    my @dataset_screens = map { $all_screens[ $_ ] } @{ $dataset_dependency{ $dataset }{'screens'} };

    my $btile_global_to_dataset_index = $dataset_dependency{ $dataset }{'btile_global_to_dataset_index'};
    my $sprite_global_to_dataset_index = $dataset_dependency{ $dataset }{'sprite_global_to_dataset_index'};
    my $rule_global_to_dataset_index = $dataset_dependency{ $dataset }{'rule_global_to_dataset_index'};

    # screen tiles
    if ( scalar( @{ $screen->{'btiles'} } ) ) {
        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "// Screen '%s' btile data\n", $screen->{'name'} );
        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "struct btile_pos_s screen_%s_btile_pos[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'btiles'}} ) );

        push @{ $c_dataset_lines->{ $dataset } }, join( ",\n", map {
                sprintf("\t{ .type = TT_%s, .row = %d, .col = %d, .btile_id = %d, .state_index = %s }",
                    uc($_->{'type'}), $_->{'row'}, $_->{'col'},
                    $btile_global_to_dataset_index->{ $btile_name_to_index{ $_->{'btile'} } },
                    ( "$_->{'asset_state_index'}" eq 'ASSET_NO_STATE' ? 'ASSET_NO_STATE' : $_->{'asset_state_index'} ) )
            } @{$screen->{'btiles'}} );
        push @{ $c_dataset_lines->{ $dataset } }, "\n};\n\n";

        # generate animated_btile_s records, they have been previously
        # classified with 'is_animated' = 1
        my $num_animated_btiles = scalar( grep { $_->{'is_animated'} } @{ $screen->{'btiles'} } );
        if ( $num_animated_btiles ) {
            push @{ $c_dataset_lines->{ $dataset } }, sprintf( "// Screen '%s' animated btile records\n", $screen->{'name'} );
            push @{ $c_dataset_lines->{ $dataset } }, sprintf( "struct animated_btile_s screen_%s_animated_btiles[ %d ] = {\n",
                $screen->{'name'},
                $num_animated_btiles
            );

            my $btile_pos_index = 0;
            foreach my $btile ( @{ $screen->{'btiles'} } ) {
                if ( $btile->{'is_animated'} ) {
                    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "\t{ .btile_id = %d, .btile_pos_id = %d, ",
                        $btile_global_to_dataset_index->{ $btile_name_to_index{ $btile->{'btile'} } },
                        $btile_pos_index,
                    );
                    push @{ $c_dataset_lines->{ $dataset } }, sprintf( ".anim.delay_data.frame_delay = %d, ",
                        $btile->{'animation_delay'}
                    );
                    push @{ $c_dataset_lines->{ $dataset } }, sprintf( ".anim.delay_data.sequence_delay = %d, ",
                        $btile->{'sequence_delay'}
                    );
                    push @{ $c_dataset_lines->{ $dataset } }, sprintf( ".anim.current.sequence = %d },\n",
                        $all_btiles[ $btile_name_to_index{ $btile->{'btile'} } ]{'sequence_name_to_index'}{ $btile->{'sequence'} }
                    );
                }
                $btile_pos_index++;
            }
            push @{ $c_dataset_lines->{ $dataset } }, "};\n\n";
        }
    }

    # screen enemies
    if ( scalar( @{ $screen->{'enemies'} } ) ) {
        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "// Screen '%s' enemy data\n", $screen->{'name'} );
        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "struct enemy_info_s screen_%s_enemies[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'enemies'}} ) );
        push @{ $c_dataset_lines->{ $dataset } }, join( ",\n", map {
                sprintf( "\t{ .sprite = %s, .num_graphic = %d, .color = %s,\n" .
                        "\t\t.animation = {\n" .
                        "\t\t\t.delay_data = { .frame_delay = %d, .sequence_delay = %d },\n" .
                        "\t\t\t.sequence_data = { .initial_sequence = %d },\n" .
                        "\t\t\t.current =  { .sequence = %d, .sequence_counter = %d, .frame_delay_counter = %d, .sequence_delay_counter = %d } },\n" .
                        "\t\t.position = { .x.value = %d , .y.value = %d, .xmax = %d, .ymax = %d },\n" .
                        "\t\t.movement = { .type = %s, .delay = %d, .delay_counter = %d,\n" .
                        "\t\t\t.data = { .%s = { %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d } },\n" .
                        "\t\t\t.flags = %s },\n" .
                        "\t\t.state_index = %s }",
                    # SP1 sprite pointer, will be initialized later
                    'NULL',
                    # index into global sprite graphics table
                    $sprite_global_to_dataset_index->{ $sprite_name_to_index{ $_->{'sprite'} } },
                    # color for the sprite
                    $_->{'color'},

                    # animation_data: delay_data values
                    $_->{'animation_delay'}, ( $_->{'sequence_delay'} || 0 ),
                    # animation_data: sequence_data values
                    $all_sprites[ $sprite_name_to_index{ $_->{'sprite'} } ]{'sequence_name_to_index'}{ $_->{'initial_sequence'} },
                    # animation_data: current values
                    0,0,0,0, # sequence number, sequence_counter, frame_delay_counter, sequence_delay_counter: will be initialized later

                    # position_data
                    0,0,0,0,				# position gets reset on initialization

                    # movement_data
                    sprintf( 'ENEMY_MOVE_%s', uc( $_->{'movement'} ) ),	# movement type
                    $_->{'speed_delay'},
                    0,				# initial delay counter
                    lc( $_->{'movement'} ),
                    $_->{'xmin'}, $_->{'xmax'},
                    $_->{'ymin'}, $_->{'ymax'},
                    $_->{'dx'}, $_->{'dy'},
                    $_->{'initx'}, $_->{'inity'},
                    $_->{'dx'}, $_->{'dy'},
                    $all_sprites[ $sprite_name_to_index{ $_->{'sprite'} } ]{'sequence_name_to_index'}{ $_->{'sequence_a'} },
                    $all_sprites[ $sprite_name_to_index{ $_->{'sprite'} } ]{'sequence_name_to_index'}{ $_->{'sequence_b'} },
                    # movement flags
                    $_->{'movement_flags'},

                    # state index
                    $_->{'asset_state_index'},
                 )
            } @{$screen->{'enemies'}} );
        push @{ $c_dataset_lines->{ $dataset } }, "\n};\n\n";
    }

    # screen items
    if ( scalar( @{ $screen->{'items'} } ) ) {
        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "// Screen '%s' item data\n", $screen->{'name'} );
        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "struct item_location_s screen_%s_items[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'items'}} ) );
        push @{ $c_dataset_lines->{ $dataset } }, join( ",\n", map {
                sprintf( "\t{ %d, %d, %d }", $_, $all_items[ $_ ]->{'row'}, $all_items[ $_ ]->{'col'} )
            } @{ $screen->{'items'} } );
        push @{ $c_dataset_lines->{ $dataset } }, "\n};\n\n";
    }

    # screen crumbs
    if ( defined( $screen->{'crumbs'} ) ) {
        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "// Screen '%s' crumb data\n", $screen->{'name'} );
        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "struct crumb_location_s screen_%s_crumbs[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'crumbs'}} ) );
        push @{ $c_dataset_lines->{ $dataset } }, join( ",\n", map {
                sprintf( "\t{ CRUMB_TYPE_%s, %d, %d, %d }",
                    uc( $_->{'type'} ),
                    $_->{'row'},
                    $_->{'col'},
                    $_->{'asset_state_index'}
                )
            } @{ $screen->{'crumbs'} } );
        push @{ $c_dataset_lines->{ $dataset } }, "\n};\n\n";
    }

    # hot zones
    if ( scalar( @{ $screen->{'hotzones'} } ) ) {
        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "// Screen '%s' hot zone data\n", $screen->{'name'} );
        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "struct hotzone_info_s screen_%s_hotzones[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'hotzones'}} ) );
        push @{ $c_dataset_lines->{ $dataset } }, join( ",\n", map {
                my $x    = ( defined( $_->{'x'} ) ? $_->{'x'} : $_->{'col'} * 8 );
                my $y    = ( defined( $_->{'y'} ) ? $_->{'y'} : $_->{'row'} * 8 );
                my $xmax = $x + ( defined( $_->{'pix_width'} ) ? $_->{'pix_width'} : $_->{'width'} * 8 ) - 1;
                my $ymax = $y + ( defined( $_->{'pix_height'} ) ? $_->{'pix_height'} : $_->{'height'} * 8 ) - 1;
                sprintf( "\t{ .position = { .x.part.integer = %d, .y.part.integer = %d, .xmax = %d, .ymax = %d }, .state_index = %s }",
                    $x, $y, $xmax, $ymax,
                    $_->{'asset_state_index'},
                )
            } @{ $screen->{'hotzones'} } );
        push @{ $c_dataset_lines->{ $dataset } }, "\n};\n\n";
    }

    # flow rules
    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "// Screen '%s' flow rules\n", $screen->{'name'} );
    foreach my $table ( @{ $syntax->{'valid_whens'} } ) {
        if ( defined( $screen->{'rules'} ) and defined( $screen->{'rules'}{ $table } ) ) {
            my $num_rules = scalar( @{ $screen->{'rules'}{ $table } } );
            if ( $num_rules ) {
                push @{ $c_dataset_lines->{ $dataset } }, sprintf( "struct flow_rule_s *screen_%s_%s_rules[ %d ] = {\n\t",
                    $screen->{'name'}, $table, $num_rules );
                push @{ $c_dataset_lines->{ $dataset } }, join( ",\n\t",
                    map {
                        sprintf( "&all_flow_rules[ %d ]", $rule_global_to_dataset_index->{ $_ } )
                    } @{ $screen->{'rules'}{ $table } }
                );
                push @{ $c_dataset_lines->{ $dataset } }, "\n};\n";
            }
        }
    }

}

###################################
## Hero functions
###################################

sub validate_and_compile_hero {
    my $hero = shift;
    defined( $hero->{'name'} ) or
        die "Hero has no NAME\n";
    defined( $hero->{'sprite'} ) or
        die "Hero has no SPRITE\n";
    defined( $hero->{'sequence_up'} ) or
        die "Hero has no SEQUENCE_UP\n";
    defined( $hero->{'sequence_down'} ) or
        die "Hero has no SEQUENCE_DOWN\n";
    defined( $hero->{'sequence_left'} ) or
        die "Hero has no SEQUENCE_LEFT\n";
    defined( $hero->{'sequence_right'} ) or
        die "Hero has no SEQUENCE_RIGHT\n";
    defined( $hero->{'animation_delay'} ) or
        die "Hero has no ANIMATION_DELAY\n";
    defined( $hero->{'lives'} ) or
        die "Hero has no LIVES\n";
    defined( $hero->{'hstep'} ) or
        die "Hero has no HSTEP\n";
    defined( $hero->{'vstep'} ) or
        die "Hero has no VSTEP\n";

    # ensure DAMAGE_MODE is always defined
    # remember LIVES are handled separately for compatibility
    my $default_damage_mode = {
        health_max	=> 1,
        enemy_damage	=> 1,
        immunity_period	=> 0,
    };
    my $damage_mode;
    if ( defined( $hero->{'damage_mode'} ) ) {
        # merge the provided parameters with the defaults
        $damage_mode = { %{ $default_damage_mode }, %{ $hero->{'damage_mode'} } };
    } else {
        $damage_mode = $default_damage_mode;
    }
    $hero->{'damage_mode'} = $damage_mode;

    # check for bullet
    if ( defined( $hero->{'bullet'} ) ) {
        add_build_feature( 'HERO_HAS_WEAPON' );
        if ( defined( $hero->{'bullet'}{'initially_enabled'} ) ) {
            add_build_feature( 'INVENTORY' );	# if it not initially enabled we need inventory
            if ( ( not $hero->{'bullet'}{'initially_enabled'} ) and not defined( $hero->{'bullet'}{'weapon_item'} ) ) {
                die "HERO: When BULLET is INITIALLY_ENABLED=0, a WEAPON_ITEM is needed\n";
            }
        } else {
            $hero->{'bullet'}{'initially_enabled'} = 1;
            add_build_feature( 'HERO_WEAPON_ALWAYS_ENABLED' );
        }
        if ( $hero->{'bullet'}{'autofire'} || 0 ) {
            add_build_feature( 'HERO_WEAPON_AUTOFIRE' );
        }
    }
}

sub generate_hero {
    my $num_lives 		= $hero->{'lives'}{'num_lives'};
    my $lives_btile_num		= 'BTILE_ID_' . uc( $hero->{'lives'}{'btile'} );
    my $sprite			= $hero->{'sprite'};
    my $num_sprite		= $sprite_name_to_index{ $hero->{'sprite'} };
    my $width			= $all_sprites[ $num_sprite ]{'cols'} * 8;
    my $height			= $all_sprites[ $num_sprite ]{'rows'} * 8;
    my $sequence_up		= $all_sprites[ $num_sprite ]{'sequence_name_to_index'}{ $hero->{'sequence_up'} };
    my $sequence_down		= $all_sprites[ $num_sprite ]{'sequence_name_to_index'}{ $hero->{'sequence_down'} };
    my $sequence_left		= $all_sprites[ $num_sprite ]{'sequence_name_to_index'}{ $hero->{'sequence_left'} };
    my $sequence_right		= $all_sprites[ $num_sprite ]{'sequence_name_to_index'}{ $hero->{'sequence_right'} };
    my $steady_frame_up		= $hero->{'steady_frames'}{'up'} || 0;
    my $steady_frame_down	= $hero->{'steady_frames'}{'down'} || 0;
    my $steady_frame_left	= $hero->{'steady_frames'}{'left'} || 0;
    my $steady_frame_right	= $hero->{'steady_frames'}{'right'} || 0;
    my $delay			= $hero->{'animation_delay'};
    my $hstep			= $hero->{'hstep'};
    my $vstep			= $hero->{'vstep'};
    my $hstep_ffp		= int( 256 * $hero->{'hstep'} );
    my $vstep_ffp		= int( 256 * $hero->{'vstep'} );
    my $local_num_sprite	= $dataset_dependency{'home'}{'sprite_global_to_dataset_index'}{ $num_sprite };
    my $health_max		= $hero->{'damage_mode'}{'health_max'};
    my $enemy_damage		= $hero->{'damage_mode'}{'enemy_damage'};
    my $immunity_period		= $hero->{'damage_mode'}{'immunity_period'};
    my $health_display_function	= $hero->{'damage_mode'}{'health_display_function'} || '';

    my $move_xmin		= $game_config->{'game_area'}{'left'} * 8;
    my $move_xmax		= ( $game_config->{'game_area'}{'right'} + 1 ) * 8 - $width;
    my $move_ymin		= $game_config->{'game_area'}{'top'} * 8;
    my $move_ymax		= ( $game_config->{'game_area'}{'bottom'} + 1 ) * 8 - $height;

    push @h_game_data_lines, <<EOF_HERO1

/////////////////////////////
// Hero definition
/////////////////////////////

#define	HERO_SPRITE_ID			$local_num_sprite
#define	HERO_SPRITE_SEQUENCE_UP		$sequence_up
#define	HERO_SPRITE_SEQUENCE_DOWN	$sequence_down
#define	HERO_SPRITE_SEQUENCE_LEFT	$sequence_left
#define	HERO_SPRITE_SEQUENCE_RIGHT	$sequence_right
#define	HERO_SPRITE_STEADY_FRAME_UP	$steady_frame_up
#define	HERO_SPRITE_STEADY_FRAME_DOWN	$steady_frame_down
#define	HERO_SPRITE_STEADY_FRAME_LEFT	$steady_frame_left
#define	HERO_SPRITE_STEADY_FRAME_RIGHT	$steady_frame_right
#define	HERO_SPRITE_ANIMATION_DELAY	$delay
#define HERO_SPRITE_WIDTH		$width
#define HERO_SPRITE_HEIGHT		$height
// FFP value: 256 * $hstep
#define	HERO_MOVE_HSTEP			$hstep_ffp
// FFP value: 256 * $vstep
#define	HERO_MOVE_VSTEP			$vstep_ffp
#define	HERO_MOVE_XMIN			$move_xmin
#define	HERO_MOVE_XMAX			$move_xmax
#define	HERO_MOVE_YMIN			$move_ymin
#define	HERO_MOVE_YMAX			$move_ymax
#define	HERO_NUM_LIVES			$num_lives
#define	HERO_LIVES_BTILE_NUM		$lives_btile_num
#define HERO_HEALTH_MAX			$health_max
#define HERO_ENEMY_DAMAGE		$enemy_damage
#define HERO_IMMUNITY_PERIOD		$immunity_period
#define HERO_HEALTH_DISPLAY_FUNCTION	$health_display_function

EOF_HERO1
;

    if ( $health_display_function ne '' ) {
        push @h_game_data_lines, "// external declaration for custom health display function\n";
        push @h_game_data_lines, "void $health_display_function( void );\n\n";
    }

    # hero sprite must be always available - output sprite into home bank
}

sub generate_bullets {

    return if not defined( $hero->{'bullet'} );
    
    my $sprite = $all_sprites[ $sprite_name_to_index{ $hero->{'bullet'}{'sprite'} } ];
    my $sprite_name = $hero->{'bullet'}{'sprite'};
    my $sprite_index = $sprite_name_to_index{ $hero->{'bullet'}{'sprite'} };
    my $local_sprite_index = $dataset_dependency{'home'}{'sprite_global_to_dataset_index'}{ $sprite_index };
    my $width = $sprite->{'cols'} * 8;
    my $height = $sprite->{'rows'} * 8;
    my $max_bullets = $hero->{'bullet'}{'max_bullets'};
    my $dx = $hero->{'bullet'}{'dx'};
    my $dy = $hero->{'bullet'}{'dy'};
    my $delay = $hero->{'bullet'}{'delay'};
    my $reload_delay = $hero->{'bullet'}{'reload_delay'};
    my $xthresh = ( defined( $sprite->{'real_pixel_width'} ) ?
        ( 8 - ( $sprite->{'real_pixel_width'} % 8 ) + 1 ) % 8 :
        1 );
    my $ythresh = ( defined( $sprite->{'real_pixel_height'} ) ?
        ( 8 - ( $sprite->{'real_pixel_height'} % 8 ) + 1 ) % 8 :
        1 );
    # sprite frames for the different shot directions. If not defined, use frame 0
    my ( $sprite_frame_up, $sprite_frame_down, $sprite_frame_left, $sprite_frame_right ) = map {
        $hero->{'bullet'}{ $_ } || 0,
    } qw ( sprite_frame_up sprite_frame_down sprite_frame_left sprite_frame_right );

    my $initial_enable = $hero->{'bullet'}{'initially_enabled'} ? 'F_HERO_CAN_SHOOT' : 0;

    push @h_game_data_lines, <<EOF_BULLET4

//////////////////////////////
// Bullets definition
//////////////////////////////

#define	BULLET_MAX_BULLETS		$max_bullets
#define	BULLET_SPRITE_WIDTH		$width
#define	BULLET_SPRITE_HEIGHT		$height
#define BULLET_SPRITE_ID		$local_sprite_index
#define	BULLET_SPRITE_XTHRESH		$xthresh
#define	BULLET_SPRITE_YTHRESH		$ythresh
#define	BULLET_MOVEMENT_DX		$dx
#define	BULLET_MOVEMENT_DY		$dy
#define	BULLET_MOVEMENT_DELAY		$delay
#define	BULLET_RELOAD_DELAY		$reload_delay
#define BULLET_SPRITE_FRAME_UP		$sprite_frame_up
#define BULLET_SPRITE_FRAME_DOWN	$sprite_frame_down
#define BULLET_SPRITE_FRAME_LEFT	$sprite_frame_left
#define BULLET_SPRITE_FRAME_RIGHT	$sprite_frame_right

#define BULLET_INITIAL_ENABLE		$initial_enable

EOF_BULLET4
;

    push @c_game_data_lines, <<EOF_BULLET5

//////////////////////////////
// Bullets definition
//////////////////////////////

struct bullet_state_data_s bullet_state_data[ BULLET_MAX_BULLETS ] = {
EOF_BULLET5
;
    foreach ( 1 .. $max_bullets ) {
        push @c_game_data_lines, "\t{ NULL, { .x.value = 0, .y.value = 0, .xmax = 0, .ymax = 0 }, 0, 0, 0, NULL, 0 },\n";
    }
    push @c_game_data_lines, "};\n\n";

    # bullet sprite must be always available - output sprite into home bank
}

########################
## Item functions
########################

sub generate_items {

    # do not generate anything related to inventory if no items defined
    return if ( not scalar( @all_items ) );

    my $max_items = scalar( @all_items );
    my $all_items_mask = 0;
    my $mask = 1;
    foreach my $i ( 1 .. $max_items ) {
        $all_items_mask += $mask;
        $mask <<= 1;
    }

    push @h_game_data_lines, <<GAME_DATA_H_3

// Global Items table
#define INVENTORY_MAX_ITEMS $max_items
#define INVENTORY_ALL_ITEMS_MASK $all_items_mask
extern struct item_info_s all_items[];

// Item constants
GAME_DATA_H_3
;

    # output constants for inventory items
    foreach my $i ( 0 .. ($max_items - 1) ) {
        my $item = $all_items[ $i ];
        my $item_mask = 1 << $i;
        push @h_game_data_lines, sprintf( "#define\tINVENTORY_ITEM_%s\t%d\n",
            uc( $item->{'name'} ), $item_mask
        );
        push @h_game_data_lines, sprintf( "#define\tINVENTORY_ITEM_%s_NUM\t%d\n",
            uc( $item->{'name'} ), $i
        );
    }
    push @h_game_data_lines, "\n";

    # output Inventory item for weapon if selected
    if ( defined( $hero->{'bullet'} ) ) {
        if ( defined( $hero->{'bullet'}{'weapon_item'} ) ) {
            push @h_game_data_lines, sprintf( "#define WEAPON_ITEM INVENTORY_ITEM_%s\n", uc( $hero->{'bullet'}{'weapon_item'} ) );
            push @h_game_data_lines, sprintf( "#define WEAPON_ITEM_NUM INVENTORY_ITEM_%s_NUM\n", uc( $hero->{'bullet'}{'weapon_item'} ) );
        }
    }

    push @c_game_data_lines, <<EOF_ITEMS1

///////////////////////
// Global items table
///////////////////////

struct item_info_s all_items[ INVENTORY_MAX_ITEMS ] = {
EOF_ITEMS1
;
    push @c_game_data_lines, join( ",\n",
        map {
            sprintf( "\t{ BTILE_ID_%s, 0x%04x, F_ITEM_ACTIVE }",
                uc( $all_items[ $_ ]{'btile'} ),
                ( 0x1 << $_ ),
            )
        } ( 0 .. ( $max_items - 1 ) )
    );

    push @c_game_data_lines, <<EOF_ITEMS2

};

EOF_ITEMS2
;

}

########################
## Crumb functions
########################

sub generate_crumb_types {

    # do not generate anything related to inventory if no items defined
    return if ( not scalar( @all_crumb_types ) );

    my $crumb_num_types = scalar( @all_crumb_types );

    push @h_game_data_lines, <<GAME_DATA_H_2

// Global Crumb Types table
#define CRUMB_NUM_TYPES $crumb_num_types

// Crumb constants
GAME_DATA_H_2
;

    # output constants for crumb types
    foreach my $i ( 0 .. ( $crumb_num_types - 1 ) ) {
        push @h_game_data_lines, sprintf( "#define\tCRUMB_TYPE_%s\t%d\n",
            uc( $all_crumb_types[ $i ]{'name'} ), $i
        );
    }
    push @h_game_data_lines, "\n";

    push @c_game_data_lines, <<EOF_CRUMBS1

/////////////////////////////////
// Global Crumb Types table
/////////////////////////////////

struct crumb_info_s all_crumb_types[ CRUMB_NUM_TYPES ] = {
EOF_CRUMBS1
;
    push @c_game_data_lines, join( ",\n",
        map {
            sprintf( "\t{ .btile_num = BTILE_ID_%s, .counter = 0, .do_action = %s, .required_items = %s }",
                uc( $all_crumb_types[ $_ ]{'btile'} ),
                $all_crumb_types[ $_ ]{'action_function'} || 'NULL',
                $all_crumb_types[ $_ ]{'required_items'} || 0,
            )
        } ( 0 .. ( $crumb_num_types - 1 ) )
    );

    push @c_game_data_lines, <<EOF_CRUMBS2

};

EOF_CRUMBS2
;

}

########################
## Game functions
########################

sub generate_game_functions {
    push @h_game_data_lines, "// game config\n";

    # generate extern declarations, only for functions in 'home' codeset
    push @h_game_data_lines, join( "\n", 
        map {
            sprintf( "void %s( void );", $game_config->{'game_functions'}{ $_ }{'name'} )
        } grep {
            ( $game_config->{'zx_target'} eq '48' ) or
            ( $game_config->{'game_functions'}{ $_ }{'codeset'} eq 'home' )
        } grep {
            $_ ne 'custom'
        } sort keys %{ $game_config->{'game_functions'} } );
    push @h_game_data_lines, "\n\n";

    # generate macro calls for all functions
    push @h_game_data_lines, join( "\n", 
        map {
            sprintf( "#define run_game_function_%-30s %s",
                lc( $_ ) . '()',
                ( defined( $game_config->{'game_functions'}{ $_ } ) ?
                  $game_config->{'game_functions'}{ $_ }{'codeset_function_call_macro'} :
                  '' ),
            )
        } grep {
            $_ ne 'custom'
        } sort @valid_game_functions
    );

    push @h_game_data_lines, "\n\n";
}

###########################
## Game Area functions
###########################

sub generate_single_game_area {
    my $area = shift;
    return if not defined ( $game_config->{ $area } );
    push @c_game_data_lines, "\n" . join( "\n", map {
        sprintf( "struct sp1_Rect %s = { %s_TOP, %s_LEFT, %s_WIDTH, %s_HEIGHT };",
            $_, ( uc( $_ ) ) x 4 )
        } ( $area )
    ) . "\n";
    push @h_game_data_lines, "\n" . join( "\n", map {
            "// " .uc( $_ ). " definitions\n" .
            sprintf( "#define %s_TOP	%d\n", uc( $_ ), $game_config->{ $_ }{'top'} ) .
            sprintf( "#define %s_LEFT	%d\n", uc( $_ ), $game_config->{ $_ }{'left'} ) .
            sprintf( "#define %s_BOTTOM	%d\n", uc( $_ ), $game_config->{ $_ }{'bottom'} ) .
            sprintf( "#define %s_RIGHT	%d\n", uc( $_ ), $game_config->{ $_ }{'right'} ) .
            sprintf( "#define %s_WIDTH	( %s_RIGHT - %s_LEFT + 1 )\n", uc( $_ ), uc( $_ ), uc( $_ ) ) .
            sprintf( "#define %s_HEIGHT	( %s_BOTTOM - %s_TOP + 1 )\n", uc( $_ ), uc( $_ ), uc( $_ ) ) .
            sprintf( "extern struct sp1_Rect %s;\n", $_ )
        } ( $area )
    ) . "\n\n";
}

sub generate_game_areas {

    # output mandatory game areas
    push @c_game_data_lines, "// screen areas\n";
    foreach my $area ( qw( game_area lives_area debug_area ) ) {
        generate_single_game_area( $area );
    }

    # output optional game areas
    if ( is_build_feature_enabled( 'INVENTORY' ) ) {
        generate_single_game_area( 'inventory_area' );
    }
    if ( is_build_feature_enabled( 'SCREEN_TITLES' ) ) {
        generate_single_game_area( 'title_area' );
    }

}

###################################
## flowgen rule functions
###################################

sub find_existing_rule_index {
    my $rule = shift;
    foreach my $i ( 0 .. ( scalar( @all_rules ) - 1 ) ) {
        return $i if Compare( $rule, $all_rules[ $i ] );
    }
    return undef;
}

sub validate_and_compile_rule {
    my $rule = shift;

    # validate rule
    defined( $rule->{'screen'} ) or
        die "Rule has no SCREEN\n";
    my $screen = $rule->{'screen'};
    if ( $screen ne '__EVENTS__' ) {
        exists( $screen_name_to_index{ $screen } ) or
            die "Screen '$screen' is not defined\n";
    }

    # WHEN clause is optional when the rule is assigned to __EVENTS__
    if ( $rule->{'screen'} ne '__EVENTS__' ) {
        defined( $rule->{'when'} ) or
            die "Rule has no WHEN clause\n";
        my $when = $rule->{'when'};
        grep { $when eq $_ } @{ $syntax->{'valid_whens'} } or
            die "WHEN must be one of ".join( ", ", map { uc } @{ $syntax->{'valid_whens'} } )."\n";
    }

    # we explictly allow rules with no checks, which are run always
#    defined( $rule->{'check'} ) and scalar( @{ $rule->{'check'} } ) or
#        die "At least one CHECK clause must be specified\n";

    defined( $rule->{'do'} ) and scalar( @{ $rule->{'do'} } ) or
        die "At least one DO clause must be specified\n";

    # do any special filtering of values

    # check filtering
    foreach my $chk ( @{ $rule->{'check'} } ) {
        $chk =~ m/^(\w+)\s*(.*)$/;
        my ( $check, $check_data ) = ( $1, $2 );

        # hotzone filtering
        if ( $check =~ /^HERO_OVER_HOTZONE$/ ) {
            $check_data = $all_screens[ $screen_name_to_index{ $rule->{'screen'} } ]{'hotzone_name_to_index'}{ $check_data };
        }

        # check custom function filtering
        if ( $check =~ /^CALL_CUSTOM_FUNCTION/ ) {
            my $vars = {
                map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                split( /\s+/, $check_data )
            };
            defined( $vars->{'name'} ) or
                die "CALL_CUSTOM_FUNCTION: NAME parameter is mandatory\n";
            my $index;
            if ( defined( $check_custom_function_id{ $vars->{'name'} } ) ) {
                $index = $check_custom_function_id{ $vars->{'name'} };
            } else {
                $index = scalar( @check_custom_functions );
                $check_custom_function_id{ $vars->{'name'} } = $index;
                push @check_custom_functions, {
                    index		=> $index,
                    function		=> $vars->{'name'},
                    uses_param		=> ( defined( $vars->{'param'} ) ? 1 : 0 ),
                };
            }
            $check_data = sprintf( "{ .function_id = %d, .param = %s }", $index, $vars->{'param'} || 0 );
        }

        # flow_vars specifics
        if ( $check =~ /^FLOW_VAR/ ) {
            my $vars = {
                map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                split( /\s+/, $check_data )
            };
            if ( not defined( $max_flow_var_id ) or ( $vars->{'var_id'} > $max_flow_var_id ) ) {
                $max_flow_var_id = $vars->{'var_id'};
            }
            $check_data = sprintf( "{ .var_id = %s, .value = %s }",
                $vars->{'var_id'}, $vars->{'value'} );
            add_build_feature( 'FLOW_VARS' );
        }

        # game_time specifics
        if ( $check =~ /^GAME_TIME_/ ) {
            add_build_feature( 'GAME_TIME' );
        }

        # regenerate the check with filtered data
        $chk = sprintf( "%s\t%s", $check, $check_data );
    }

    # action filtering
    foreach my $do ( @{ $rule->{'do'} } ) {
        $do =~ m/^(\w+)\s*(.*)$/;
        my ( $action, $action_data ) = ( $1, $2 );

        # hotzone filtering
        if ( $action =~ /^(ENABLE|DISABLE)_HOTZONE$/ ) {
            $action_data = $all_screens[ $screen_name_to_index{ $rule->{'screen'} } ]{'hotzone_name_to_index'}{ $action_data };
        }

        # warp_to_screen filtering
        if ( $action =~ /^WARP_TO_SCREEN$/ ) {
            my $vars = { 
                map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                split( /\s+/, $action_data )
            };
            my @flag_list;
            if ( not defined( $vars->{'dest_hero_x'} ) ) {
                push @flag_list, 'ACTION_WARP_TO_SCREEN_KEEP_HERO_X';
            }
            if ( not defined( $vars->{'dest_hero_y'} ) ) {
                push @flag_list, 'ACTION_WARP_TO_SCREEN_KEEP_HERO_Y';
            }
            my $flags = ( scalar( @flag_list ) ? join( " | ", @flag_list ) : 0 );
            $action_data = sprintf( "{ .num_screen = %d, .hero_x = %d, .hero_y = %d, .flags = %s }",
                $screen_name_to_index{ $vars->{'dest_screen'} },
                ( $vars->{'dest_hero_x'} || 0 ), ( $vars->{'dest_hero_y'} || 0 ),
                $flags,
            );
        }

        # btile filtering
        if ( $action =~ /^(ENABLE|DISABLE)_BTILE$/ ) {
            $action_data = $all_screens[ $screen_name_to_index{ $rule->{'screen'} } ]{'btile_name_to_index'}{ $action_data };
        }

        # enemy filtering
        if ( $action =~ /^(ENABLE|DISABLE)_ENEMY$/ ) {
            $action_data = $all_screens[ $screen_name_to_index{ $rule->{'screen'} } ]{'enemy_name_to_index'}{ $action_data };
        }

        # set/reset screen flag filtering
        if ( $action =~ /^(SET|RESET)_SCREEN_FLAG$/ ) {
            my $vars = { 
                map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                split( /\s+/, $action_data )
            };
            $action_data = sprintf( "{ .num_screen = %d, .flag = %s }",
                $screen_name_to_index{ $vars->{'screen'} },
                ( $vars->{'flag'} || 0 ),
            );
        }

        # custom action function filtering
        if ( $action =~ /^CALL_CUSTOM_FUNCTION/ ) {
            my $vars = {
                map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                split( /\s+/, $action_data )
            };
            defined( $vars->{'name'} ) or
                die "CALL_CUSTOM_FUNCTION: NAME parameter is mandatory\n";
            my $index;
            if ( defined( $action_custom_function_id{ $vars->{'name'} } ) ) {
                $index = $action_custom_function_id{ $vars->{'name'} };
            } else {
                $index = scalar( @action_custom_functions );
                $action_custom_function_id{ $vars->{'name'} } = $index;
                push @action_custom_functions, {
                    index		=> $index,
                    function		=> $vars->{'name'},
                    uses_param		=> ( defined( $vars->{'param'} ) ? 1 : 0 ),
                };
            }
            $action_data = sprintf( "{ .function_id = %d, .param = %s }", $index, $vars->{'param'} || 0 );
        }

        # flow_vars specifics
        if ( $action =~ /^FLOW_VAR/ ) {
            my $vars = {
                map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                split( /\s+/, $action_data )
            };
            if ( not defined( $max_flow_var_id ) or ( $vars->{'var_id'} > $max_flow_var_id ) ) {
                $max_flow_var_id = $vars->{'var_id'};
            }
            $action_data = sprintf( "{ .var_id = %s, .value = %s }",
                $vars->{'var_id'}, $vars->{'value'} || 0 );
            add_build_feature( 'FLOW_VARS' );
        }

        # tracker_select_song specific
        if ( $action =~ /^TRACKER_SELECT_SONG/ ) {
            # $action_data may contain the song name - convert into the song
            # index into the songs table
            if ( defined( $game_config->{'tracker'}{'song_index'}{ $action_data } ) ) {
                $action_data = $game_config->{'tracker'}{'song_index'}{ $action_data };
            }
        }

        # regenerate the value with the filtered data
        $do = sprintf( "%s\t%s", $action, $action_data );
    }

    # generate conditional build features for this rule: checks and actions
    foreach my $chk ( @{ $rule->{'check'} } ) {
        my ( $check, $check_data ) = split( /\s+/, $chk );
        my $id = sprintf( 'FLOW_RULE_CHECK_%s', uc( $check ) );
        add_build_feature( $id );
    }
    foreach my $do ( @{ $rule->{'do'} } ) {
        $do =~ m/^(\w+)\s*(.*)$/;
        my ( $action, $action_data ) = ( $1, $2 );
        my $id = sprintf( 'FLOW_RULE_ACTION_%s', uc( $action ) );
        add_build_feature( $id );
    }

    1;
}

# struct initializer formats depending on the check and action names
my $check_data_output_format = {
    GAME_FLAG_IS_SET		=> ".data.flag_state.flag = %s",
    GAME_FLAG_IS_RESET		=> ".data.flag_state.flag = %s",
    LOOP_FLAG_IS_SET		=> ".data.flag_state.flag = %s",
    LOOP_FLAG_IS_RESET		=> ".data.flag_state.flag = %s",
    USER_FLAG_IS_SET		=> ".data.flag_state.flag = %s",
    USER_FLAG_IS_RESET		=> ".data.flag_state.flag = %s",
    LIVES_EQUAL			=> ".data.lives.count = %d",
    LIVES_MORE_THAN		=> ".data.lives.count = %d",
    LIVES_LESS_THAN		=> ".data.lives.count = %d",
    ENEMIES_ALIVE_EQUAL		=> ".data.enemies.count = %d",
    ENEMIES_ALIVE_MORE_THAN	=> ".data.enemies.count = %d",
    ENEMIES_ALIVE_LESS_THAN	=> ".data.enemies.count = %d",
    ENEMIES_KILLED_EQUAL	=> ".data.enemies.count = %d",
    ENEMIES_KILLED_MORE_THAN	=> ".data.enemies.count = %d",
    ENEMIES_KILLED_LESS_THAN	=> ".data.enemies.count = %d",
    CALL_CUSTOM_FUNCTION	=> ".data.custom = %s",
    ITEM_IS_OWNED		=> ".data.item.item_id = %s",
    HERO_OVER_HOTZONE		=> ".data.hotzone.num_hotzone = %s",
    SCREEN_FLAG_IS_SET		=> ".data.flag_state.flag = %s",
    SCREEN_FLAG_IS_RESET	=> ".data.flag_state.flag = %s",
    FLOW_VAR_EQUAL		=> ".data.flow_var = %s",
    FLOW_VAR_MORE_THAN		=> ".data.flow_var = %s",
    FLOW_VAR_LESS_THAN		=> ".data.flow_var = %s",
    GAME_TIME_EQUAL		=> ".data.game_time.seconds = %s",
    GAME_TIME_MORE_THAN		=> ".data.game_time.seconds = %s",
    GAME_TIME_LESS_THAN		=> ".data.game_time.seconds = %s",
    GAME_EVENT_HAPPENED		=> ".data.game_event.event = %s",
    ITEM_IS_NOT_OWNED		=> ".data.item.item_id = %s",
};

my $action_data_output_format = {
    SET_USER_FLAG		=> ".data.user_flag.flag = %s",
    RESET_USER_FLAG		=> ".data.user_flag.flag = %s",
    INC_LIVES			=> ".data.lives.count = %s",
    PLAY_SOUND			=> ".data.play_sound.sound_id = %s",
    CALL_CUSTOM_FUNCTION	=> ".data.custom = %s",
    END_OF_GAME			=> ".data.unused = %d",
    WARP_TO_SCREEN		=> ".data.warp_to_screen = %s",
    ENABLE_HOTZONE		=> ".data.hotzone.num_hotzone = %d",
    DISABLE_HOTZONE		=> ".data.hotzone.num_hotzone = %d",
    ENABLE_BTILE		=> ".data.btile.num_btile = %d",
    DISABLE_BTILE		=> ".data.btile.num_btile = %d",
    ADD_TO_INVENTORY		=> ".data.item.item_id = %s",
    REMOVE_FROM_INVENTORY	=> ".data.item.item_id = %s",
    SET_SCREEN_FLAG		=> ".data.screen_flag = %s",
    RESET_SCREEN_FLAG		=> ".data.screen_flag = %s",
    FLOW_VAR_STORE		=> ".data.flow_var = %s",
    FLOW_VAR_INC		=> ".data.flow_var = %s",
    FLOW_VAR_ADD		=> ".data.flow_var = %s",
    FLOW_VAR_DEC		=> ".data.flow_var = %s",
    FLOW_VAR_SUB		=> ".data.flow_var = %s",
    TRACKER_SELECT_SONG		=> ".data.tracker_song.num_song = %s",
    TRACKER_MUSIC_STOP		=> ".data.unused = %d",
    TRACKER_MUSIC_START		=> ".data.unused = %d",
    TRACKER_PLAY_FX		=> ".data.tracker_fx.num_effect = %d",
    HERO_ENABLE_WEAPON		=> ".data.unused = %d",
    HERO_DISABLE_WEAPON		=> ".data.unused = %d",
    ENABLE_ENEMY		=> ".data.enemy.num_enemy = %d",
    DISABLE_ENEMY		=> ".data.enemy.num_enemy = %d",
};

sub generate_rule_checks {
    my ( $rule, $index ) = @_;
    my $num_checks = scalar( @{ $rule->{'check'} } );

    return if ( not scalar( @{ $rule->{'check'} } ) );

    my $output = sprintf( "struct flow_rule_check_s flow_rule_checks_%05d[%d] = {\n",
        $index, $num_checks );
    foreach my $ch ( @{ $rule->{'check'} } ) {
        $ch =~ m/^(\w+)\s*(.*)$/;
        my ( $check, $check_data ) = ( $1, $2 );
        $output .= sprintf( "\t{ .type = RULE_CHECK_%s, %s },\n",
            $check,
            sprintf( $check_data_output_format->{ $check }, $check_data || 0 )
        );
    }
    $output .= "};\n\n";
    return $output;
}

sub generate_rule_actions {
    my ( $rule, $index ) = @_;
    my $num_actions = scalar( @{ $rule->{'do'} } );
    my $output = sprintf( "struct flow_rule_action_s flow_rule_actions_%05d[%d] = {\n",
        $index, $num_actions );
    foreach my $ac ( @{ $rule->{'do'} } ) {
        $ac =~ m/^(\w+)\s*(.*)$/;
        my ( $action, $action_data ) = ( $1, $2 );
        $output .= sprintf( "\t{ .type = RULE_ACTION_%s, %s },\n",
            $action,
            sprintf( $action_data_output_format->{ $action }, $action_data || 0 )
        );
    }
    $output .= "};\n\n";
    return $output;
}

sub generate_flow_rules {
    my $dataset = shift;

    # generate the list of dataset rules, return immediately if empty
    my @dataset_rules = map { $all_rules[ $_ ] } @{ $dataset_dependency{ $dataset }{'rules'} };
    return if not scalar( @dataset_rules );

    # file header comments
    push @{ $c_dataset_lines->{ $dataset } }, <<FLOW_DATA_C_1

///////////////////////////////////////////////////////////
//
// Flow data
//
///////////////////////////////////////////////////////////

FLOW_DATA_C_1
;

    # output check and action tables for each rule
    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "// check tables for all dataset rules\n" );
    foreach my $i ( 0 .. scalar( @dataset_rules )-1 ) {
        push @{ $c_dataset_lines->{ $dataset } }, generate_rule_checks( $dataset_rules[ $i ], $i );
    }
    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "// action tables for all dataset rules\n" );
    foreach my $i ( 0 .. scalar( @dataset_rules )-1 ) {
        push @{ $c_dataset_lines->{ $dataset } }, generate_rule_actions( $dataset_rules[ $i ], $i );
    }

    # output dataset rule table
    if ( scalar( @dataset_rules ) ) {
        push @{ $c_dataset_lines->{ $dataset } }, sprintf(  "// Dataset %s rule table\n\n#define FLOW_NUM_RULES\t%d\n",
            $dataset, scalar( @dataset_rules ) );
        push @{ $c_dataset_lines->{ $dataset } }, "struct flow_rule_s all_flow_rules[ FLOW_NUM_RULES ] = {\n";
        foreach my $i ( 0 .. scalar( @dataset_rules )-1 ) {
            push @{ $c_dataset_lines->{ $dataset } }, "\t{";
            push @{ $c_dataset_lines->{ $dataset } }, sprintf( " .num_checks = %d, .checks = %s,",
                scalar( @{ $dataset_rules[ $i ]{'check'} } ),
                ( scalar( @{ $dataset_rules[ $i ]{'check'} } ) ? sprintf( "&flow_rule_checks_%05d[0]", $i ) : 'NULL' )
            );
            push @{ $c_dataset_lines->{ $dataset } }, sprintf( " .num_actions = %d, .actions = &flow_rule_actions_%05d[0],",
                scalar( @{ $dataset_rules[ $i ]{'do'} } ), $i );
            push @{ $c_dataset_lines->{ $dataset } }, " },\n";
        }
        push @{ $c_dataset_lines->{ $dataset } }, "\n};\n\n";
    }
}

###################################
## Utility functions
###################################

# converts a 16-char long string of ## and .. into its 8 bit number
# MSB first
sub pixels_to_byte {
    my $pixels = shift;
    return -1 if ( length( $pixels ) != 16 );
    # yes 'oct' function in perl converts _binary_ strings to number
    return oct( '0b' . join( '', map { ( $_ eq '..' ? '0' : '1' ) } unpack("(A2)*", $pixels ) ) );
}

#################################
## Consistency Checks Functions
#################################

sub check_screen_sprites_are_valid {
    my $errors = 0;
    my %is_valid_sprite = map { $_->{'name'}, 1 } @all_sprites;
    foreach my $screen ( @all_screens ) {
        foreach my $sprite ( @{ $screen->{'sprites'} } ) {
            if ( not $is_valid_sprite{ $sprite->{'name'} } ) {
                warn sprintf( "Screen '%s': undefined sprite '%s'\n", $screen->{'name'}, $sprite->{'name'} );
                $errors++;
            }
        }
    }
    return $errors;
}

sub check_screen_btiles_are_valid {
    my $errors = 0;
    my %is_valid_btile = map { $_->{'name'}, 1 } @all_btiles;
    foreach my $screen ( @all_screens ) {
        foreach my $btile ( @{ $screen->{'btiles'} } ) {
            if ( not defined( $btile->{'btile'} ) ) {
                warn sprintf( "Screen '%s': %s has no associated btile attribute\n", $screen->{'name'}, $btile->{'type'} );
                $errors++;
                next;
            }
            if ( not $is_valid_btile{ $btile->{'btile'} } ) {
                warn sprintf( "Screen '%s': undefined btile '%s'\n", $screen->{'name'}, $btile->{'btile'} );
                $errors++;
            }
        }
    }
    return $errors;
}

# items are btiles
sub check_screen_items_are_valid {
    my $errors = 0;
    my %is_valid_btile = map { $_->{'name'}, 1 } @all_btiles;
    foreach my $screen ( @all_screens ) {
        foreach my $item ( map { $all_items[ $_ ] } @{ $screen->{'items'} } ) {
            if ( not $is_valid_btile{ $item->{'btile'} } ) {
                warn sprintf( "Screen '%s': undefined btile '%s' for item '%s'\n",
                    $screen->{'name'},
                    $item->{'btile'},
                    $item->{'name'},
                );
                $errors++;
            }
        }
    }
    return $errors;
}

sub integer_in_range {
    my ( $value, $min, $max ) = @_;
    return ( ( $value >= $min ) and ( $value <= $max ) );
}


sub check_game_config_is_valid {
    my $errors = 0;
    if ( defined( $game_config->{'zx_target'} ) ) {
        ( $game_config->{'zx_target'} eq '48' ) or
        ( $game_config->{'zx_target'} eq '128' ) or do {
            warn sprintf( "Game Config: invalid '%s' value for 'zx_target' setting", $game_config->{'zx_target'} );
            $errors++;
        }
    } else {
        $game_config->{'zx_target'} = '48';
        warn "Game Config: 'zx_target' not defined - building for 48K mode\n";
    }
    if ( is_build_feature_enabled( 'INVENTORY') and not defined( $game_config->{'inventory_area'} ) ) {
        warn "Game Config: using INVENTORY feature, but no INVENTORY_AREA defined\n";
        $errors++;
    }

    if ( is_build_feature_enabled( 'SCREEN_TITLES') and not defined( $game_config->{'title_area'} ) ) {
        warn "Game Config: using SCREEN_TITLES feature, but no TITLE_AREA defined\n";
        $errors++;
    }

    # tracker configuration
    if ( defined( $game_config->{'tracker'} ) ) {
        if ( not defined( $game_config->{'tracker'}{'type'} ) ) {
            warn "TRACKER: tracker TYPE must be specified\n";
            $errors++;
        }
        if ( not scalar( @{ $game_config->{'tracker'}{'songs'} } ) ) {
            warn "TRACKER: no music songs defined (TRACKER_SONG directive)\n";
            $errors++;
        }
        if ( defined( $game_config->{'tracker'}{'in_game_song'} ) and 
                not grep { $_->{'name'} eq $game_config->{'tracker'}{'in_game_song'} } 
                @{ $game_config->{'tracker'}{'songs'} } ) {
            warn "TRACKER: unknown song name in IN_GAME_SONG parameter\n";
            $errors++;
        }
        if ( $game_config->{'zx_target'} ne '128' ) {
            warn "TRACKER: must be used together with ZX_TARGET = 128\n";
            $errors++;
        }
        if ( ( lc( $game_config->{'tracker'}{'type'} ) eq 'vortex2' ) ) {
            if ( defined(  $game_config->{'tracker'}{'fxtable'} ) ) {
                warn "TRACKER: vortex2 tracker does not support sound effects (TRACKER_FXTABLE directive)\n";
                $errors++;
            }
            if ( defined(  $game_config->{'tracker'}{'fx_channel'} ) ) {
                warn "TRACKER: vortex2 tracker does not support sound effects (FX_CHANNEL directive)\n";
                $errors++;
            }
            if ( defined(  $game_config->{'tracker'}{'fx_volume'} ) ) {
                warn "TRACKER: vortex2 tracker does not support sound effects (FX_VOLUME directive)\n";
                $errors++;
            }
        }
    }

    # check color mode, if nothing specified set to FULL
    if ( defined( $game_config->{'color'} ) ) {
        if ( not defined( $game_config->{'color'}{'mode'} ) ) {
            warn "COLOR: MODE parameter is mandatory\n";
            $errors++;
        } else {
            if ( lc( $game_config->{'color'}{'mode'} ) eq 'mono' ) {
                if ( not defined( $game_config->{'color'}{'gamearea_attr'} ) ) {
                    warn "COLOR: when MODE=MONO, GAMEAREA_ATTR parameter is mandatory\n";
                    $errors++;
                }
            } elsif ( lc( $game_config->{'color'}{'mode'} ) ne 'full' ) {
                warn "COLOR: parameter MODE must be one of MONO, FULL\n";
                $errors++;
            }
        }
    } else {
        $game_config->{'color'}{'mode'} = 'full';
    }
    # now we are sure color mode is one of 'full' or 'mono'
    if ( lc( $game_config->{'color'}{'mode'} ) eq 'mono' ) {
        add_build_feature( 'GAMEAREA_COLOR_MONO' );
    } else {
        add_build_feature( 'GAMEAREA_COLOR_FULL' );
    }

    # check SUBs configuration
    my %used_sub_names;
    foreach my $sub ( @{ $game_config->{'single_use_blobs'} } ) {
        if ( not defined( $sub->{'org_address'} ) ) {
            $sub->{'org_address'} = $sub->{'load_address'};
        }
        if ( not defined( $sub->{'run_address'} ) ) {
            $sub->{'run_address'} = $sub->{'org_address'};
        }
        if ( not defined( $sub->{'compress'} ) ) {
            $sub->{'compress'} = 0;
        }
        $sub->{'load_address'} = optional_hex_decode( $sub->{'load_address'} );
        $sub->{'org_address'} = optional_hex_decode( $sub->{'org_address'} );
        $sub->{'run_address'} = optional_hex_decode( $sub->{'run_address'} );

        # at this point, NAME,LOAD_ADDRESS,ORG_ADDRESS,RUN_ADDRESS and COMPRESS are always defined
        # Now with the logic checks

        if ( $used_sub_names{ $sub->{'name'} }++ ) {
            warn "SINGLE_USE_BLOB: $sub->{'name'}: duplicate SUB name\n";
            $errors++;
        }

        if ( ( $sub->{'load_address'} < 0xC000 ) and not is_build_feature_enabled( 'ZX_TARGET_128' ) ) {
            warn "SINGLE_USE_BLOB: $sub->{'name'}: LOAD_ADDRESS lower than 0xC000 can only be used in 128K mode games\n";
            $errors++;
        }

        if ( ( $sub->{'compress'} ) and ( $sub->{'load_address'} == $sub->{'org_address'} ) ) {
            warn "SINGLE_USE_BLOB: $sub->{'name'}: LOAD_ADDRESS and ORG_ADDRESS can't be the same if COMPRESS=1\n";
            $errors++;
        }
    }

    return $errors;
}

# this function is called from main
sub run_consistency_checks {
    my $errors = 0;
    $errors += check_game_config_is_valid;
    $errors += check_screen_sprites_are_valid;
    $errors += check_screen_btiles_are_valid;
    $errors += check_screen_items_are_valid;
    die sprintf( "*** %d errors were found in configuration\n", $errors )
        if ( $errors );
}

#############################
## General Output Functions
#############################

sub generate_c_home_header {
    push @c_game_data_lines, <<EOF_HEADER

//////////////////////////////////////////////////////////////////////////
//
// Game data for the Home bank - automatically generated with datagen.pl
//
//////////////////////////////////////////////////////////////////////////

#include <arch/spectrum.h>
#include <sound/bit.h>
#include <arch/zx/sp1.h>

#include "rage1/inventory.h"
#include "rage1/game_state.h"
#include "rage1/codeset.h"

#include "game_data.h"

EOF_HEADER
;
}

sub generate_c_banked_header {
    my $dataset	= shift;

    my $num_btiles	= scalar( @{ $dataset_dependency{ $dataset }{'btiles'} } );
    my $num_sprites	= scalar( @{ $dataset_dependency{ $dataset }{'sprites'} } );
    my $num_flow_rules	= scalar( @{ $dataset_dependency{ $dataset }{'rules'} } );
    my $num_screens	= scalar( @{ $dataset_dependency{ $dataset }{'screens'} } );

    my $all_btiles_ptr		= ( $num_btiles ?	'_all_btiles'		: '0' );
    my $all_sprites_ptr		= ( $num_sprites ?	'_all_sprite_graphics'	: '0' );
    my $all_flow_rules_ptr	= ( $num_flow_rules ?	'_all_flow_rules'	: '0' );
    my $all_screens_ptr		= ( $num_screens ?	'_all_screens'		: '0' );

    if ( $dataset =~ /^\d+$/ ) {
        push @{ $c_dataset_lines->{ $dataset } }, <<EOF_HEADER
///////////////////////////////////////////////////////////////////////////
//
// Game data for the High banks - automatically generated with datagen.pl
//
////////////////////////////////&//////////////////////////////////////////

#include <arch/spectrum.h>
#include <sound/bit.h>

#include "rage1/map.h"
#include "rage1/sprite.h"
#include "rage1/debug.h"
#include "rage1/hero.h"
#include "rage1/game_state.h"
#include "rage1/bullet.h"
#include "rage1/enemy.h"
#include "rage1/flow.h"
#include "rage1/dataset.h"

// This _must_ be included - Datasets may reference assets from the home dataset!
#include "game_data.h"

EOF_HEADER
;

        push @{ $asm_dataset_lines->{ $dataset } }, <<EOF_HEADER
        org	$dataset_base_address
EOF_HEADER
;
    }

    push @{ $asm_dataset_lines->{ $dataset } }, <<EOF_HEADER2
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Asset index for this bank - This structure must be the first data item
;; generated in the bank: it contains pointers to the rest of the bank data
;; items!
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        section	data_compiler

extern	_all_btiles
extern	_all_sprite_graphics
extern	_all_flow_rules
extern	_all_screens

public	_all_assets_dataset_$dataset

_all_assets_dataset_$dataset:
    dw	$num_btiles		;; .num_btiles
    dw	$all_btiles_ptr		;; .all_btiles
    db	$num_sprites		;; .num_sprite_graphics
    dw	$all_sprites_ptr	;; .all_sprite_graphics
    db	$num_flow_rules		;; .num_flow_rules
    dw	$all_flow_rules_ptr	;; .all_flow_rules
    db	$num_screens		;; .num_screens
    dw	$all_screens_ptr	;; .all_screens

EOF_HEADER2
;
}

sub generate_btiles {
    my $dataset = shift;

    # generate the list of dataset btiles, return immediately if empty
    my @dataset_btiles = map { $all_btiles[ $_ ] } @{ $dataset_dependency{ $dataset }{'btiles'} };
    return if not scalar( @dataset_btiles );

    push @h_game_data_lines, <<EOF_TILES_H

////////////////////////////
// Big Tile definitions
////////////////////////////

EOF_TILES_H
;

    push @{ $c_dataset_lines->{ $dataset } }, <<EOF_TILES

////////////////////////////
// Big Tile definitions
////////////////////////////

EOF_TILES
;


    # generate the tiles

    my $animated_btiles = $conditional_build_features{'ANIMATED_BTILES'} || 0;

    my $gamearea_color_full = $conditional_build_features{'GAMEAREA_COLOR_FULL'} || 0;

    # generate the offsets and byte arena for all btiles in the dataset

    # the whole dedupe schema works also for animated btiles, since
    # everything is stored as 8-byte tiles
    my @orig_cell_offsets;
    my @orig_byte_arena;
    foreach my $tile ( @dataset_btiles ) {
        my $initial_offset = scalar( @orig_byte_arena );
        push @orig_byte_arena, map { @$_ } @{ $tile->{'pixel_bytes'} };
        my $offset = 0;
        while ( $offset < 8 * scalar( @{ $tile->{'pixel_bytes'} } ) ) {
            push @orig_cell_offsets, $initial_offset + $offset;
            $offset += 8;
        }
    }

    # deduplication code goes here!
    my ( $new_cell_offsets, $new_arena ) = btile_deduplicate_arena_best( \@orig_cell_offsets, \@orig_byte_arena );
    my @cell_offsets = @$new_cell_offsets;
    my @byte_arena = @$new_arena;

    # generate the code for the arena (offsets will be used later)
    push @{ $c_dataset_lines->{ $dataset } }, "// Dataset BTILE byte arena\n";
    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "uint8_t all_dataset_btile_data[ %d ] = {\n", scalar( @byte_arena ) );
    my @bytes = @byte_arena;	# splice (below) is destructive!
    while ( @bytes ) {		# output the arena in 16-byte chunks
        push @{ $c_dataset_lines->{ $dataset } }, "\t" . join('', map { sprintf( '0x%02x,', $_ ) } splice( @bytes, 0, 16 ) ) . "\n";
    }
    push @{ $c_dataset_lines->{ $dataset } }, "};\n";
    
    # generate btile data structs
    # btiles always have 'frames' == 1, or the number of frames if specified
    my $cell_index = 0;
    foreach my $tile ( @dataset_btiles ) {

        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "\n// Start of Big tile '%s'\n\n", $tile->{'name'} );

        # output frame tiles
        foreach my $frame ( 0 .. ( $tile->{'frames'} - 1 ) ) {
            my $num_cells = scalar( @{ $tile->{'pixel_bytes'} } ) / $tile->{'frames'};
            my @btile_cell_offsets = @cell_offsets[ $cell_index .. ( $cell_index + $num_cells - 1 ) ];
            push @{ $c_dataset_lines->{ $dataset } }, sprintf( "uint8_t *btile_%s_frame_%d_tiles[ %d ] = {\n\t%s\n};\n",
                $tile->{'name'},
                $frame,
                $num_cells,
                join( ",\n\t",
                    map { sprintf( "&all_dataset_btile_data[ %d ]", $_ ) }
                    @btile_cell_offsets
                ) );
            $cell_index += $num_cells;
        }

        # manually specified attrs have preference over PNG ones
        # warning: this list will be destroyed by splice calls later!
        # attrs are not output when in monochrome mode
        if ( $gamearea_color_full ) {
            my @attrs = @{ $tile->{'attr'} || $tile->{'png_attr'} };
            foreach my $frame ( 0 .. ( $tile->{'frames'} - 1 ) ) {
                my @frame_attrs = splice( @attrs, 0, $tile->{'rows'} * $tile->{'cols'} );
                push @{ $c_dataset_lines->{ $dataset } }, sprintf( "uint8_t btile_%s_frame_%d_attrs[ %d ] = {\n\t%s\n};\n",
                    $tile->{'name'},
                    $frame,
                    scalar( @frame_attrs ),
                    join( ",\n\t", @frame_attrs ) );
            }
        }

        # if using ANIMATED_BTILES, frame and sequence tables for the btile have to be output
        if ( $animated_btiles ) {

            # output frame table
            # attrs are not output when in monochrome mode
            if ( $gamearea_color_full ) {
                push @{ $c_dataset_lines->{ $dataset } },
                    sprintf( "struct btile_frame_s btile_%s_frames[ %d ] = {\n\t%s\n};\n\n",
                        $tile->{'name'},
                        $tile->{'frames'},
                        join( ",\n\t", map {
                                sprintf( "{ .tiles = &btile_%s_frame_%d_tiles[0], .attrs = &btile_%s_frame_%d_attrs[0] }",
                                    $tile->{'name'}, $_,
                                    $tile->{'name'}, $_,
                                )
                            } ( 0 .. ( $tile->{'frames'} - 1 ) ) ),
                    );
            } else {
                push @{ $c_dataset_lines->{ $dataset } },
                    sprintf( "struct btile_frame_s btile_%s_frames[ %d ] = {\n\t%s\n};\n\n",
                        $tile->{'name'},
                        $tile->{'frames'},
                        join( ",\n\t", map {
                                sprintf( "{ .tiles = &btile_%s_frame_%d_tiles[0] }",
                                    $tile->{'name'}, $_,
                                )
                            } ( 0 .. ( $tile->{'frames'} - 1 ) ) ),
                    );
            }

            # output sequence table
            # first output each sequence
            foreach my $seq ( @{ $tile->{'sequences' } } ) {
                push @{ $c_dataset_lines->{ $dataset } },
                    sprintf( "uint8_t btile_%s_sequence_%s_frame_numbers[ %d ] = { %s };\n",
                        $tile->{'name'},
                        $seq->{'name'},
                        scalar( @{ $seq->{'frame_list'} } ),
                        join( ',', @{ $seq->{'frame_list'} } ),
                    );
            }

            # now the table of sequences itself
            if ( scalar( @{ $tile->{'sequences'} } ) ) {
                push @{ $c_dataset_lines->{ $dataset } },
                    sprintf( "struct animation_sequence_s btile_%s_sequences[ %d ] = {\n\t%s\n};\n\n",
                        $tile->{'name'},
                        scalar( @{ $tile->{'sequences'} } ),
                        join( ",\n\t", map {
                                sprintf( "{ .num_frames = %d, .frame_numbers = &btile_%s_sequence_%s_frame_numbers[0] }",
                                    scalar( @{ $_->{'frame_list'} } ),
                                    $tile->{'name'},
                                    $_->{'name'},
                                );
                            } ( @{ $tile->{'sequences'} } )
                        ),
                    );
            }
        }

        # output auxiliary definitions
        if ( $dataset eq 'home' ) {
            push @h_game_data_lines, sprintf( "#define BTILE_%s\t( &home_assets->all_btiles[ %d ] )\n",
                uc( $tile->{'name'} ),
                $dataset_dependency{ $dataset }{'btile_global_to_dataset_index'}{ $btile_name_to_index{ $tile->{'name'} } },
            );
            push @h_game_data_lines, sprintf( "#define BTILE_ID_%s\t%d\n",
                uc( $tile->{'name'} ),
                $dataset_dependency{ $dataset }{'btile_global_to_dataset_index'}{ $btile_name_to_index{ $tile->{'name'} } },
            );
        } else {
            push @{ $c_dataset_lines->{ $dataset } }, sprintf( "#define BTILE_%s\t( &home_assets->all_btiles[ %d ] )\n",
                uc( $tile->{'name'} ),
                $dataset_dependency{ $dataset }{'btile_global_to_dataset_index'}{ $btile_name_to_index{ $tile->{'name'} } },
            );
            push @{ $c_dataset_lines->{ $dataset } }, sprintf( "#define BTILE_ID_%s\t%d\n",
                uc( $tile->{'name'} ),
                $dataset_dependency{ $dataset }{'btile_global_to_dataset_index'}{ $btile_name_to_index{ $tile->{'name'} } },
            );
        }

        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "\n// End of Big tile '%s'\n\n", $tile->{'name'} );
    }

    # generate the global btile table for this dataset

    # the btile_s structures differ when using (or not) ANIMATED_BTILES
    push @{ $c_dataset_lines->{ $dataset } }, "// Dataset BTile table\n";
    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "struct btile_s all_btiles[ %d ] = {\n", scalar( @dataset_btiles ) );
    foreach my $tile ( @dataset_btiles ) {
        if ( $animated_btiles ) {
            push @{ $c_dataset_lines->{ $dataset } },
                sprintf( "\t{ .num_rows = %d, .num_cols = %d, ",
                    $tile->{'rows'},
                    $tile->{'cols'}
                );
            push @{ $c_dataset_lines->{ $dataset } },
                sprintf( ".num_frames = %d, .frames = &btile_%s_frames[0], ",
                    $tile->{'frames'},
                    $tile->{'name'}
                );
            push @{ $c_dataset_lines->{ $dataset } },
                sprintf( ".num_sequences = %d, .sequences = %s },\n",
                    scalar( @{ $tile->{'sequences'} } ),
                    ( scalar( @{ $tile->{'sequences'} } ) ? 
                        sprintf( "&btile_%s_sequences[0]", $tile->{'name'} ) :
                        'NULL'
                    )
                );
        } else {
            # when no ANIMATED_BTILES are used, the tiles and attrs pointers
            # are short-circuited to frame 0, which always exists

            # attrs are not output when in monochrome mode
            if ( $gamearea_color_full ) {
                push @{ $c_dataset_lines->{ $dataset } },
                    sprintf( "\t{ %d, %d, &btile_%s_frame_0_tiles[0], &btile_%s_frame_0_attrs[0] },\n",
                        $tile->{'rows'},
                        $tile->{'cols'},
                        $tile->{'name'},
                        $tile->{'name'} );
            } else {
                push @{ $c_dataset_lines->{ $dataset } },
                    sprintf( "\t{ %d, %d, &btile_%s_frame_0_tiles[0] },\n",
                        $tile->{'rows'},
                        $tile->{'cols'},
                        $tile->{'name'} );
            }
        }
    }
    push @{ $c_dataset_lines->{ $dataset } }, "};\n";
    push @{ $c_dataset_lines->{ $dataset } }, "// End of Dataset BTile table\n\n";


}

sub generate_sprites {
    my $dataset = shift;

    # generate the list of dataset sprites, return immediately if empty
    my @dataset_sprites = map { $all_sprites[ $_ ] } @{ $dataset_dependency{ $dataset }{'sprites'} };
    return if not scalar( @dataset_sprites );

    push @{ $c_dataset_lines->{ $dataset } }, <<EOF_SPRITES

////////////////////////////
// Sprite definitions
////////////////////////////

EOF_SPRITES
;

    # generate the sprites
    foreach my $sprite ( @dataset_sprites ) { generate_sprite( $sprite, $dataset ); }

    # output global sprite graphics table
    my $num_sprites = scalar( @dataset_sprites );
    push @{ $c_dataset_lines->{ $dataset } }, "// Dataset sprite graphics table\n";
    push @{ $c_dataset_lines->{ $dataset } }, "struct sprite_graphic_data_s all_sprite_graphics[ $num_sprites ] = {\n\t";
    push @{ $c_dataset_lines->{ $dataset } }, join( ",\n\n\t", map {
        my $sprite = $_;
        sprintf( "{ .width = %d, .height = %d,\n\t.frame_data.num_frames = %d,\n\t.frame_data.frames = &sprite_%s_frames[0],\n\t.sequence_data.num_sequences = %d,\n\t.sequence_data.sequences = %s }",
            $_->{'cols'} * 8, $_->{'rows'} * 8,
            $_->{'frames'}, $_->{'name'},
            scalar( @{ $sprite->{'sequences'} } ),	# number of animation sequences
            ( scalar( @{ $sprite->{'sequences'} } ) ? sprintf( "&sprite_%s_sequences[0]", $_->{'name'}) : 'NULL' ) ),
    } @dataset_sprites );
    push @{ $c_dataset_lines->{ $dataset } }, "\n};\n\n";
}

sub generate_screens {
    my $dataset = shift;

    # generate the list of dataset screens,  return immediately if empty
    my @dataset_screens = map { $all_screens[ $_ ] } @{ $dataset_dependency{ $dataset }{'screens'} };
    return if not scalar( @dataset_screens );

    push @{ $c_dataset_lines->{ $dataset } }, <<EOF_SCREENS

////////////////////////////
// Screen definitions
////////////////////////////

EOF_SCREENS
;

    # generate screen data
    foreach my $screen ( @dataset_screens ) {
        generate_screen( $screen, $dataset );
    }
}

sub generate_map {
    my $dataset = shift;

    # generate the list of dataset screens, return immediately if empty
    my @dataset_screens = map { $all_screens[ $_ ] } @{ $dataset_dependency{ $dataset }{'screens'} };
    return if not scalar( @dataset_screens );

    my $num_screens = scalar( @dataset_screens );

    # output global map data structure
    push @{ $c_dataset_lines->{ $dataset } }, <<EOF_MAP

////////////////////////////
// Map definition
////////////////////////////

// dataset map

EOF_MAP
;
    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "struct map_screen_s all_screens[ %d ] = {\n", $num_screens );

    push @{ $c_dataset_lines->{ $dataset } }, join( ",\n", map {
            my $screen_name = $_->{'name'};
            my $screen = $_;
            my $num_animated_btiles = scalar( grep { $_->{'is_animated'} } @{ $_->{'btiles'} } );
            sprintf( "\t// Screen '%s'\n\t{\n", $_->{'name'} ) .

            sprintf( "\t\t.global_screen_num = %d,\n", $screen_name_to_index{ $_->{'name'} } ) .

            sprintf( "\t\t.title = %s,\n", ( defined( $screen->{'title'} ) ? '"'.$screen->{'title'}.'"' : 'NULL' ) ) .

            sprintf( "\t\t.btile_data = { %d, %s },\t// btile_data\n",
                scalar( @{$_->{'btiles'}} ), ( scalar( @{$_->{'btiles'}} ) ? sprintf( 'screen_%s_btile_pos', $_->{'name'} ) : 'NULL' ) ) .

            # onlye output if ANIMATED_BTILES are used
            ( is_build_feature_enabled( 'ANIMATED_BTILES' ) ?
                sprintf( "\t\t.animated_btile_data = { %d, %s },\t// btile_data\n",
                $num_animated_btiles, ( $num_animated_btiles ? sprintf( 'screen_%s_animated_btiles', $_->{'name'} ) : 'NULL' ) )
                : '' ) .

            sprintf( "\t\t.enemy_data = { %d, %s },\t// enemy_data\n",
                scalar( @{$_->{'enemies'}} ), ( scalar( @{$_->{'enemies'}} ) ? sprintf( 'screen_%s_enemies', $_->{'name'} ) : 'NULL' ) ) .

            sprintf( "\t\t.hero_data = { %d, %d },\t// hero_data\n",
                $_->{'hero'}{'startup_xpos'}, $_->{'hero'}{'startup_ypos'} ) .

            # only output if INVENTORY is used
            ( scalar( @all_items) ? sprintf( "\t\t.item_data = { %d, %s },\t// item_data\n",
                scalar( @{$_->{'items'}} ), ( scalar( @{$_->{'items'}} ) ? sprintf( 'screen_%s_items', $_->{'name'} ) : 'NULL' ) )
                : '' ) .

            # only output if CRUMBS are used
            ( scalar( @all_crumb_types) ? sprintf( "\t\t.crumb_data = { %d, %s },\t// item_data\n",
                scalar( @{$_->{'crumbs'}} ), ( scalar( @{$_->{'crumbs'}} ) ? sprintf( 'screen_%s_crumbs', $_->{'name'} ) : 'NULL' ) )
                : '' ) .

            sprintf( "\t\t.hotzone_data = { %d, %s },\t// hotzone_data\n",
                scalar( @{$_->{'hotzones'}} ), ( scalar( @{$_->{'hotzones'}} ) ? sprintf( 'screen_%s_hotzones', $_->{'name'} ) : 'NULL' ) ) .

            join( "\n", map {
                sprintf( "\t\t.flow_data.rule_tables.%s = { %d, %s },",
                    $_,
                    ( scalar( @{ $screen->{'rules'}{ $_ } } ) || 0 ),
                    ( scalar( @{ $screen->{'rules'}{ $_ } } ) ?
                        sprintf( "&screen_%s_%s_rules[0]",
                            $screen_name,
                            $_
                        ) :
                        'NULL'
                    )
                )
                } @{ $syntax->{'valid_whens'} } ) . "\n" .

            ( defined( $_->{'background'} ) ?
                sprintf( "\t\t.background_data = { %s, %d, { %d, %d, %d, %d } }\t// background_data\n",
                    sprintf( "BTILE_ID_%s", uc( $_->{'background'}{'btile'} ) ),
                    ( defined( $_->{'background'}{'probability'} ) ? $_->{'background'}{'probability'} : 255 ),
                    $_->{'background'}{'row'}, $_->{'background'}{'col'},
                    $_->{'background'}{'width'}, $_->{'background'}{'height'}
                ) :
                "\t\t.background_data = { 0, 0, { 0,0,0,0 } }\t// background_data\n" ) .

            "\t}"
        } @dataset_screens );

    push @{ $c_dataset_lines->{ $dataset } }, "\n};\n\n";

}

sub generate_h_header {
    push @h_game_data_lines, <<GAME_DATA_H_1
#ifndef _GAME_DATA_H
#define _GAME_DATA_H

#include <stdint.h>
#include <games/sp1.h>

#include "rage1/dataset.h"

extern struct dataset_assets_s all_assets_dataset_home;

GAME_DATA_H_1
;
}

sub generate_h_ending {
    push @h_game_data_lines, <<GAME_DATA_H_4
#endif // _GAME_DATA_H
GAME_DATA_H_4
;
}

sub generate_game_config {
    push @h_game_data_lines, "\n// game configuration data\n";
    push @h_game_data_lines, sprintf( "#define MAP_NUM_SCREENS\t%d\n", scalar( @all_screens ) );
    push @h_game_data_lines, sprintf( "#define MAP_INITIAL_SCREEN\t%d\n", $screen_name_to_index{ $game_config->{'screen'}{'initial'} } );
    push @h_game_data_lines, sprintf( "#define DEFAULT_BG_ATTR ( %s )\n", $game_config->{'default_bg_attr'} );

    push @h_game_data_lines, "\n// sound effect constants\n";
    foreach my $effect ( keys %{$game_config->{'sounds'}} ) {
        push @h_game_data_lines, sprintf( "#define SOUND_%s %s\n", uc( $effect ), $game_config->{'sounds'}{ $effect } );
    }

    # check maximum sprite usage
    my $max_sprites = 0;
    my $max_spritechars = 0;

    # start with the screens
    foreach my $screen ( @all_screens ) {
        my $screen_sprites = 0;
        my $screen_spritechars = 0;
        foreach my $sprite ( map { $all_sprites[ $sprite_name_to_index{ $_->{'sprite'} } ] } @{ $screen->{'enemies'} } ) {
            $screen_sprites++;
            # remember: SP1 sprites have 1 extra row and col
            $screen_spritechars += ( $sprite->{'rows'} + 1 ) * ( $sprite->{'cols'} + 1 )
        }
        if ( $screen_sprites > $max_sprites ) {
            $max_sprites = $screen_sprites;
        }
        if ( $screen_spritechars > $max_spritechars ) {
            $max_spritechars = $screen_spritechars;
        }
    }

    # add the hero sprite - just 1
    $max_sprites++;
    my $hs = $all_sprites[ $sprite_name_to_index{ $hero->{'sprite'} } ];
    $max_spritechars += ( $hs->{'rows'} + 1 ) * ( $hs->{'cols'} + 1 );

    # add the bullet sprites - the N bullets
    if ( defined( $hero->{'bullet'} ) ) {
        $max_sprites += $hero->{'bullet'}{'max_bullets'};
        my $bs = $all_sprites[ $sprite_name_to_index{ $hero->{'bullet'}{'sprite'} } ];
        $max_spritechars += $hero->{'bullet'}{'max_bullets'} * ( $bs->{'rows'} + 1 ) * ( $bs->{'cols'} + 1 );
    }

    # 20 bytes for a safety margin, plus 6 bytes per allocation, plus 20
    # bytes per sprite, plus 24 bytes per sprite char
    my $max_heap_usage = 20 + $max_sprites * (20 + 6) + $max_spritechars * (24 + 6);

    # max dataset size: memory from $5B00->$7FFF minus the heap
    my $max_dataset_size = (
        ( $cfg->{'interrupts_128'}{'base_code_address'} =~ /^0x/ ?
            hex( $cfg->{'interrupts_128'}{'base_code_address'} ) :
            $cfg->{'interrupts_128'}{'base_code_address'} )
         - 0x5B00 ) - $max_heap_usage;

    push @h_game_data_lines, <<EOF_BLDCFG1

// maximum sprite and heap usage
#define BUILD_MAX_NUM_SPRITES_PER_SCREEN	$max_sprites
#define BUILD_MAX_NUM_SPRITECHARS_PER_SCREEN	$max_spritechars

// 20 bytes for a safety margin, plus 6 bytes per allocation, plus 20
// bytes per sprite, plus 24 bytes per sprite char
#define BUILD_MAX_HEAP_SPRITE_USAGE		$max_heap_usage

// max dataset size when uncompressed to \$5B00
#define	BUILD_MAX_DATASET_SIZE			$max_dataset_size

EOF_BLDCFG1
;


    # add CUSTOM_CHARSET definitions of present
    if ( defined( $game_config->{'custom_charset'} ) ) {
        my ( $char_min, $char_max ) = ( 32, 127 );	# defaults: all ZX ASCII range
        if ( $game_config->{'custom_charset'}{'range'} ) {
            $game_config->{'custom_charset'}{'range'} =~ m/^(\d+)\-(\d+)$/;
            ( $char_min, $char_max ) = ( $1, $2 );
        }
        push @h_game_data_lines, "\n// custom charset minimum and maximum characters\n";
        push @h_game_data_lines, sprintf( "#define CUSTOM_CHARSET_MIN_CHAR %d\n", $char_min );
        push @h_game_data_lines, sprintf( "#define CUSTOM_CHARSET_MAX_CHAR %d\n", $char_max );

        # ...and CUSTOM_CHARSET data to game_data.c
        open( CHAR_DATA, "$build_dir/$game_config->{'custom_charset'}{'file'}" ) or
            die "CUSTOM_CHARSET: could not open $game_config->{'custom_charset'}{'file'} for reading\n";
        binmode CHAR_DATA;
        my $data;
        my $data_offset = ( $char_min - 32 ) * 8;
        my $data_size = ( $char_max - $char_min + 1 ) * 8;
        if ( read( CHAR_DATA, $data, $data_size, $data_offset ) != $data_size ) {
            die "CUSTOM_CHARSET: error reading $data_size bytes from $game_config->{'custom_charset'}{'file'}, offset $data_offset\n";
        }
        close CHAR_DATA;
        push @c_game_data_lines, "\n// custom charset binary data\n";
        push @c_game_data_lines, sprintf( "// first char: %d ('%c'), last char: %d ('%c')\n", $char_min, $char_min, $char_max, $char_max );
        push @c_game_data_lines, "uint8_t custom_charset[ ( CUSTOM_CHARSET_MAX_CHAR - CUSTOM_CHARSET_MIN_CHAR + 1 ) * 8 ] = {\n";
        push @c_game_data_lines, "\t" . join( ", ", map { sprintf "0x%02x", $_ } unpack('C*', $data ) ) . "\n";
        push @c_game_data_lines, "};\n\n";
    }

    # add gamearea default attribute if monochrome mode is used
    if ( defined( $game_config->{'color'}{'gamearea_attr'} ) ) {
        push @h_game_data_lines, "\n// gamearea default attr for monochrome mode\n";
        push @h_game_data_lines, sprintf( "#define GAMEAREA_COLOR_MONO_ATTR (%s)\n\n", $game_config->{'color'}{'gamearea_attr'} );
    }

    # add custom_state_data config
    if ( defined( $game_config->{'custom_state_data'} ) ) {
        push @h_game_data_lines, "\n// custom state data size\n";
        push @h_game_data_lines, sprintf( "#define CUSTOM_STATE_DATA_SIZE %d\n\n", $game_config->{'custom_state_data'}{'size'} );
    }

}

# this function generates screen data that needs to be stored in the home
# dataset at all times: screen->dataset mapping, screen state asset tables,
# etc.

sub generate_global_screen_data {

    my $dataset = 'home';

    # generate global screen_dataset_map variable with screen->dataset mapping
    push @{ $c_dataset_lines->{ $dataset } }, "\n// Global screen->dataset mapping table\n";
    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "struct screen_dataset_map_s screen_dataset_map[ %d ] = {\n", scalar( @all_screens) );
    foreach my $global_screen_index ( 0 .. ( scalar( @all_screens) - 1 ) ) {
        my $screen = $all_screens[ $global_screen_index ];
        my $screen_dataset = ( $game_config->{'zx_target'} eq '48' ? 'home' : $screen->{'dataset'} );
        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "\t{ .dataset_num = %d, .dataset_local_screen_num = %d },\t// Screen '%s'\n",
            $screen->{'dataset'},
            $dataset_dependency{ $screen_dataset }{'screen_global_to_dataset_index'}{ $global_screen_index },
            $screen->{'name'}
        );
    }
    push @{ $c_dataset_lines->{ $dataset } }, "};\n\n";

    # screen asset state tables
    foreach my $screen ( @all_screens ) {
        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "// Screen '%s' asset state table\n", $screen->{'name'} );
        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "struct asset_state_s screen_%s_asset_state[ %d ] = {\n\t",
            $screen->{'name'}, scalar( @{ $screen->{'asset_states'} } )
        );
        push @{ $c_dataset_lines->{ $dataset } }, join( "\n\t",
            map {
                sprintf( "{ .asset_state = %s, .asset_initial_state = %s },\t// %s",
                    $_->{'value'}, $_->{'value'}, $_->{'comment'},
                )
            } @{ $screen->{'asset_states'} }
        );
        push @{ $c_dataset_lines->{ $dataset } }, "\n};\n\n";
    }

    # global table of asset state tables for all screens
    push @{ $c_dataset_lines->{ $dataset } }, "// Global table of asset state tables for all screens\n";
    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "struct asset_state_table_s all_screen_asset_state_tables[ %d ] = {\n\t",
        scalar( @all_screens ) );
    push @{ $c_dataset_lines->{ $dataset } }, join( ",\n\t",
        map {
            sprintf( "{ .num_states = %d, .states = &screen_%s_asset_state[0] }",
                scalar( @{$_->{ 'asset_states' } } ), $_->{'name'}
            )
        } @all_screens
    );
    push @{ $c_dataset_lines->{ $dataset } }, "\n};\n\n";

}

# generate data that does not logically fit elsewhere
sub generate_misc_data {

    # number of enemies at game reset
    my $count = 0;
    foreach my $screen ( @all_screens ) {
        $count += scalar( @{ $screen->{'enemies'} } );
    }
    push @h_game_data_lines, "\n// Total number of enemies in the game\n";
    push @h_game_data_lines, sprintf( "#define\tGAME_NUM_TOTAL_ENEMIES\t%d\n\n", $count );

    # number of flow vars
    if ( defined( $max_flow_var_id ) ) {
        push @h_game_data_lines, "\n// Total number of flow vars in the game\n";
        push @h_game_data_lines, sprintf( "#define\tGAME_NUM_FLOW_VARS\t%d\n\n", ( $max_flow_var_id + 1 ) );
    }
}

sub generate_conditional_build_features {

    # output build features for conditional compiles
    push @h_build_features_lines, <<EOF_FEATURES1

////////////////////////////////////////////////////////////////
// BUILD FEATURE MACROS FOR CONDITIONAL COMPILES
////////////////////////////////////////////////////////////////

#ifndef _FEATURES_H
#define _FEATURES_H

EOF_FEATURES1
;

    foreach my $f ( sort keys %conditional_build_features ) {
        push @h_build_features_lines, sprintf( "#define BUILD_FEATURE_%s\n", uc($f) );
    }

    push @h_build_features_lines, <<EOF_FEATURES2

////////////////////////////////////////////////////////////////
// END OF BUILD FEATURE MACROS
////////////////////////////////////////////////////////////////

#endif // _FEATURES_H

EOF_FEATURES2
;

}

## CODESET information
sub generate_global_codeset_data {
    push @h_game_data_lines, <<EOF_CODESET_1

//////////////////////////////////////////
// CODESET DEFINITIONS
//////////////////////////////////////////

EOF_CODESET_1
;
    push @h_game_data_lines, sprintf( "#define	NUM_CODESETS	%d\n\n", scalar( grep { "$_" ne 'home' } keys %codeset_functions_by_codeset ) );
    push @c_game_data_lines, <<EOF_CODESET_3

//////////////////////////////////////////
// CODESET DEFINITIONS
//////////////////////////////////////////

EOF_CODESET_3
;

    my @non_home_codeset_functions = grep { $_->{'codeset'} ne 'home' } @all_codeset_functions;

    if ( scalar( @non_home_codeset_functions ) and ( $game_config->{'zx_target'} ne '48' ) ) {
        push @c_game_data_lines, "// global codeset functions table\n";
        push @h_game_data_lines, "// global indexes of codeset functions\n";

        push @c_game_data_lines, sprintf( "struct codeset_function_info_s all_codeset_functions[ %d ] = { \n",
            scalar( @non_home_codeset_functions )
        );
        my $index = 0;
        foreach my $function ( @non_home_codeset_functions ) {
            push @c_game_data_lines,  sprintf( "\t{ .bank_num = %d, .local_function_num = %d },\n",
                $codeset_valid_banks[ $function->{'codeset'} ],
                $function->{'local_index'},
            );
            push @h_game_data_lines, sprintf( "#define CODESET_FUNCTION_%s	(%d)\n",
                uc( $function->{'name'} ),
                $index,
            );
            $index++;
        }
        push @c_game_data_lines, "};\n";
        push @h_game_data_lines, "\n";
    } else {
        push @c_game_data_lines, "// No codesets defined\n";
        push @h_game_data_lines, "// No codesets defined\n";
    }

    # Add the function call macros to the global game_data header file.
    # All codeset functions must be called via call macros.  If in 128K
    # mode, they will generate a call to codeset_call_function(), and if in
    # 48K mode they will be resolved to a regular function call

    push @h_game_data_lines, "// codeset function call macros for each function\n";
    foreach my $function ( @all_codeset_functions ) {
        my $macro;
        if ( ( $game_config->{'zx_target'} eq '48' ) or ( $function->{'codeset'} eq 'home' ) ) {
            # macros for 48K mode
            push @h_game_data_lines, sprintf(
                "#define CALL_CODESET_FUNCTION_%-30s  (%s())\n",
                uc( $function->{'name'} ) . '()',
                $function->{'name'},
            );
        } else {
            # macros for 128K mode
            push @h_game_data_lines, sprintf(
                "#define CALL_CODESET_FUNCTION_%-30s  (codeset_call_function( CODESET_FUNCTION_%s ))\n",
                uc( $function->{'name'} ) . '()',
                uc( $function->{'name'} ),
            );
        }
        $function->{'codeset_function_call_macro'} = sprintf(
            'CALL_CODESET_FUNCTION_%s()', uc( $function->{'name'} )
        );
    }

    push @h_game_data_lines, <<EOF_CODESET_2

//////////////////////////////////////////
// END OF CODESET DEFINITIONS
//////////////////////////////////////////

EOF_CODESET_2
;

    push @c_game_data_lines, <<EOF_CODESET_4

//////////////////////////////////////////
// END OF CODESET DEFINITIONS
//////////////////////////////////////////

EOF_CODESET_4
;
}

sub all_codesets_except_home {
    # codesets used by functions
    my @function_codesets = grep { "$_" ne 'home' } keys %codeset_functions_by_codeset;

    # codesets used by binary items
    my @blob_codesets = grep { "$_" ne 'home' } map { $_->{'codeset'} } @{ $game_config->{'binary_data'} };

    # all unique codesets except 'home'
    my @all_codesets = uniq @function_codesets, @blob_codesets;

#    print Dumper( \@all_codesets );
    return @all_codesets;
}

sub generate_codeset_headers {

    foreach my $codeset ( all_codesets_except_home ) {

        # add the needed source lines to the C and ASM files for this
        # codeset: the main codeset_assets_s struct at the beginning, the
        # function table and e.g.  tiles used by these functions
        push @{ $asm_codeset_lines->{ $codeset } }, <<EOF_CODESET_LINES_MAIN_ASM
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; We need this ASM file to force the linking of the codeset_assets_s
;; structure exactly at start of the binary (0xC000)
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	section	code_compiler
	org	$codeset_base_address

extern	_codeset_functions
public	_all_codeset_assets

_all_codeset_assets:
	dw	0			;; .game_state
	dw	0			;; .banked_assets
	dw	0			;; .home_assets
EOF_CODESET_LINES_MAIN_ASM
;

        push @{ $c_codeset_lines->{ $codeset } }, <<EOF_CODESET_LINES_MAIN
#include <stdlib.h>

#include "features.h"

#include "rage1/codeset.h"

#include "game_data.h"

EOF_CODESET_LINES_MAIN
;

    }
}

sub generate_codeset_functions {

    # If in 128K mode, for each codeset except 'home' codeset we create the
    # needed data structures.  If we are in 48K mode, there will be no
    # codesets besides 'home' so this will not run
    foreach my $codeset ( all_codesets_except_home ) {
        next if not defined( $codeset_functions_by_codeset{ $codeset } );
        my $num_codeset_functions = scalar( @{ $codeset_functions_by_codeset{ $codeset } } );
        if ( $num_codeset_functions ) {
            # add extern codeset function declarations
            push @{ $c_codeset_lines->{ $codeset } }, "// codeset functions table\n";
            foreach my $function ( @{ $codeset_functions_by_codeset{ $codeset } } ) {
                push @{ $c_codeset_lines->{ $codeset } }, sprintf( "extern void %s( void );\n", $function->{'name'} );
            }

            # add the codeset function table
            push @{ $asm_codeset_lines->{ $codeset } }, "	db	$num_codeset_functions			;; .num_functions\n";
            push @{ $asm_codeset_lines->{ $codeset } }, "	dw	_codeset_functions	;; .functions\n";
            push @{ $c_codeset_lines->{ $codeset } }, "codeset_function_t codeset_functions[ $num_codeset_functions ] = {\n";
            foreach my $function ( @{ $codeset_functions_by_codeset{ $codeset } } ) {
                push @{ $c_codeset_lines->{ $codeset } }, sprintf( "\t&%s,\n", $function->{'name'} );
            }
            push @{ $c_codeset_lines->{ $codeset } }, "};\n\n";
        }
    }
}

sub generate_custom_function_tables {
    # generate 'custom' type check function prototypes ('home' codeset)
    if ( scalar( @check_custom_functions ) ) {

        push @h_game_data_lines, "// Check custom functions table\n";
        push @h_game_data_lines, "extern check_custom_function_t check_custom_functions[];\n\n";
        push @h_game_data_lines, "// Check custom function prototypes\n";

        push @c_game_data_lines, "// Check custom functions table\n";
        push @c_game_data_lines, sprintf( "check_custom_function_t check_custom_functions[ %d ] = {\n",
            scalar( @check_custom_functions )
        );
        foreach my $f ( @check_custom_functions ) {
            # all check functions must accept a single 1-byte param, even if they ignore it
            push @h_game_data_lines, sprintf( "uint8_t %s( %s );\n", $f->{'function'}, 'uint8_t param' );
            push @c_game_data_lines, sprintf( "\t%s,\n", $f->{'function'} );
        }
        push @h_game_data_lines, "\n";
        push @c_game_data_lines, "};\n\n";
    }
    # generate 'custom' type action function prototypes ('home' codeset)
    if ( scalar( @action_custom_functions ) ) {

        push @h_game_data_lines, "// Action custom functions table\n";
        push @h_game_data_lines, "extern action_custom_function_t action_custom_functions[];\n\n";
        push @h_game_data_lines, "// Action custom function prototypes\n";

        push @c_game_data_lines, "// Action custom function table\n";
        push @c_game_data_lines, sprintf( "action_custom_function_t action_custom_functions[ %d ] = {\n",
            scalar( @action_custom_functions )
        );
        foreach my $f ( @action_custom_functions ) {
            push @h_game_data_lines, sprintf( "void %s( %s );\n", $f->{'function'}, ( $f->{'uses_param'} ? 'uint8_t param' : 'void' ) );
            push @c_game_data_lines, sprintf( "\t%s,\n", $f->{'function'} );
        }
        push @h_game_data_lines, "\n";
        push @c_game_data_lines, "};\n\n";
    }
    # generate 'crumb_action' type function prototypes ('home' codeset)
    push @h_game_data_lines, "// Crumb actions functions table\n";
    foreach my $function ( grep { lc( $_->{'type'} ) eq 'crumb_action' } @{ $codeset_functions_by_codeset{'home'} } ) {
        push @h_game_data_lines, sprintf( "extern void %s(  struct crumb_info_s *c );\n", $function->{'name'} );
    }
}

sub generate_binary_data_items {
    # return if no binary_data instances
    return if ( not defined( $game_config->{'binary_data'} ) or not scalar( @{ $game_config->{'binary_data'} } ) );

    # general data
    push @h_game_data_lines, "// extern declarations for binary data items\n";
    push @c_game_data_lines, "//////////////////////////////////////////\n";
    push @c_game_data_lines, "// BINARY DATA ITEMS\n";
    push @c_game_data_lines, "//////////////////////////////////////////\n\n";

    # process each of the binary blobs and generate its code
    foreach my $item ( @{ $game_config->{'binary_data'} } ) {

        # first, generate .h and .c lines for the binary. Later we'll place them
        # where they belong, depending on 48 or 128 mode

        my ( @h_lines, @c_lines );
        # slurp binary data from file into byte list, taking COMPRESS into account
        my @bytes;
        if ( $item->{'compress'} ) {
            @bytes = file_to_compressed_bytes( "$build_dir/$item->{'file'}", $item->{'offset'}, $item->{'size'} );
        } else {
            @bytes = file_to_bytes( "$build_dir/$item->{'file'}", $item->{'offset'}, $item->{'size'} );
        }

        # generate extern declaration
        push @h_lines, sprintf( "extern uint8_t %s[];\n", $item->{'symbol'} );

        # generate data definition
        push @c_lines, sprintf( "// binary data item '%s'%s\n", $item->{'symbol'}, ( $item->{'compress'} ? ' (ZX0 compressed)': '' ) );
        push @c_lines, sprintf( "uint8_t %s[ %d ] = {\n", $item->{'symbol'}, scalar( @bytes ) );

        my @byte16_groups;	# group in 16-byte-or-less pieces for easier reading/checking
        push @byte16_groups, [ splice @bytes, 0, 16 ]  while @bytes;
        push @c_lines, join( ",\n", map { "\t" . join( ", ", map { sprintf( "0x%02x", $_ ) } @{ $_ } ) } @byte16_groups );

        push @c_lines, "\n};\n\n";

        # ...now place the generated code where it belongs
        if ( $game_config->{'zx_target'} eq '48' ) {
            # logic for 48K mode - easy, all into game_data.c and .h. CODESET setting is ignored
            push @h_game_data_lines, @h_lines;
            push @c_game_data_lines, @c_lines;
        } else {
            # logic for 128K mode - store the binary data into the specified CODESET or home if none specified
            my $codeset = defined( $item->{'codeset'} ) ? $item->{'codeset'} : 'home';
            push @h_game_data_lines, @h_lines;
            if ( $codeset eq 'home' ) {
                push @c_game_data_lines, @c_lines;
            } else {
                push @{ $c_codeset_lines->{ $codeset } }, @c_lines;
            }
        }
    }

    push @h_game_data_lines, "\n";
    push @c_game_data_lines, "//////////////////////////////////////////\n";
    push @c_game_data_lines, "// END OF BINARY DATA ITEMS\n";
    push @c_game_data_lines, "//////////////////////////////////////////\n";

}

sub generate_c_banked_data_128_header {
    push @c_banked_data_128_lines,<<EOF_BANKED_128_HEADING
#include <stdint.h>
#include <stdlib.h>

EOF_BANKED_128_HEADING
;
}

sub generate_tracker_data {
    # tracker songs
    if ( defined( $game_config->{'tracker'} ) ) {

        push @h_game_data_lines, "/////////////////////\n";
        push @h_game_data_lines, "// Tracker songs\n";
        push @h_game_data_lines, "/////////////////////\n\n";

        push @c_banked_data_128_lines, "//////////////////////////////////\n";
        push @c_banked_data_128_lines, "// Tracker songs data and table\n";
        push @c_banked_data_128_lines, "//////////////////////////////////\n\n";

        # output the songs data

        foreach my $song ( @{ $game_config->{'tracker'}{'songs'} } ) {
            my $symbol_name = "tracker_song_" . $song->{'name'};

            # generate extern declaration for later use in C file
            push @c_banked_data_128_lines, sprintf( "extern uint8_t %s[];\n", $symbol_name );

            # generate song ID in header file
            push @h_game_data_lines, sprintf( "#define TRACKER_SONG_%s\t%d\n",
                uc( $song->{'name'} ), $song->{'song_index'} );

            # generate song ASM file and put it in place for compilation
            if ( $game_config->{'tracker'}{'type'} eq 'arkos2' ) {
                # for Arkos2, convert it into asm format with the official tool
                my $asm_file = arkos2_convert_song_to_asm( "$build_dir/$song->{'file'}", $symbol_name );
                my $dest_asm_file = "$build_dir/generated/banked/128/" . basename( $asm_file );
                move( $asm_file, $dest_asm_file ) or
                    die "Could not rename $asm_file to $dest_asm_file\n";
            }
            if ( $game_config->{'tracker'}{'type'} eq 'vortex2' ) {
                # for Vortex2, copy the binary .PT3 file and add an ASM shim to include the binary as-is
                copy( "$build_dir/$song->{'file'}", "$build_dir/generated/banked/128" ) or
                    die "Could not copy $build_dir/$song->{'file'} to $build_dir/generated/banked/128\n";
                my $dest_asm_file = sprintf( "$build_dir/generated/banked/128/vortex2_song_%s.asm", $symbol_name );
                my $bin_basename = basename( "$build_dir/$song->{'file'}" );
                open ASM, ">$dest_asm_file" or
                    die "Could not write to $dest_asm_file\n";
                printf ASM "SECTION data_compiler\nPUBLIC _%s\n_%s:\nBINARY \"%s\"\n", $symbol_name, $symbol_name, $bin_basename;
                close ASM;
            }
        }
        if ( defined( $game_config->{'tracker'}{'in_game_song'} ) ) {
            push @h_game_data_lines, sprintf( "#define TRACKER_IN_GAME_SONG\tTRACKER_SONG_%s\n",
                uc( $game_config->{'tracker'}{'in_game_song'} ) );
        }

        # now output the songs table
        push @c_banked_data_128_lines, "\n// songs table\n";
        push @c_banked_data_128_lines, sprintf( "uint8_t *all_songs[ %d ] = {\n",
            scalar( @{ $game_config->{'tracker'}{'songs'} } ) );
        foreach my $song ( @{ $game_config->{'tracker'}{'songs'} } ) {
            my $symbol_name = "tracker_song_" . $song->{'name'};
            push @c_banked_data_128_lines, sprintf( "\t&%s[0],\n", $symbol_name );
        }
        push @c_banked_data_128_lines, "};\n";

        # output sound effects table and constants
        if ( defined( $game_config->{'tracker'}{'fxtable'} ) ) {
            # generate song ASM file and put it in place for compilation
            # the extern declaration for this is already in tracker.h
            my $asm_file = arkos2_convert_effects_to_asm( "$build_dir/$game_config->{'tracker'}{'fxtable'}{'file'}", 'all_sound_effects' );
            my $dest_asm_file = "$build_dir/generated/banked/128/" . basename( $asm_file );

            my $effects_count = arkos2_count_sound_effects( $asm_file );
            push @h_game_data_lines, sprintf( "#define TRACKER_SOUNDFX_NUM_EFFECTS %d\n", $effects_count );

            move( $asm_file, $dest_asm_file ) or
                die "Could not rename $asm_file to $dest_asm_file\n";
        }
        if ( defined( $game_config->{'tracker'}{'fx_channel'} ) ) {
            push @h_game_data_lines, sprintf( "#define TRACKER_SOUNDFX_CHANNEL %d\n",
                $game_config->{'tracker'}{'fx_channel'} );
        }
        if ( defined( $game_config->{'tracker'}{'fx_volume'} ) ) {
            push @h_game_data_lines, sprintf( "#define TRACKER_SOUNDFX_VOLUME %d\n",
                $game_config->{'tracker'}{'fx_volume'} );
        }

    }
}

# generates the game_events_rule_table
sub generate_game_events_rule_table {
    # rule checks and actions have been already generated in the home dataset
    # together with the other datasets. We just output the rule pointers here,
    # as it is already done when generating the rules for each screen

    my $rule_global_to_dataset_index = $dataset_dependency{ 'home' }{'rule_global_to_dataset_index'};

    # flow rules
    push @{ $c_dataset_lines->{ 'home' } }, sprintf( "// Game Events rule table\n" );
    my $num_rules = scalar( @game_events_rule_table );
    if ( $num_rules ) {
        push @{ $c_dataset_lines->{ 'home' } }, sprintf( "struct flow_rule_s *game_events_rule_table_rules[ %d ] = {\n\t",
            $num_rules );
        push @{ $c_dataset_lines->{ 'home' } }, join( ",\n\t",
            map {
                sprintf( "&all_flow_rules[ %d ]", $rule_global_to_dataset_index->{ $_ } )
            } @game_events_rule_table
        );
        push @{ $c_dataset_lines->{ 'home' } }, "\n};\n";
        push @{ $c_dataset_lines->{ 'home' } },
            "struct flow_rule_table_s game_events_rule_table = {\n",
            "\t.num_rules = $num_rules,\n",
            "\t.rules = &game_events_rule_table_rules[0]\n",
            "};\n\n";

    } else {
        push @{ $c_dataset_lines->{ 'home' } }, sprintf( "// Game Events rule table has no rules defined\n" );
        push @{ $c_dataset_lines->{ 'home' } },
            "struct flow_rule_table_s game_events_rule_table = { 0, NULL };\n\n";
    }
}

sub generate_configuration_values {

    # interrupt configuration values
    push @h_game_data_lines, "// Interrupt configuration\n";
    foreach my $k ( qw( iv_table_addr isr_vector_byte base_code_address ) ) {
        my $value = $cfg->{'interrupts_128'}{ $k };
        if ( $value =~ /^0x/ ) {
            $value = hex( $value );
        }
        push @h_game_data_lines, sprintf( "#define RAGE1_CONFIG_INT128_%-29s 0x%x\n", uc($k), $value );
        if ( $k eq 'isr_vector_byte' ) {
            push @h_game_data_lines, sprintf( "#define RAGE1_CONFIG_INT128_ISR_ADDRESS                   0x%02x%02x\n",
                $value, $value
            );
        }
    }
    push @h_game_data_lines, "\n";

}

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

sub create_dataset_dependencies {

    # first, we add all assets to the dataset lists
    foreach my $screen ( @all_screens ) {

        # get the screen dataset, override it and use 'home' if compiling for 48K target
        my $dataset = ( $game_config->{'zx_target'} eq '48' ? 'home' : $screen->{'dataset'} );

        # add screen to the dataset
        push @{ $dataset_dependency{ $dataset }{'screens'} },
            $screen_name_to_index{ $screen->{'name'} };

        # add btiles
        push @{ $dataset_dependency{ $dataset }{'btiles'} },
            map { $btile_name_to_index{ $_->{'btile'} } } @{ $screen->{'btiles'} };

        # the background btile is a special case, add it to the btile list
        if ( defined( $screen->{'background'} ) ) {
            push @{ $dataset_dependency{ $dataset }{'btiles'} },
                $btile_name_to_index{ $screen->{'background'}{'btile'} };
        }

        # add sprites
        push @{ $dataset_dependency{ $dataset }{'sprites'} },
            map { $sprite_name_to_index{ $_->{'sprite'} } } @{ $screen->{'enemies'} };

        # add rules
        push @{ $dataset_dependency{ $dataset }{'rules'} },
            map { @{ $screen->{'rules'}{ $_ } } } keys %{ $screen->{'rules'} };
    }

    # we then add the home dataset dependencies:
    # ...special btiles with a 'home' dataset
    foreach my $btile ( @all_btiles ) {
        # get the btile dataset, override it and use 'home' if compiling for 48K target
        my $dataset = ( $game_config->{'zx_target'} eq '48' ? 'home' : $btile->{'dataset'} );
        if ( defined( $btile->{'dataset'} ) ) {
            push @{ $dataset_dependency{ $dataset }{'btiles'} },
                $btile_name_to_index{ $btile->{'name'} };
        }
    }

    # ...hero sprite
    push @{ $dataset_dependency{'home'}{'sprites'} },
        $sprite_name_to_index{ $hero->{'sprite'} };

    # ...bullet sprite
    if ( defined( $hero->{'bullet'} ) ) {
        push @{ $dataset_dependency{'home'}{'sprites'} },
            $sprite_name_to_index{ $hero->{'bullet'}{'sprite'} };
    }

    # item btiles are always added to the home dataset, since the item table
    # is global
    foreach my $item ( @all_items ) {
        push @{ $dataset_dependency{'home'}{'btiles'} },
            $btile_name_to_index{ $item->{'btile'} };
    }

    # crumb btiles are always added to the home dataset, since the crumb type table
    # is global
    foreach my $crumb_type ( @all_crumb_types ) {
        push @{ $dataset_dependency{'home'}{'btiles'} },
            $btile_name_to_index{ $crumb_type->{'btile'} };
    }

    # the same for the Lives btile
    push @{ $dataset_dependency{'home'}{'btiles'} },
        $btile_name_to_index{ $hero->{'lives'}{'btile'} };

    # add rules in the game events rule table to the home dataset
    push @{ $dataset_dependency{ 'home' }{'rules'} },
        @game_events_rule_table;

    # we must then remove duplicates from the lists
    # we take the oportunity to precalculate some tables
    foreach my $dataset ( keys %dataset_dependency ) {

        my %seen = ();
        $dataset_dependency{ $dataset }{'screens'} =
            [ sort { $a <=> $b } grep { !$seen{$_}++ } @{ $dataset_dependency{ $dataset }{'screens'} } ];

        %seen = ();	# reset
        $dataset_dependency{ $dataset }{'btiles'} =
            [ sort { $a <=> $b } grep { !$seen{$_}++ } @{ $dataset_dependency{ $dataset }{'btiles'} } ];

        %seen = ();	# reset
        $dataset_dependency{ $dataset }{'sprites'} =
            [ sort { $a <=> $b } grep { !$seen{$_}++ } @{ $dataset_dependency{ $dataset }{'sprites'} } ];

        %seen = ();	# reset
        $dataset_dependency{ $dataset }{'rules'} =
            [ sort { $a <=> $b } grep { !$seen{$_}++ } @{ $dataset_dependency{ $dataset }{'rules'} } ];

        # we now precalculate the global->local asset index tables for all asset types

        # generate the global->local index btile mapping table
        my @local_btile = ( 0 .. scalar( @{ $dataset_dependency{ $dataset }{'btiles'} } ) - 1 );
        my @global_btile = map { $dataset_dependency{ $dataset }{'btiles'}[ $_ ] } @local_btile;
        my %btile_global_to_dataset_index = ( zip @global_btile, @local_btile );
        $dataset_dependency{ $dataset }{'btile_global_to_dataset_index'} = \%btile_global_to_dataset_index;

        # generate the global->local index sprite mapping table
        my @local_sprite = ( 0 .. scalar( @{ $dataset_dependency{ $dataset }{'sprites'} } ) - 1 );
        my @global_sprite = map { $dataset_dependency{ $dataset }{'sprites'}[ $_ ] } @local_sprite;
        my %sprite_global_to_dataset_index = ( zip @global_sprite, @local_sprite );
        $dataset_dependency{ $dataset }{'sprite_global_to_dataset_index'} = \%sprite_global_to_dataset_index;

        # generate the global->local index rule mapping table
        my @local_rule = ( 0 .. scalar( @{ $dataset_dependency{ $dataset }{'rules'} } ) - 1 );
        my @global_rule = map { $dataset_dependency{ $dataset }{'rules'}[ $_ ] } @local_rule;
        my %rule_global_to_dataset_index = ( zip @global_rule, @local_rule );
        $dataset_dependency{ $dataset }{'rule_global_to_dataset_index'} = \%rule_global_to_dataset_index;

        # generate the global->local index screen mapping table
        my @local_screen = ( 0 .. scalar( @{ $dataset_dependency{ $dataset }{'screens'} } ) - 1 );
        my @global_screen = map { $dataset_dependency{ $dataset }{'screens'}[ $_ ] } @local_screen;
        my %screen_global_to_dataset_index = ( zip @global_screen, @local_screen );
        $dataset_dependency{ $dataset }{'screen_global_to_dataset_index'} = \%screen_global_to_dataset_index;
    }
}

# fixes dependencies between build features.  put here all exceptions and
# mangling needed for build features that need/exclude others, etc.
sub fix_feature_dependencies {

    # currently, the CRUMBS feature needs to have byte-size tile types, so
    # if CRUMBS are used, disable the default packed tile map
    if ( defined( $conditional_build_features{ 'CRUMBS' } ) and
        defined( $conditional_build_features{ 'BTILE_2BIT_TYPE_MAP' }) ) {
        delete $conditional_build_features{ 'BTILE_2BIT_TYPE_MAP' };
    }

    # if ZX_TARGET is 48, CODESETs make no sense
    if ( defined( $conditional_build_features{ 'ZX_TARGET_48' } ) and
        defined( $conditional_build_features{ 'CODESETS' }) ) {
        delete $conditional_build_features{ 'CODESETS' };
    }

    # additional fixes here...
}

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

our ( $opt_b, $opt_d, $opt_c, $opt_t, $opt_s );
getopts("b:d:ct:s:");
if ( defined( $opt_d ) ) {
    $c_file_game_data		= "$opt_d/$c_file_game_data";
    $asm_file_game_data		= "$opt_d/$asm_file_game_data";
    $h_file_game_data		= "$opt_d/$h_file_game_data";
    $h_file_build_features	= "$opt_d/$h_file_build_features";
    $c_file_banked_data_128	=  "$opt_d/$c_file_banked_data_128";
    $dump_file = "$opt_d/$dump_file";
    $output_dest_dir = $opt_d;
}
$build_dir = $opt_b || 'build';
$game_src_dir = $opt_s || 'build/game_src';
$forced_build_target = $opt_t || 0;

# add default build features - these will be updated/modified later
print "Adding default build features...\n";
add_default_build_features;

# read, validate and compile input
print "Reading input data files...\n";
read_input_data;

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

# dump internal data if required to do so
dump_internal_data
    if ( $opt_c );

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

use Data::Dumper;
use List::MoreUtils qw( zip );
use Getopt::Std;
use Data::Compare;
use File::Path qw( make_path );
use File::Copy;

# final destination address for compilation of datasets and codesets
my $dataset_base_address = 0x5B00;
my $codeset_base_address = 0xC000;

# banks reserved for codesets. Bank 4 is reserved for engine code
my @codeset_valid_banks = ( 6, );	# non-contended

# global program state
# if you add any global variable here, don't forget to add a reference to it
# also in $all_state variable in dump_internal_state function at the end of
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

# output lines for each of the files
my @c_game_data_lines;
my $c_dataset_lines;	# hashref: dataset_id => [ C dataset lines ]
my $asm_dataset_lines;	# hashref: dataset_id => [ C dataset lines ]
my $c_codeset_lines;	# hashref: codeset_id => [ C codeset lines ]
my $asm_codeset_lines;	# hashref: codeset_id => [ C codeset lines ]
my @h_game_data_lines;
my @h_build_features_lines;
my $forced_build_target;
my %conditional_build_features;

# build features that always selected no matter what
my @default_build_features = qw(
    BTILE_PACKED_TYPE_MAP
);

######################################################
## Configuration syntax definitions and lists
######################################################

my $syntax = {
    valid_whens => [ 'enter_screen', 'exit_screen', 'game_loop' ],
};

##########################################
## Input data parsing and state machine
##########################################

sub read_input_data {
    # possible states: NONE, BTILE, SCREEN, SPRITE, HERO, GAME_CONFIG, RULE
    # initial state
    my $state = 'NONE';
    my $cur_btile = undef;
    my $cur_screen = undef;
    my $cur_sprite = undef;
    my $cur_rule = undef;

    # read and process input
    my $num_line = 0;
    while (my $line = <>) {

        $num_line++;

        # cleanup the line
        chomp $line;
        $line =~ s/^\s*//g;		# remove leading blanks
        $line =~ s/\s*$//g;		# remove trailing blanks
        $line =~ s/\/\/.*$//g;		# remove comments (//...)
        next if $line eq '';		# ignore blank lines

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
            if ( $line =~ /^BEGIN_SPRITE$/ ) {
                $state = 'SPRITE';
                $cur_sprite = undef;
                next;
            }
            if ( $line =~ /^BEGIN_HERO$/ ) {
                if ( defined( $hero ) ) {
                    die "A HERO is already defined, there can be only one\n";
                }
                $state = 'HERO';
                $cur_sprite = undef;
                next;
            }
            if ( $line =~ /^BEGIN_GAME_CONFIG$/ ) {
                if ( defined( $game_config ) ) {
                    die "A GAME_CONFIG is already defined, there can be only one\n";
                }
                $state = 'GAME_CONFIG';
                next;
            }
            if ( $line =~ /^BEGIN_RULE$/ ) {
                $state = 'RULE';
                $cur_rule = undef;
                next;
            }
            die "Syntax error:line $num_line: '$line' not recognized (global section)\n";

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
                my $data = png_to_pixels_and_attrs(
                    $build_dir . '/' . $vars->{'file'},
                    $vars->{'xpos'}, $vars->{'ypos'},
                    $vars->{'width'}, $vars->{'height'},
                );
                $cur_btile->{'pixels'} = $data->{'pixels'};
                $cur_btile->{'png_attr'} = $data->{'attrs'};
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
            die "Syntax error:line $num_line: '$line' not recognized (BTILE section)\n";

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
                push @{$cur_sprite->{'pixels'}}, @{ pick_pixel_data_by_color_from_png(
                    $build_dir . '/' . $vars->{'file'}, $vars->{'xpos'}, $vars->{'ypos'}, $vars->{'width'}, $vars->{'height'}, $fgcolor,
                    ( $vars->{'hmirror'} || 0 ), ( $vars->{'vmirror'} || 0 )
                    ) };
                push @{$cur_sprite->{'png_attr'}}, @{ attr_data_from_png(
                    $build_dir . '/' . $vars->{'file'}, $vars->{'xpos'}, $vars->{'ypos'}, $vars->{'width'}, $vars->{'height'},
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
                push @{$cur_sprite->{'mask'}}, @{ pick_pixel_data_by_color_from_png(
                    $build_dir . '/' . $vars->{'file'}, $vars->{'xpos'}, $vars->{'ypos'}, $vars->{'width'}, $vars->{'height'}, $maskcolor,
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
            die "Syntax error:line $num_line: '$line' not recognized (SPRITE section)\n";

        } elsif ( $state eq 'SCREEN' ) {

            if ( $line =~ /^NAME\s+(\w+)$/ ) {
                $cur_screen->{'name'} = $1;
                next;
            }
            if ( $line =~ /^DATASET\s+(\w+)$/ ) {
                $cur_screen->{'dataset'} = $1;
                next;
            }
            if ( $line =~ /^TITLE\s+'(.+)'$/ ) {
                $cur_screen->{'title'} = $1;
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

                # enemies can always change state (=killed), so assign a state slot
                $item->{'asset_state_index'} = scalar( @{ $cur_screen->{'asset_states'} } );
                push @{ $cur_screen->{'asset_states'} }, { value => 'F_ENEMY_ACTIVE', comment => "Enemy '$item->{name}'" };

                push @{ $cur_screen->{'enemies'} }, $item;
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
                validate_and_compile_screen( $cur_screen );
                $screen_name_to_index{ $cur_screen->{'name'}} = scalar( @all_screens );
                push @all_screens, $cur_screen;
                $state = 'NONE';
                next;
            }
            die "Syntax error:line $num_line: '$line' not recognized (SCREEN section)\n";

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
            if ( $line =~ /^HSTEP\s+(\d+)$/ ) {
                $hero->{'hstep'} = $1;
                next;
            }
            if ( $line =~ /^VSTEP\s+(\d+)$/ ) {
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
            die "Syntax error:line $num_line: '$line' not recognized (HERO section)\n";

        } elsif ( $state eq 'GAME_CONFIG' ) {

            if ( $line =~ /^NAME\s+(\w+)$/ ) {
                $game_config->{'name'} = $1;
                next;
            }
            if ( $line =~ /^ZX_TARGET\s+(\w+)$/ ) {
                $game_config->{'zx_target'} = $1;
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
                        die sprintf( "CODESET must be in range 0..%d\n", scalar(@codeset_valid_banks ) - 1 );
                    }
                }

                # add the needed codeset-related fields.  if a function has
                # no codeset directive, it goes to the 'home' codeset
                if ( not defined( $item->{'codeset'} ) ) {
                    $item->{'codeset'} = 'home';
                }
                my $codeset = $item->{'codeset'};
                if ( not defined( $codeset_functions_by_codeset{ $codeset } ) ) {
                    $codeset_functions_by_codeset{ $codeset } = [];
                }
                $item->{'local_index'} = scalar( @{ $codeset_functions_by_codeset{ $codeset } } );

                # add the function to the codeset lists
                push @all_codeset_functions, $item;
                push @{ $codeset_functions_by_codeset{ $codeset } }, $item;

                # add the function to the game config
                $game_config->{'game_functions'}{ lc( $item->{'type'} ) } = $item;
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
            if ( $line =~ /^(GAME_AREA|LIVES_AREA|INVENTORY_AREA|DEBUG_AREA)\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my ( $directive, $args ) = ( $1, $2 );
                $game_config->{ lc( $directive ) } = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                next;
            }
            if ( $line =~ /^END_GAME_CONFIG$/ ) {
                $state = 'NONE';
                next;
            }
            die "Syntax error:line $num_line: '$line' not recognized (GAME_CONFIG section)\n";

        } elsif ( $state eq 'RULE' ) {
            if ( $line =~ /^SCREEN\s+(\w+)$/ ) {
                $cur_rule->{'screen'} = $1;
                next;
            }
            if ( $line =~ /^WHEN\s+(\w+)$/ ) {
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
                # bt we must keep them for properly storing the rule
                my $when = $cur_rule->{'when'};
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

                # add the rule index to the proper screen rule table
                push @{ $all_screens[ $screen_name_to_index{ $screen } ]{'rules'}{ $when } }, $index;

                # clean up for next rule
                $cur_rule = undef;
                $state = 'NONE';
                next;
            }
            die "Syntax error:line $num_line: '$line' not recognized (RULE section)\n";

        } else {
            die "Unknown state '$state'\n";
        }
    }
}

# Loads a PNG file
# Returns a ref to a list of refs to lists of pixels
# i.e. each pixel can addressed as $png->[y][x]
my $png_file_cache;
sub load_png_file {
    my $file = shift;

    # if data exists in cache for the file, just return it
    if ( exists( $png_file_cache->{ $file } ) ) {
        return $png_file_cache->{ $file };
    }

    # ..else, build it...
    my $command = sprintf( "pngtopam '%s' | pamtable", $file );
    my @pixel_lines = `$command`;
    chomp @pixel_lines;
    my @pixels = map {			# for each line...
        s/(\d+)/sprintf("%02X",$1)/ge;	# replace decimals by upper hex equivalent
        s/ //g;				# remove spaces
       [ split /\|/ ];			# split each pixel data by '|' and return listref of pixels
    } @pixel_lines;

    # ...store in cache for later use...
    $png_file_cache->{ $file } = \@pixels;

    # ..and return it
    return \@pixels;
}

# extracts pixel data from a PNG file
sub pick_pixel_data_by_color_from_png {
    my ( $file, $xpos, $ypos, $width, $height, $hex_fgcolor, $hmirror, $vmirror ) = @_;
    my $png = load_png_file( $file );
    my @pixels = map {
        join( "",
            map {
                $_ eq $hex_fgcolor ? "##" : "..";		# filter color
                } @$_[ $xpos .. ( $xpos + $width - 1 ) ]	# select cols
        )
    } @$png[ $ypos .. ( $ypos + $height - 1 ) ];		# select rows
    if ( $hmirror ) {
        my @tmp = map { scalar reverse } @pixels;
        @pixels = @tmp;
    }
    if ( $vmirror ) {
        my @tmp = reverse @pixels;
        @pixels = @tmp;
    }
    return \@pixels;
}

# calculates best attributes for a 8x8 cell out of PNG data
my %zx_colors = (
    '000000' => 'BLACK',
    '0000C0' => 'BLUE',
    '00C000' => 'GREEN',
    '00C0C0' => 'CYAN',
    'C00000' => 'RED',
    'C000C0' => 'MAGENTA',
    'C0C000' => 'YELLOW',
    'C0C0C0' => 'WHITE',
    '0000FF' => 'BLUE',
    '00FF00' => 'GREEN',
    '00FFFF' => 'CYAN',
    'FF0000' => 'RED',
    'FF00FF' => 'MAGENTA',
    'FFFF00' => 'YELLOW',
    'FFFFFF' => 'WHITE',
);

sub extract_colors_from_cell {
    my ( $png, $xpos, $ypos ) = @_;
    my %histogram;
    foreach my $x ( $xpos .. ( $xpos + 7 ) ) {
        foreach my $y ( $ypos .. ( $ypos + 7 ) ) {
            my $pixel_color = $png->[$y][$x];
            $histogram{$pixel_color}++;
        }
    }
    my @l = sort { $histogram{ $a } > $histogram{ $b } } keys %histogram;
    if (scalar( @l ) > 2 ) {
        foreach my $e ( 3 .. $#l ) {
            printf STDERR "Warning: color #%s (%s)  detected but ignored\n",
                $l[$e], $zx_colors{ $l[$e] };
        }
    }
    my $bg = $l[0];
    my $fg = $l[1] || $l[0];	# just in case there is only 1 color
    # if one of them is black, it is preferred as bg color, swap them if needed
    if ( $fg eq '000000' ) {
        my $tmp = $bg;
        $bg = $fg;
        $fg = $tmp;
    }
    return { 'bg' => $bg, 'fg' => $fg };
}

sub extract_attr_from_cell {
    my ( $png, $xpos, $ypos ) = @_;
    my $colors = extract_colors_from_cell( $png, $xpos, $ypos );
    my ( $bg, $fg ) = map { $colors->{$_} } qw( bg fg );
    my $attr = sprintf "INK_%s | PAPER_%s", $zx_colors{ $fg }, $zx_colors{ $bg };
    if ( ( $fg =~ /FF/ ) or ( $bg =~ /FF/ ) ) { $attr .= " | BRIGHT"; }
    return $attr;
}

sub attr_data_from_png {
    my ( $file, $xpos, $ypos, $width, $height, $hmirror, $vmirror ) = @_;
    my $png = load_png_file( $file );
    my @attrs;
    # extract attr from cells left-right, top-bottom order
    my $y = $ypos;
    while ( $y < ( $ypos + $height ) ) {
        my $x = $xpos;
        while ( $x < ( $xpos + $width ) ) {
            push @attrs, extract_attr_from_cell( $png, $x, $y );
            $x += 8;
        }
        $y += 8;
    }
    my $c_width = $width / 8;
    my $c_height = $height / 8;
    if ( $hmirror ) {
        my @tmp;
        foreach my $c ( ( $c_width - 1 ) .. 0 ) {	# columns: reverse order
            foreach my $r ( 0 .. ( $c_height - 1 ) ) {	# rows: direct order
                push @tmp, $attrs[ $r * $c_width + $c ];
            }
        }
        @attrs = @tmp;
    }
    if ( $vmirror ) {
        my @tmp;
        foreach my $c ( 0 .. ( $c_width - 1 ) ) {	# columns: direct order
            foreach my $r ( ( $c_height - 1 ) .. 0 ) {	# rows: reverse order
                push @tmp, $attrs[ $r * $c_width + $c ];
            }
        }
        @attrs = @tmp;
    }
    return \@attrs;
}

sub png_to_pixels_and_attrs {
    my ( $file, $xpos, $ypos, $width, $height ) = @_;
    my $png = load_png_file( $file );

    # extract color and pixel data from cells left-right, top-bottom order
    my @colors;
    my @pixels;
    my $y = $ypos;
    while ( $y < ( $ypos + $height ) ) {
        my $x = $xpos;
        while ( $x < ( $xpos + $width ) ) {
            my $c = extract_colors_from_cell( $png, $x, $y );
            push @colors, $c;
            push @pixels, pick_pixel_data_by_color_from_png( $file, $x, $y, 8, 8, $c->{'fg'} );
            $x += 8;
        }
        $y += 8;
    }

    # we need to rearrange pixel data
    my @pixel_data_lines;
    my $nrows = $height / 8;
    my $ncols = $width / 8;
    foreach my $r ( 0 .. ( $nrows - 1 ) ) {
        foreach my $l ( 0 .. 7 ) {
            my $pixel_data_line;
            foreach my $c ( 0 .. ( $ncols - 1 ) ) {
                $pixel_data_line .= $pixels[ $r * $ncols + $c ][ $l ];
            }
            push @pixel_data_lines, $pixel_data_line;
        }
    }

    return {
            'pixels'	=> \@pixel_data_lines,
            'attrs'	=> attr_data_from_png( $file, $xpos, $ypos, $width, $height ),
    };
}

######################################
## BTile functions
######################################

sub validate_and_compile_btile {
    my $tile = shift;
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
    my $num_attrs = $tile->{'rows'} * $tile->{'cols'};
    if ( defined( $tile->{'attr'} ) ) {
        ( scalar( @{$tile->{'attr'}} ) == $num_attrs ) or
            die "Btile '$tile->{name}' should have $num_attrs ATTR elements\n";
    } else {
        ( scalar( @{$tile->{'png_attr'}} ) == $num_attrs ) or
            die "Btile '$tile->{name}' should have $num_attrs elements in PNG_ATTR\n";
    }
    ( scalar( @{$tile->{'pixels'}} ) == $tile->{'rows'} * 8 ) or
        die "Btile '$tile->{name}' should have ".( $tile->{'rows'} * 8 )." PIXELS elements\n";
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
}

sub generate_btile {
    my ( $tile, $dataset ) = @_;

    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "// Big tile '%s'\n\n", $tile->{'name'} );
    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "uint8_t btile_%s_tile_data[%d] = {\n%s\n};\n",
        $tile->{'name'},
        scalar( map { @$_ } @{ $tile->{'pixel_bytes'} } ),
        join( ", ",
            map { '0x'.sprintf('%02x',$_) }
            map { @$_ }
            @{ $tile->{'pixel_bytes'} }
        ) );
    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "uint8_t *btile_%s_tiles[%d] = { %s };\n",
        $tile->{'name'},
        scalar( map { @$_ } @{ $tile->{'pixel_bytes'} } ) / 8,
        join( ', ',
            map { sprintf( "&btile_%s_tile_data[%d]", $tile->{'name'}, $_ ) }
            grep { ( $_ % 8 ) == 0 }
            ( 0 .. ( $tile->{'rows'} * $tile->{'cols'} * 8 - 1 ) )
        ) );
    # manually specified attrs have preference over PNG ones
    my $attrs = ( $tile->{'attr'} || $tile->{'png_attr'} );
    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "uint8_t btile_%s_attrs[%d] = { %s };\n",
        $tile->{'name'},
        scalar( @{ $attrs } ),
        join( ', ', @{ $attrs } ) );
    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "\n// End of Big tile '%s'\n\n", $tile->{'name'} );

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

    # if the sprite has no 'sequence_delay' parameter, define as 0
    if ( not defined( $sprite->{'sequence_delay'} ) ) {
        $sprite->{'sequence_delay'} = 0;
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

sub validate_and_compile_screen {
    my $screen = shift;
    defined( $screen->{'name'} ) or
        die "Screen has no NAME\n";
    defined( $screen->{'hero'} ) or
        die "Screen '$screen->{name}' has no Hero\n";

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
    }

    # compile SCREEN_DATA lines
    compile_screen_data( $screen );

    ( scalar( @{$screen->{'btiles'}} ) > 0 ) or
        die "Screen '$screen->{name}' has no Btiles\n";
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
    }

    # screen enemies
    if ( scalar( @{ $screen->{'enemies'} } ) ) {
        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "// Screen '%s' enemy data\n", $screen->{'name'} );
        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "struct enemy_info_s screen_%s_enemies[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'enemies'}} ) );
        push @{ $c_dataset_lines->{ $dataset } }, join( ",\n", map {
                sprintf( "\t{ %s, %d, %s, { { %d, %d }, { %d, %d, %d, %d } }, { %d, %d, %d, %d }, { %s, %d, %d, .data.%s={ %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d }, %s }, %s }",
                    # SP1 sprite pointer, will be initialized later
                    'NULL',

                    # index into global sprite graphics table
                    $sprite_global_to_dataset_index->{ $sprite_name_to_index{ $_->{'sprite'} } },

                    # color for the sprite
                    $_->{'color'},

                    # animation_data: delay_data values
                    $_->{'animation_delay'}, ( $_->{'sequence_delay'} || 0 ),
                    # animation_data: current values (initial)
                    # sequence number
                    $all_sprites[ $sprite_name_to_index{ $_->{'sprite'} } ]{'sequence_name_to_index'}{ $_->{'initial_sequence'} },
                    0,0,0, # sequence_counter, frame_delay_counter, sequence_delay_counter: will be initialized later

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
            } @{$screen->{'items'}} );
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
                sprintf( "\t{ .position = { %d, %d, %d, %d }, .state_index = %s }",
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
    my $local_num_sprite	= $dataset_dependency{'home'}{'sprite_global_to_dataset_index'}{ $num_sprite };

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
#define	HERO_MOVE_HSTEP			$hstep
#define	HERO_MOVE_VSTEP			$vstep
#define	HERO_NUM_LIVES			$num_lives
#define	HERO_LIVES_BTILE_NUM		$lives_btile_num

EOF_HERO1
;

    # hero sprite must be always available - output sprite into home bank
}

sub generate_bullets {
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

    push @h_game_data_lines, <<EOF_BULLET4

//////////////////////////////
// Bullets definition
//////////////////////////////

#define	BULLET_MAX_BULLETS	$max_bullets
#define	BULLET_SPRITE_WIDTH	$width
#define	BULLET_SPRITE_HEIGHT	$height
#define BULLET_SPRITE_ID	$local_sprite_index
#define	BULLET_SPRITE_FRAMES	( home_assets->all_sprite_graphics[ BULLET_SPRITE_ID ].frame_data.frames )
#define	BULLET_SPRITE_XTHRESH	$xthresh
#define	BULLET_SPRITE_YTHRESH	$ythresh
#define	BULLET_MOVEMENT_DX	$dx
#define	BULLET_MOVEMENT_DY	$dy
#define	BULLET_MOVEMENT_DELAY	$delay
#define	BULLET_RELOAD_DELAY	$reload_delay

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
        push @c_game_data_lines, "\t{ NULL, { 0, 0, 0, 0 }, 0, 0, 0, 0 },\n";
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

    add_build_feature( 'INVENTORY' );

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

sub generate_game_functions {
    push @h_game_data_lines, "// game config\n";

    # generate extern declarations, only for functions in 'home' codeset
    push @h_game_data_lines, join( "\n", 
        map {
            sprintf( "void %s(void);", $game_config->{'game_functions'}{ $_ }{'name'} )
        } grep {
            ( $game_config->{'zx_target'} eq '48' ) or
            ( $game_config->{'game_functions'}{ $_ }{'codeset'} eq 'home' )
        } sort keys %{ $game_config->{'game_functions'} } );
    push @h_game_data_lines, "\n\n";

    # generate macro calls for all functions
    push @h_game_data_lines, join( "\n", 
        map {
            sprintf( "#define RUN_GAME_FUNC_%-30s (%s)",
                uc($_) . '()',
                $game_config->{'game_functions'}{ $_ }{'codeset_function_call_macro'},
            )
        } sort keys %{ $game_config->{'game_functions'} }
    );

    push @h_game_data_lines, "\n\n";
}

sub generate_game_areas {
    # output game areas
    push @c_game_data_lines, "// screen areas\n";
    push @c_game_data_lines, "\n" . join( "\n", map {
        sprintf( "struct sp1_Rect %s = { %s_TOP, %s_LEFT, %s_WIDTH, %s_HEIGHT };",
            $_, ( uc( $_ ) ) x 4 )
        } qw( game_area lives_area inventory_area debug_area )
    ) . "\n\n";

    # output definitions for screen areas
    push @h_game_data_lines, "\n" . join( "\n", map {
            "// " .uc( $_ ). " definitions\n" .
            sprintf( "#define %s_TOP	%d\n", uc( $_ ), $game_config->{ $_ }{'top'} ) .
            sprintf( "#define %s_LEFT	%d\n", uc( $_ ), $game_config->{ $_ }{'left'} ) .
            sprintf( "#define %s_BOTTOM	%d\n", uc( $_ ), $game_config->{ $_ }{'bottom'} ) .
            sprintf( "#define %s_RIGHT	%d\n", uc( $_ ), $game_config->{ $_ }{'right'} ) .
            sprintf( "#define %s_WIDTH	( %s_RIGHT - %s_LEFT + 1 )\n", uc( $_ ), uc( $_ ), uc( $_ ) ) .
            sprintf( "#define %s_HEIGHT	( %s_BOTTOM - %s_TOP + 1 )\n", uc( $_ ), uc( $_ ), uc( $_ ) ) .
            sprintf( "extern struct sp1_Rect %s;\n", $_ )
        } qw( game_area lives_area inventory_area debug_area )
    );
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
    exists( $screen_name_to_index{ $screen } ) or
        die "Screen '$screen' is not defined\n";

    defined( $rule->{'when'} ) or
        die "Rule has no WHEN clause\n";
    my $when = $rule->{'when'};
    grep { $when eq $_ } @{ $syntax->{'valid_whens'} } or
        die "WHEN must be one of ".join( ", ", map { uc } @{ $syntax->{'valid_whens'} } )."\n";

#    defined( $rule->{'check'} ) and scalar( @{ $rule->{'check'} } ) or
#        die "At least one CHECK clause must be specified\n";

    defined( $rule->{'do'} ) and scalar( @{ $rule->{'do'} } ) or
        die "At least one DO clause must be specified\n";

    # do any special filtering of values

    # check filtering
    foreach my $chk ( @{ $rule->{'check'} } ) {
        my ( $check, $check_data ) = split( /\s+/, $chk );

        # hotzone filtering
        if ( $check =~ /^HERO_OVER_HOTZONE$/ ) {
            $check_data = $all_screens[ $screen_name_to_index{ $rule->{'screen'} } ]{'hotzone_name_to_index'}{ $check_data };
            # regenerate the value with the filtered data
            $chk = sprintf( "%s\t%d", $check, $check_data );
        }

    }

    # action filtering
    foreach my $do ( @{ $rule->{'do'} } ) {
        $do =~ m/^(\w+)\s*(.*)$/;
        my ( $action, $action_data ) = ( $1, $2 );

        # hotzone filtering
        if ( $action =~ /^(ENABLE|DISABLE)_HOTZONE$/ ) {
            $action_data = $all_screens[ $screen_name_to_index{ $rule->{'screen'} } ]{'hotzone_name_to_index'}{ $action_data };
            # regenerate the value with the filtered data
            $do = sprintf( "%s\t%d", $action, $action_data );
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
            # regenerate the value with the filtered data
            $do = sprintf( "%s\t%s", $action, $action_data );
        }

        # btile filtering
        if ( $action =~ /^(ENABLE|DISABLE)_BTILE$/ ) {
            $action_data = $all_screens[ $screen_name_to_index{ $rule->{'screen'} } ]{'btile_name_to_index'}{ $action_data };
            # regenerate the value with the filtered data
            $do = sprintf( "%s\t%d", $action, $action_data );
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
            # regenerate the value with the filtered data
            $do = sprintf( "%s\t%s", $action, $action_data );
        }

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
    CALL_CUSTOM_FUNCTION	=> ".data.custom.function = %s",
    ITEM_IS_OWNED		=> ".data.item.item_id = %s",
    HERO_OVER_HOTZONE		=> ".data.hotzone.num_hotzone = %s",
    SCREEN_FLAG_IS_SET		=> ".data.flag_state.flag = %s",
    SCREEN_FLAG_IS_RESET	=> ".data.flag_state.flag = %s",
};

my $action_data_output_format = {
    SET_USER_FLAG		=> ".data.user_flag.flag = %s",
    RESET_USER_FLAG		=> ".data.user_flag.flag = %s",
    INC_LIVES			=> ".data.lives.count = %s",
    PLAY_SOUND			=> ".data.play_sound.sound_id = %s",
    CALL_CUSTOM_FUNCTION	=> ".data.custom.function = %s",
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
};

sub generate_rule_checks {
    my ( $rule, $index ) = @_;
    my $num_checks = scalar( @{ $rule->{'check'} } );

    return if ( not scalar( @{ $rule->{'check'} } ) );

    my $output = sprintf( "struct flow_rule_check_s flow_rule_checks_%05d[%d] = {\n",
        $index, $num_checks );
    foreach my $ch ( @{ $rule->{'check'} } ) {
        my ( $check, $check_data ) = split( /\s+/, $ch );
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
        if ( lc( $action ) eq 'call_custom_function' ) {
            push @h_game_data_lines, sprintf( "void %s( void );\n", $action_data );
        }
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
            if ( not $is_valid_btile{ $item->{'name'} } ) {
                warn sprintf( "Screen '%s': undefined btile for item '%s'\n", $screen->{'name'}, $item->{'name'} );
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
    if ( $forced_build_target ) {
        $game_config->{'zx_target'} = $forced_build_target;
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
    db	$num_btiles		;; .num_btiles
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
    foreach my $tile ( @dataset_btiles ) { generate_btile( $tile, $dataset ); }

    # generate the global btile table for this dataset
    push @{ $c_dataset_lines->{ $dataset } }, "// Dataset BTile table\n";
    push @{ $c_dataset_lines->{ $dataset } }, sprintf( "struct btile_s all_btiles[ %d ] = {\n", scalar( @dataset_btiles ) );
    foreach my $tile ( @dataset_btiles ) {
        push @{ $c_dataset_lines->{ $dataset } }, sprintf( "\t{ %d, %d, &btile_%s_tiles[0], &btile_%s_attrs[0] },\n",
            $tile->{'rows'},
            $tile->{'cols'},
            $tile->{'name'},
            $tile->{'name'} );
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
            sprintf( "\t// Screen '%s'\n\t{\n", $_->{'name'} ) .
            sprintf( "\t\t.global_screen_num = %d,\n", $screen_name_to_index{ $_->{'name'} } ) .
            sprintf( "\t\t.title = %s,\n", ( defined( $screen->{'title'} ) ? '"'.$screen->{'title'}.'"' : 'NULL' ) ) .
            sprintf( "\t\t.btile_data = { %d, %s },\t// btile_data\n",
                scalar( @{$_->{'btiles'}} ), ( scalar( @{$_->{'btiles'}} ) ? sprintf( 'screen_%s_btile_pos', $_->{'name'} ) : 'NULL' ) ) .
            sprintf( "\t\t.enemy_data = { %d, %s },\t// enemy_data\n",
                scalar( @{$_->{'enemies'}} ), ( scalar( @{$_->{'enemies'}} ) ? sprintf( 'screen_%s_enemies', $_->{'name'} ) : 'NULL' ) ) .
            sprintf( "\t\t.hero_data = { %d, %d },\t// hero_data\n",
                $_->{'hero'}{'startup_xpos'}, $_->{'hero'}{'startup_ypos'} ) .
            ( scalar( @all_items) ? sprintf( "\t\t.item_data = { %d, %s },\t// item_data\n",
                scalar( @{$_->{'items'}} ), ( scalar( @{$_->{'items'}} ) ? sprintf( 'screen_%s_items', $_->{'name'} ) : 'NULL' ) )
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
#include "rage1/codeset.h"

extern struct dataset_assets_s all_assets_dataset_home;

GAME_DATA_H_1
;
}

sub generate_h_ending {
    push @h_game_data_lines, <<GAME_DATA_H_3
#endif // _GAME_DATA_H
GAME_DATA_H_3
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
    $max_sprites += $hero->{'bullet'}{'max_bullets'};
    my $bs = $all_sprites[ $sprite_name_to_index{ $hero->{'bullet'}{'sprite'} } ];
    $max_spritechars += $hero->{'bullet'}{'max_bullets'} * ( $bs->{'rows'} + 1 ) * ( $bs->{'cols'} + 1 );

    # 20 bytes for a safety margin, plus 6 bytes per allocation, plus 20
    # bytes per sprite, plus 24 bytes per sprite char
    my $max_heap_usage = 20 + $max_sprites * (20 + 6) + $max_spritechars * (24 + 6);

    # max dataset size: memory from $5B00->$7FFF minus the heap
    my $max_dataset_size = ( 0x8000 - 0x5B00 ) - $max_heap_usage;

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

    add_build_feature( sprintf( "ZX_TARGET_%s\n", $game_config->{'zx_target'} ) );

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
}

sub add_build_feature {
    my $f = shift;
    $conditional_build_features{ $f }++;
}

sub add_default_build_features {
    foreach my $f ( @default_build_features ) {
        add_build_feature( $f );
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
        add_build_feature( 'CODESETS' );
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
                "#define CALL_GAME_FUNCTION_%-30s  (%s())\n",
                uc( $function->{'name'} ) . '()',
                $function->{'name'},
            );
        } else {
            # macros for 128K mode
            add_build_feature( 'CODESETS' );
            push @h_game_data_lines, sprintf(
                "#define CALL_GAME_FUNCTION_%-30s  (codeset_call_function( CODESET_FUNCTION_%s ))\n",
                uc( $function->{'name'} ) . '()',
                uc( $function->{'name'} ),
            );
        }
        $function->{'codeset_function_call_macro'} = sprintf(
            'CALL_GAME_FUNCTION_%s()', uc( $function->{'name'} )
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

sub generate_codesets {

    # If in 128K mode, for each codeset except 'home' codeset we create the
    # needed data structures.  If we are in 48K mode, there will be no
    # codesets besides 'home' so this will not run
    foreach my $codeset ( grep { "$_" ne 'home' } keys %codeset_functions_by_codeset ) {

        my $num_codeset_functions = scalar( @{ $codeset_functions_by_codeset{ $codeset } } );

        push @h_game_data_lines, "// codeset assets struct - only valid in codesets\n";
        push @h_game_data_lines, "extern struct codeset_assets_s all_codeset_assets;\n";

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
	db	$num_codeset_functions			;; .num_functions
	dw	_codeset_functions	;; .functions

EOF_CODESET_LINES_MAIN_ASM
;

        push @{ $c_codeset_lines->{ $codeset } }, <<EOF_CODESET_LINES_MAIN
#include <stdlib.h>

#include "features.h"

#include "rage1/codeset.h"

#include "game_data.h"

EOF_CODESET_LINES_MAIN
;

        # add extern codeset function declarations
        push @{ $c_codeset_lines->{ $codeset } }, "// codeset functions table\n";
        foreach my $function ( @{ $codeset_functions_by_codeset{ $codeset } } ) {
            push @{ $c_codeset_lines->{ $codeset } }, sprintf( "extern void %s( void );\n", $function->{'name'} );
        }

        # add the codeset function table
        push @{ $c_codeset_lines->{ $codeset } }, "codeset_function_t codeset_functions[ $num_codeset_functions ] = {\n";
        foreach my $function ( @{ $codeset_functions_by_codeset{ $codeset } } ) {
            push @{ $c_codeset_lines->{ $codeset } }, sprintf( "\t&%s,\n", $function->{'name'} );
        }
        push @{ $c_codeset_lines->{ $codeset } }, "};\n\n";

    }
}

# this function is called from main
sub generate_game_data {

    # generate header lines for all output files
    generate_c_home_header;
    generate_h_header;

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
    }

    # home bank items
    generate_hero;
    generate_bullets;
    generate_items;
    generate_global_screen_data;
    generate_game_areas;
    generate_game_config;
    generate_misc_data;

    # codeset items
    generate_codesets;
    generate_global_codeset_data;

    # this must be generated after codesets, it needs the codeset function
    # call macros
    generate_game_functions;

    # generate conditional build features
    add_default_build_features;
    generate_conditional_build_features;

    # generate ending lines if needed
    generate_h_ending;
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
    my %files_to_copy;
    foreach my $codeset ( sort grep { /\d+/ } keys %$c_codeset_lines ) {

        # create the destination directory
        my $dst_dir = sprintf( $output_dest_dir . '/' . $codeset_src_dir_format, $codeset );
        if ( ! -d $dst_dir ) {
            make_path( $dst_dir ) or
                die "** Could not create destination directory $dst_dir\n";
        }

        # note the files to be moved to the codeset source dir
        foreach my $function ( @{ $codeset_functions_by_codeset{ $codeset } } ) {
            if ( not defined( $files_to_copy{ $function->{'file'} } ) ) {
                $files_to_copy{ $function->{'file'} } = {
                    src => $game_src_dir . '/' . $function->{'file'},
                    dst => $dst_dir . '/' . $function->{'file'},
                };
            }
        }

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
        foreach my $file ( keys %files_to_copy ) {
            my $src_file = $files_to_copy{ $file }{'src'};
            my $dst_file = $files_to_copy{ $file }{'dst'};
            move( $src_file, $dst_file ) or
                die "** Could not move $src_file to $dst_file\n";
        }
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
    push @{ $dataset_dependency{'home'}{'sprites'} },
        $sprite_name_to_index{ $hero->{'bullet'}{'sprite'} };

    # item btiles are always added to the home dataset, since the item table
    # is global
    foreach my $item ( @all_items ) {
        push @{ $dataset_dependency{'home'}{'btiles'} },
            $btile_name_to_index{ $item->{'btile'} };
    }

    # the same for the Lives btile
    push @{ $dataset_dependency{'home'}{'btiles'} },
        $btile_name_to_index{ $hero->{'lives'}{'btile'} };

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
        all_rules			=> \@all_rules,
        hero				=> $hero,
        game_config			=> $game_config,
        dataset_dependency		=> \%dataset_dependency,
        all_codeset_functions		=> \@all_codeset_functions,
        codeset_function_name_to_index	=> \%codeset_function_name_to_index,
        codeset_functions_by_codeset	=> \%codeset_functions_by_codeset,
    };

    print DUMP Data::Dumper->Dump( [ $all_state ], [ 'all_state' ] );
    close DUMP;
}

#########################
## Main loop
#########################

our ( $opt_b, $opt_d, $opt_c, $opt_t, $opt_s );
getopts("b:d:ct:s:");
if ( defined( $opt_d ) ) {
    $c_file_game_data = "$opt_d/$c_file_game_data";
    $asm_file_game_data = "$opt_d/$asm_file_game_data";
    $h_file_game_data = "$opt_d/$h_file_game_data";
    $h_file_build_features = "$opt_d/$h_file_build_features";
    $dump_file = "$opt_d/$dump_file";
    $output_dest_dir = $opt_d;
}
$build_dir = $opt_b || 'build';
$game_src_dir = $opt_s || 'build/game_src';
$forced_build_target = $opt_t || 0;

# read, validate and compile input
read_input_data;

# run consistency checks
run_consistency_checks;

# generate output
create_dataset_dependencies;
generate_game_data;
output_game_data;

# dump internal data if required to do so
dump_internal_data
    if ( $opt_c );

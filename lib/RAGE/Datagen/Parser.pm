package RAGE::Datagen::Parser;

################################################################################
##
## RAGE1 - Retro Adventure Game Engine, release 1
## (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
##
## This code is published under a GNU GPL license version 3 or later.  See
## LICENSE file in the distribution for details.
##
################################################################################
##
## RAGE::Datagen::Parser — the .gdata parser / state-machine for datagen
## (Task 6, Stage 2 — final/largest extraction).  read_input_data() reads every
## .gdata file and builds the whole datagen model: it pushes into the model
## arrays (@all_btiles, @all_sprites, @all_screens, @all_items, @all_rules,
## @all_crumb_types, @all_codeset_functions, @game_events_rule_table), fills the
## name->index hashes (%btile_name_to_index, %sprite_name_to_index,
## %screen_name_to_index, %item_name_to_index, %crumb_type_name_to_index),
## assigns $game_config / $hero, and registers build features.  Moved verbatim
## from tools/datagen.pl; the shared globals live in the RAGE::Datagen::Context
## object ($ctx), threaded in as read_input_data's first positional arg and
## reached as $ctx->{field} (e.g. $ctx->{all_btiles}, $ctx->{game_config},
## $ctx->{hero}); $ctx is also passed first into the sibling helpers imported
## from their RAGE::Datagen::* modules (see the use list below), except the pure
## input_backend_for_platform, which takes no $ctx.  Behaviour (and emitted
## bytes) is unchanged.
##
## Exported: read_input_data.
##
################################################################################

use strict;
use warnings;
use utf8;

use RAGE::Datagen::ColorTokens qw( resolve_color_tokens );
use RAGE::Datagen::PngDispatch qw( dispatch_png_asset_handling );
use RAGE::Datagen::BuildFeatures qw( add_build_feature input_backend_for_platform );
use RAGE::Datagen::Btiles qw( validate_and_compile_btile );
use RAGE::Datagen::Sprites qw( validate_and_compile_sprite );
use RAGE::Datagen::Entities qw( validate_and_compile_hero );
use RAGE::Datagen::Screens qw( validate_screen compile_screen );
use RAGE::Datagen::FlowRules qw( validate_and_compile_rule find_existing_rule_index );

use Exporter 'import';
our @EXPORT_OK = qw( read_input_data );

sub read_input_data {
    my $ctx = shift;
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
                    if ( not defined( $ctx->{screen_name_to_index}{ $name } ) ) {
                        die "PATCH_SCREEN: $file, line $current_line: '$name' is not the name of an existing screen\n";
                    }
                    $state = 'SCREEN';
                    $screen_patching = 1;
                    $cur_screen = $ctx->{all_screens}[ $ctx->{screen_name_to_index}{ $name } ];
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
                    if ( not defined( $ctx->{game_config} ) ) {
                        die "PATCH_GAME_CONFIG: $file, line $current_line: GAME_CONFIG has not been loaded yet\n";
                    }
                    $state = 'GAME_CONFIG';
                    $game_config_patching = 1;
                    next;
                }
                if ( $line =~ /^PATCH_BTILE\s+NAME=(.+)$/ ) {
                    my $name = $1;
                    if ( not defined( $ctx->{btile_name_to_index}{ $name } ) ) {
                        die "PATCH_BTILE: $file, line $current_line: '$name' is not the name of an existing BTILE\n";
                    }
                    $state = 'BTILE';
                    $btile_patching = 1;
                    $cur_btile = $ctx->{all_btiles}[ $ctx->{btile_name_to_index}{ $name } ];
                    next;
                }
                if ( $line =~ /^PATCH_SPRITE\s+NAME=(.+)$/ ) {
                    my $name = $1;
                    if ( not defined( $ctx->{sprite_name_to_index}{ $name } ) ) {
                        die "PATCH_SPRITE: $file, line $current_line: '$name' is not the name of an existing SPRITE\n";
                    }
                    $state = 'SPRITE';
                    $sprite_patching = 1;
                    $cur_sprite = $ctx->{all_sprites}[ $ctx->{sprite_name_to_index}{ $name } ];
                    next;
                }
                if ( $line =~ /^PATCH_HERO\s+NAME=(.+)$/ ) {
                    my $name = $1;
                    if ( not defined( $ctx->{hero} ) ) {
                        die "PATCH_HERO: $file, line $current_line: HERO has not been loaded yet\n";
                    }
                    if ( ( $ctx->{hero}->{'name'} // '' ) ne $name ) {
                        die "PATCH_HERO: $file, line $current_line: '$name' is not the name of the loaded HERO (loaded: '" . ( $ctx->{hero}->{'name'} // '<unnamed>' ) . "')\n";
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
                    if ( defined( $ctx->{hero} ) ) {
                        die "HERO: $file, line $current_line: a HERO is already defined, there can be only one\n";
                    }
                    $state = 'HERO';
                    $cur_sprite = undef;
                    next;
                }
                if ( $line =~ /^BEGIN_GAME_CONFIG$/ ) {
                    if ( defined( $ctx->{game_config} ) ) {
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
                    my $platform = $ctx->{game_config}->{'platform'};
                    my $png = dispatch_png_asset_handling( $ctx, $platform,
                        'load_png_file', $ctx->{build_dir} . '/' . $vars->{'file'} ) or
                        die "** Error: $file, line $current_line: could not load PNG file " . $ctx->{build_dir} . '/' . $vars->{'file'} . "\n";

                    if ( $vars->{'png_rotate'} || 0 ) {
                        $png = dispatch_png_asset_handling( $ctx, $platform,
                            'png_rotate', $png, $vars->{'png_rotate'} );
                    }
                    if ( $vars->{'png_hmirror'} || 0 ) {
                        $png = dispatch_png_asset_handling( $ctx, $platform,
                            'png_hmirror', $png );
                    }
                    if ( $vars->{'png_vmirror'} || 0 ) {
                        $png = dispatch_png_asset_handling( $ctx, $platform,
                            'png_vmirror', $png );
                    }

                    dispatch_png_asset_handling( $ctx, $platform,
                        'map_png_colors_to_zx_colors', $png );

                    my $data = dispatch_png_asset_handling( $ctx, $platform,
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
                        validate_and_compile_btile( $ctx, $cur_btile );
                        my $index = scalar( @{ $ctx->{all_btiles} } );
                        push @{ $ctx->{all_btiles} }, $cur_btile;
                        $ctx->{btile_name_to_index}{ $cur_btile->{'name'} } = $index;
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
                    my $platform = $ctx->{game_config}->{'platform'};
                    my $fgcolor = uc( $vars->{'fgcolor'} );
                    my $png = dispatch_png_asset_handling( $ctx, $platform,
                        'load_png_file', $ctx->{build_dir} . '/' . $vars->{'file'} ) or
                        die "** Error: $file, line $current_line: could not load PNG file " . $ctx->{build_dir} . '/' . $vars->{'file'} . "\n";

                    dispatch_png_asset_handling( $ctx, $platform,
                        'map_png_colors_to_zx_colors', $png );

                    my $pix = dispatch_png_asset_handling( $ctx, $platform,
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
                    my $platform = $ctx->{game_config}->{'platform'};
                    my $maskcolor = uc( $vars->{'maskcolor'} );
                    my $png = dispatch_png_asset_handling( $ctx, $platform,
                        'load_png_file', $ctx->{build_dir} . '/' . $vars->{'file'} ) or
                        die "** Error: $file, line $current_line: could not load PNG file " . $ctx->{build_dir} . '/' . $vars->{'file'} . "\n";

                    dispatch_png_asset_handling( $ctx, $platform,
                        'map_png_colors_to_zx_colors', $png );

                    my $msk = dispatch_png_asset_handling( $ctx, $platform,
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
                        validate_and_compile_sprite( $ctx, $cur_sprite );
                        $ctx->{sprite_name_to_index}{ $cur_sprite->{'name'}} = scalar( @{ $ctx->{all_sprites} } );
                        push @{ $ctx->{all_sprites} }, $cur_sprite;
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
                    add_build_feature( $ctx, 'SCREEN_TITLES' );
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
                    my $item_index = scalar( @{ $ctx->{all_items} } );
                    push @{ $ctx->{all_items} }, $item;
                    push @{ $cur_screen->{'items'} }, $item_index;
                    $ctx->{item_name_to_index}{ $item->{'name'} } = $item_index;
                    add_build_feature( $ctx, 'HERO_CHECK_TILES_BELOW' );
                    add_build_feature( $ctx, 'INVENTORY' );
                    next;
                }
                if ( $line =~ /^CRUMB\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    my $item = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };

                    if ( not defined( $ctx->{crumb_type_name_to_index}{ $item->{'type'} } ) ) {
                        die "CRUMB: $file, line $current_line: undefined crumb TYPE '$item->{type}'\n";
                    }

                    # crumbs can change state (=grabbed), so assign a state slot
                    $item->{'asset_state_index'} = scalar( @{ $cur_screen->{'asset_states'} } );
                    push @{ $cur_screen->{'asset_states'} }, { value => 'F_CRUMB_ACTIVE', comment => "Crumb '$item->{name}'" };

                    push @{ $cur_screen->{'crumbs'} }, $item;

                    add_build_feature( $ctx, 'HERO_CHECK_TILES_BELOW' );
                    add_build_feature( $ctx, 'CRUMBS' );
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
                    validate_screen( $ctx, $cur_screen );
                    if ( not $screen_patching ) {
                        compile_screen( $ctx, $cur_screen );
                        $ctx->{screen_name_to_index}{ $cur_screen->{'name'}} = scalar( @{ $ctx->{all_screens} } );
                        push @{ $ctx->{all_screens} }, $cur_screen;
                    } else {
                        $screen_patching = 0;
                    }
                    $state = 'NONE';
                    next;
                }
                die "Syntax error: $file, line $current_line: '$line' not recognized (SCREEN section)\n";

            } elsif ( $state eq 'HERO' ) {

                if ( $line =~ /^NAME\s+(\w+)$/ ) {
                    $ctx->{hero}->{'name'} = $1;
                    next;
                }
                if ( $line =~ /^LIVES\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    $ctx->{hero}->{'lives'} = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    next;
                }
                if ( $line =~ /^DAMAGE_MODE\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    $ctx->{hero}->{'damage_mode'} = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    add_build_feature( $ctx, 'HERO_ADVANCED_DAMAGE_MODE' );
                    if ( defined( $ctx->{hero}->{'damage_mode'}{'health_display_function'} ) ) {
                        add_build_feature( $ctx, 'HERO_ADVANCED_DAMAGE_MODE_USE_HEALTH_DISPLAY_FUNCTION' );
                    }
                    next;
                }
                if ( $line =~ /^HSTEP\s+([\d\.]+)$/ ) {
                    $ctx->{hero}->{'hstep'} = $1;
                    next;
                }
                if ( $line =~ /^VSTEP\s+([\d\.]+)$/ ) {
                    $ctx->{hero}->{'vstep'} = $1;
                    next;
                }
                if ( $line =~ /^ANIMATION_DELAY\s+(\d+)$/ ) {
                    $ctx->{hero}->{'animation_delay'} = $1;
                    next;
                }
                if ( $line =~ /^SPRITE\s+(\w+)$/ ) {
                    $ctx->{hero}->{'sprite'} = $1;
                    next;
                }
                if ( $line =~ /^SEQUENCE_UP\s+(\w+)$/ ) {
                    $ctx->{hero}->{'sequence_up'} = $1;
                    next;
                }
                if ( $line =~ /^SEQUENCE_DOWN\s+(\w+)$/ ) {
                    $ctx->{hero}->{'sequence_down'} = $1;
                    next;
                }
                if ( $line =~ /^SEQUENCE_LEFT\s+(\w+)$/ ) {
                    $ctx->{hero}->{'sequence_left'} = $1;
                    next;
                }
                if ( $line =~ /^SEQUENCE_RIGHT\s+(\w+)$/ ) {
                    $ctx->{hero}->{'sequence_right'} = $1;
                    next;
                }
                if ( $line =~ /^STEADY_FRAMES\s+(.*)$/ ) {
                    my $args = $1;
                    my $vars = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    $ctx->{hero}->{'steady_frames'} = $vars;
                    next;
                }
                if ( $line =~ /^BULLET\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    $ctx->{hero}->{'bullet'} = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    next;
                }
                if ( $line =~ /^END_HERO$/ ) {
                    if ( not $hero_patching ) {
                        validate_and_compile_hero( $ctx, $ctx->{hero} );
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
                    $ctx->{game_config}->{'name'} = $1;
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
                        $ctx->{game_config}->{'platform'} = $platform;
                        # No ZX_TARGET for CPC; skip derived_zx_target.
                        add_build_feature( $ctx, 'PLATFORM_CPC464' );      # machine identity
                        add_build_feature( $ctx, 'PLATFORM_CPC_FLAT' );    # memory model
                        # IN5-3: input backend is forced by PLATFORM (cpc* -> CPC).
                        add_build_feature( $ctx, input_backend_for_platform( $platform ) );
                        next;
                    }
                    my $derived_zx_target = ( $platform eq 'zx48' ) ? '48' : '128';
                    # CLI override (-t) still wins; it carries 48|128 from
                    # the Makefile (kept legacy for A1-4 compatibility).
                    if ( $ctx->{forced_build_target} ) {
                        $derived_zx_target = $ctx->{forced_build_target};
                        $platform = ( $ctx->{forced_build_target} eq '48' ) ? 'zx48' : 'zx128';
                    }
                    $ctx->{game_config}->{'zx_target'} = $derived_zx_target;
                    $ctx->{game_config}->{'platform'}  = $platform;
                    add_build_feature( $ctx, sprintf( "ZX_TARGET_%s", $derived_zx_target ) );
                    add_build_feature( $ctx, sprintf( "PLATFORM_%s", uc( $platform ) ) );
                    # IN5-3: input backend is forced by PLATFORM (zx* -> ZX).
                    add_build_feature( $ctx, input_backend_for_platform( $platform ) );
                    next;
                }
                # A1-2: ZX_TARGET is a permanent silent alias for PLATFORM
                # (per README §5.6). Same emission as PLATFORM — both
                # macros are always emitted so the two spellings produce
                # byte-identical builds.
                if ( $line =~ /^ZX_TARGET\s+(\w+)$/ ) {
                    if ( $ctx->{forced_build_target} ) {
                        $ctx->{game_config}->{'zx_target'} = $ctx->{forced_build_target};
                    } else {
                        $ctx->{game_config}->{'zx_target'} = $1;
                    }
                    if ( ( $ctx->{game_config}->{'zx_target'} ne '48' ) and
                        ( $ctx->{game_config}->{'zx_target'} ne '128' ) ) {
                            die "ZX_TARGET: $file, line $current_line: ZX_TARGET must be either 48 or 128\n";
                        }
                    # internal mapping ZX_TARGET 48|128 -> PLATFORM zx48|zx128
                    $ctx->{game_config}->{'platform'} = ( $ctx->{game_config}->{'zx_target'} eq '48' ) ? 'zx48' : 'zx128';
                    add_build_feature( $ctx, sprintf( "ZX_TARGET_%s", $ctx->{game_config}->{'zx_target'} ) );
                    add_build_feature( $ctx, sprintf( "PLATFORM_ZX%s", $ctx->{game_config}->{'zx_target'} ) );
                    # IN5-3: input backend is forced by PLATFORM (zx* -> ZX).
                    add_build_feature( $ctx, input_backend_for_platform( $ctx->{game_config}->{'platform'} ) );
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
                    $ctx->{game_config}->{'gfx_backend'} = $engine;
                    next;
                }
                if ( $line =~ /^DEFAULT_BG_ATTR\s+(.*)$/ ) {
                    # A1-7: resolve generic FG_/BG_ tokens to their ZX
                    # INK_*/PAPER_*/BRIGHT/FLASH form (byte-identical;
                    # legacy spellings pass through unchanged).
                    $ctx->{game_config}->{'default_bg_attr'} = resolve_color_tokens( $1 );
                    next;
                }
                if ( $line =~ /^HERO\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    $ctx->{game_config}->{'hero'} = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    next;
                }
                if ( $line =~ /^SCREEN\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    $ctx->{game_config}->{'screen'} = {
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
                        if ( $item->{'codeset'} > ( scalar( @{ $ctx->{codeset_valid_banks} } ) - 1 ) ) {
                            die sprintf( "CODESET: $file, line $current_line: CODESET must be in range 0..%d\n", scalar(@{ $ctx->{codeset_valid_banks} } ) - 1 );
                        }
                    } else {
                        $item->{'codeset'} = 'home';
                    }

                    # add the needed codeset-related fields.  if a function has
                    # no codeset directive, it goes to the 'home' codeset
                    my $codeset = $item->{'codeset'};
                    if ( not defined( $ctx->{codeset_functions_by_codeset}{ $codeset } ) ) {
                        $ctx->{codeset_functions_by_codeset}{ $codeset } = [];
                    }
                    $item->{'local_index'} = scalar( @{ $ctx->{codeset_functions_by_codeset}{ $codeset } } );

                    # add the function to the codeset lists
                    push @{ $ctx->{all_codeset_functions} }, $item;
                    push @{ $ctx->{codeset_functions_by_codeset}{ $codeset } }, $item;

                    # check that the type is a valid function type
                    if ( not scalar( grep { lc( $item->{'type'} ) eq $_ } @{ $ctx->{valid_game_functions} } ) ) {
                        die sprintf( "GAME_FUNCTION:  $file, line $current_line: Invalid game function type: %s\n", lc( $item->{'type'} ) );
                    }

                    # add the function to the game config
                    if ( lc( $item->{'type'} ) eq 'custom' ) {
                        push @{ $ctx->{game_config}->{'game_functions'}{'custom'} }, $item;
                    } else {
                        $ctx->{game_config}->{'game_functions'}{ lc( $item->{'type'} ) } = $item;
                    }

                    # adjust build feature
                    if ( $codeset ne 'home' ) {
                        add_build_feature( $ctx, 'CODESETS' );
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
                        $ctx->{game_config}->{'sounds'}{ $k } = $vars->{ $k };
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
                    $ctx->{game_config}->{'cpc_palette'} = $pal;
                    next;
                }
                if ( $line =~ /^(GAME_AREA|LIVES_AREA|INVENTORY_AREA|DEBUG_AREA|TITLE_AREA)\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my ( $directive, $args ) = ( $1, $2 );
                    $ctx->{game_config}->{ lc( $directive ) } = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    add_build_feature( $ctx, 'SCREEN_AREA_' . $directive );
                    next;
                }
                if ( $line =~ /^LOADING_SCREEN\s+(.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    $ctx->{game_config}->{'loading_screen'} = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    if ( scalar( grep { defined } map { $ctx->{game_config}->{'loading_screen'}{ $_ } } qw( png scr ) ) != 1 ) {
                        die "LOADING_SCREEN: $file, line $current_line: exactly one of PNG or SCR options (but not both) must be specified\n";
                    }
                    add_build_feature( $ctx, "LOADING_SCREEN" );
                    if ( $ctx->{game_config}->{'loading_screen'}{'wait_any_key'} ) {
                        add_build_feature( $ctx, "LOADING_SCREEN_WAIT_ANY_KEY" );
                    }
                    next;
                }
                if ( $line =~ /^CUSTOM_CHARSET\s+(.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    $ctx->{game_config}->{'custom_charset'} = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };
                    if ( not defined( $ctx->{game_config}->{'custom_charset'}{'file'} ) ) {
                        die "CUSTOM_CHARSET: $file, line $current_line: FILE must be specified\n";
                    }
                    if ( defined( $ctx->{game_config}->{'custom_charset'}{'range'} ) ) {
                        if ( $ctx->{game_config}->{'custom_charset'}{'range'} !~ m/^\d+\-\d+$/ ) {
                            die "CUSTOM_CHARSET: $file, line $current_line: RANGE option must be integers MM-NN\n";
                        }
                    }
                    add_build_feature( $ctx, "CUSTOM_CHARSET" );
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
                    push @{ $ctx->{game_config}->{'binary_data'} }, $blob_info;
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
                        if ( ( $action_function->{'codeset'} ne 'home' ) and ( $action_function->{'codeset'} > ( scalar( @{ $ctx->{codeset_valid_banks} } ) - 1 ) ) ) {
                            die sprintf( "CRUMB_TYPE: $file, line $current_line: CODESET must be in range 0..%d\n", scalar(@{ $ctx->{codeset_valid_banks} } ) - 1 );
                        }

                        # add the needed codeset-related fields.  if a function has
                        # no codeset directive, it goes to the 'home' codeset
                        my $codeset = $action_function->{'codeset'};
                        if ( not defined( $ctx->{codeset_functions_by_codeset}{ $codeset } ) ) {
                            $ctx->{codeset_functions_by_codeset}{ $codeset } = [];
                        }
                        $action_function->{'local_index'} = scalar( @{ $ctx->{codeset_functions_by_codeset}{ $codeset } } );

                        # add the function to the codeset lists
                        push @{ $ctx->{all_codeset_functions} }, $action_function;
                        push @{ $ctx->{codeset_functions_by_codeset}{ $codeset } }, $action_function;

                    }

                    # if an inventory mask is defined keep it, otherwise set it to 0
                    if ( not defined( $item->{'required_items'} ) ) {
                        $item->{'required_items'} = 0;
                    }

                    # add the crumb type to the global list
                    my $index = scalar( @{ $ctx->{all_crumb_types} } );
                    push @{ $ctx->{all_crumb_types} }, $item;
                    $ctx->{crumb_type_name_to_index}{ $item->{'name'} } = $index;
                    next;	# $line
                }
                if ( $line =~ /^TRACKER\s+(\w.*)$/ ) {
                    # ARG1=val1 ARG2=va2 ARG3=val3...
                    my $args = $1;
                    my $item = {
                        map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                        split( /\s+/, $args )
                    };

                    if ( not defined( $ctx->{game_config}->{'tracker'} ) ) {
                        $ctx->{game_config}->{'tracker'} = $item;
                    } else {
                        $ctx->{game_config}->{'tracker'} = { %{ $ctx->{game_config}->{'tracker'} }, %$item };
                    }

                    add_build_feature( $ctx, 'TRACKER' );
                    ( defined( $item->{'type'} ) and grep { $item->{'type'} eq $_ } @{ $ctx->{valid_trackers} } ) or
                        die "TRACKER: TYPE is mandatory, must be one of ".join(",",@{ $ctx->{valid_trackers} })."\n";
                    add_build_feature( $ctx, 'TRACKER_'.uc( $item->{'type'} ) );

                    if ( ( lc( $item->{'type'} ) eq 'vortex2' ) and
                        ( defined( $item->{'fx_channel'} ) or defined( $item->{'fx_volume'} ) ) ) {
                        die "TRACKER: tracker type vortex2 does not support Sound FX\n";
                    }

                    if ( defined( $item->{'fx_channel'} ) ) {
                        if ( not grep { $_ == $item->{'fx_channel'} } ( 0, 1, 2 ) ) {
                            die "TRACKER: $file, line $current_line: FX_CHANNEL can only be 0, 1 or 2\n";
                        }
                        add_build_feature( $ctx, 'TRACKER_SOUNDFX' );
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
                    my $index = defined( $ctx->{game_config}->{'tracker'}{'songs'} ) ?
                        scalar( @{ $ctx->{game_config}->{'tracker'}{'songs'} } ) : 0;
                    $item->{'song_index'} = $index;
                    push @{ $ctx->{game_config}->{'tracker'}{'songs'} }, $item;
                    $ctx->{game_config}->{'tracker'}{'song_index'}{ $item->{'name'} } = $index;
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
                    $ctx->{game_config}->{'tracker'}{'fxtable'} = $item;
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
                    $ctx->{game_config}->{'color'} = $item;
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
                    $ctx->{game_config}->{'custom_state_data'} = $item;
                    add_build_feature( $ctx, 'CUSTOM_STATE_DATA' );
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
                    push @{ $ctx->{game_config}->{'single_use_blobs'} }, $item;
                    add_build_feature( $ctx, 'SINGLE_USE_BLOB' );
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
                    $ctx->{game_config}->{'cpc_color_map'} ||= {};
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
                    my $platform = $ctx->{game_config}->{'platform'} // '';
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
                    $ctx->{game_config}->{'cpc_color_map'}{ $tok } = $fw;
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
                    validate_and_compile_rule( $ctx, $cur_rule );

                    # we must delete WHEN and SCREEN for deduplicating rules,
                    # but we must keep them for properly storing the rule
                    my $when = $cur_rule->{'when'} || '<undefined>';
                    delete $cur_rule->{'when'};
                    my $screen = $cur_rule->{'screen'};
                    delete $cur_rule->{'screen'};

                    # find an identical rule if it exists
                    my $found = find_existing_rule_index( $ctx, $cur_rule );
                    my $index;
                    # use it if found, otherwise add the new one to the global rule list
                    if ( defined( $found ) ) {
                        $index = $found;
                    } else {
                        $index = scalar( @{ $ctx->{all_rules} } );
                        push @{ $ctx->{all_rules} }, $cur_rule;
                    }

                    # add the rule index to the proper screen rule table, or the events rule table
                    if ( $screen eq '__EVENTS__' ) {
                        push @{ $ctx->{game_events_rule_table} }, $index;
                    } else {
                        push @{ $ctx->{all_screens}[ $ctx->{screen_name_to_index}{ $screen } ]{'rules'}{ $when } }, $index;
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

1;

package RAGE::Datagen::Screens;

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
## RAGE::Datagen::Screens — screen validation/compilation and C emission for
## datagen (Task 6, Stage 2 extraction).  Moved verbatim from tools/datagen.pl;
## the only edits are the mechanical scaffold bindings: the shared globals are
## reached via their RAGE::Datagen::Context aliases (@main::all_screens,
## @main::all_btiles, @main::all_sprites, @main::all_items,
## @main::all_crumb_types, %main::screen_name_to_index,
## %main::sprite_name_to_index, %main::btile_name_to_index,
## %main::dataset_dependency, $main::game_config, $main::syntax and the
## per-dataset C emit accumulator $main::c_dataset_lines), and the sibling
## helpers add_build_feature / is_build_feature_enabled are imported from
## RAGE::Datagen::BuildFeatures.
## Behaviour (and emitted bytes) is unchanged.
##
## Exported: validate_screen, compile_screen (parse-time), generate_screens,
## generate_map, generate_global_screen_data (emit-time).  compile_screen_data
## and generate_screen are internal helpers (called only from this module).
##
################################################################################

use strict;
use warnings;
use utf8;

# scaffold aliases (RAGE::Datagen::Context) populated at runtime by datagen.pl;
# silence the benign "used only once" check for these main:: globals.
no warnings 'once';

use RAGE::Datagen::BuildFeatures qw( add_build_feature is_build_feature_enabled );

use Exporter 'import';
our @EXPORT_OK = qw(
    validate_screen compile_screen
    generate_screens generate_map generate_global_screen_data
);

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
                not defined( $main::all_sprites[ $main::sprite_name_to_index{ $s->{'sprite'} } ]{'sequence_name_to_index'}{ $s->{ $seq_param } } ) ) {
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
    my $game_area_width = $main::game_config->{'game_area'}{'right'} - $main::game_config->{'game_area'}{'left'} + 1;
    my $game_area_height = $main::game_config->{'game_area'}{'bottom'} - $main::game_config->{'game_area'}{'top'} + 1;
    my $game_area_top = $main::game_config->{'game_area'}{'top'};
    my $game_area_left = $main::game_config->{'game_area'}{'left'};
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
                my $btile = $main::all_btiles[ $main::btile_name_to_index{ $screen_digraphs->{ $data_dg }{'btile'} } ];
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
    my @dataset_screens = map { $main::all_screens[ $_ ] } @{ $main::dataset_dependency{ $dataset }{'screens'} };

    my $btile_global_to_dataset_index = $main::dataset_dependency{ $dataset }{'btile_global_to_dataset_index'};
    my $sprite_global_to_dataset_index = $main::dataset_dependency{ $dataset }{'sprite_global_to_dataset_index'};
    my $rule_global_to_dataset_index = $main::dataset_dependency{ $dataset }{'rule_global_to_dataset_index'};

    # screen tiles
    if ( scalar( @{ $screen->{'btiles'} } ) ) {
        push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "// Screen '%s' btile data\n", $screen->{'name'} );
        push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "struct btile_pos_s screen_%s_btile_pos[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'btiles'}} ) );

        push @{ $main::c_dataset_lines->{ $dataset } }, join( ",\n", map {
                sprintf("\t{ .type = TT_%s, .row = %d, .col = %d, .btile_id = %d, .state_index = %s }",
                    uc($_->{'type'}), $_->{'row'}, $_->{'col'},
                    $btile_global_to_dataset_index->{ $main::btile_name_to_index{ $_->{'btile'} } },
                    ( "$_->{'asset_state_index'}" eq 'ASSET_NO_STATE' ? 'ASSET_NO_STATE' : $_->{'asset_state_index'} ) )
            } @{$screen->{'btiles'}} );
        push @{ $main::c_dataset_lines->{ $dataset } }, "\n};\n\n";

        # generate animated_btile_s records, they have been previously
        # classified with 'is_animated' = 1
        my $num_animated_btiles = scalar( grep { $_->{'is_animated'} } @{ $screen->{'btiles'} } );
        if ( $num_animated_btiles ) {
            push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "// Screen '%s' animated btile records\n", $screen->{'name'} );
            push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "struct animated_btile_s screen_%s_animated_btiles[ %d ] = {\n",
                $screen->{'name'},
                $num_animated_btiles
            );

            my $btile_pos_index = 0;
            foreach my $btile ( @{ $screen->{'btiles'} } ) {
                if ( $btile->{'is_animated'} ) {
                    push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "\t{ .btile_id = %d, .btile_pos_id = %d, ",
                        $btile_global_to_dataset_index->{ $main::btile_name_to_index{ $btile->{'btile'} } },
                        $btile_pos_index,
                    );
                    push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( ".anim.delay_data.frame_delay = %d, ",
                        $btile->{'animation_delay'}
                    );
                    push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( ".anim.delay_data.sequence_delay = %d, ",
                        $btile->{'sequence_delay'}
                    );
                    push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( ".anim.current.sequence = %d },\n",
                        $main::all_btiles[ $main::btile_name_to_index{ $btile->{'btile'} } ]{'sequence_name_to_index'}{ $btile->{'sequence'} }
                    );
                }
                $btile_pos_index++;
            }
            push @{ $main::c_dataset_lines->{ $dataset } }, "};\n\n";
        }
    }

    # screen enemies
    if ( scalar( @{ $screen->{'enemies'} } ) ) {
        push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "// Screen '%s' enemy data\n", $screen->{'name'} );
        push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "struct enemy_info_s screen_%s_enemies[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'enemies'}} ) );
        push @{ $main::c_dataset_lines->{ $dataset } }, join( ",\n", map {
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
                    $sprite_global_to_dataset_index->{ $main::sprite_name_to_index{ $_->{'sprite'} } },
                    # color for the sprite
                    $_->{'color'},

                    # animation_data: delay_data values
                    $_->{'animation_delay'}, ( $_->{'sequence_delay'} || 0 ),
                    # animation_data: sequence_data values
                    $main::all_sprites[ $main::sprite_name_to_index{ $_->{'sprite'} } ]{'sequence_name_to_index'}{ $_->{'initial_sequence'} },
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
                    $main::all_sprites[ $main::sprite_name_to_index{ $_->{'sprite'} } ]{'sequence_name_to_index'}{ $_->{'sequence_a'} },
                    $main::all_sprites[ $main::sprite_name_to_index{ $_->{'sprite'} } ]{'sequence_name_to_index'}{ $_->{'sequence_b'} },
                    # movement flags
                    $_->{'movement_flags'},

                    # state index
                    $_->{'asset_state_index'},
                 )
            } @{$screen->{'enemies'}} );
        push @{ $main::c_dataset_lines->{ $dataset } }, "\n};\n\n";
    }

    # screen items
    if ( scalar( @{ $screen->{'items'} } ) ) {
        push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "// Screen '%s' item data\n", $screen->{'name'} );
        push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "struct item_location_s screen_%s_items[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'items'}} ) );
        push @{ $main::c_dataset_lines->{ $dataset } }, join( ",\n", map {
                sprintf( "\t{ %d, %d, %d }", $_, $main::all_items[ $_ ]->{'row'}, $main::all_items[ $_ ]->{'col'} )
            } @{ $screen->{'items'} } );
        push @{ $main::c_dataset_lines->{ $dataset } }, "\n};\n\n";
    }

    # screen crumbs
    if ( defined( $screen->{'crumbs'} ) ) {
        push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "// Screen '%s' crumb data\n", $screen->{'name'} );
        push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "struct crumb_location_s screen_%s_crumbs[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'crumbs'}} ) );
        push @{ $main::c_dataset_lines->{ $dataset } }, join( ",\n", map {
                sprintf( "\t{ CRUMB_TYPE_%s, %d, %d, %d }",
                    uc( $_->{'type'} ),
                    $_->{'row'},
                    $_->{'col'},
                    $_->{'asset_state_index'}
                )
            } @{ $screen->{'crumbs'} } );
        push @{ $main::c_dataset_lines->{ $dataset } }, "\n};\n\n";
    }

    # hot zones
    if ( scalar( @{ $screen->{'hotzones'} } ) ) {
        push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "// Screen '%s' hot zone data\n", $screen->{'name'} );
        push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "struct hotzone_info_s screen_%s_hotzones[ %d ] = {\n",
            $screen->{'name'},
            scalar( @{$screen->{'hotzones'}} ) );
        push @{ $main::c_dataset_lines->{ $dataset } }, join( ",\n", map {
                my $x    = ( defined( $_->{'x'} ) ? $_->{'x'} : $_->{'col'} * 8 );
                my $y    = ( defined( $_->{'y'} ) ? $_->{'y'} : $_->{'row'} * 8 );
                my $xmax = $x + ( defined( $_->{'pix_width'} ) ? $_->{'pix_width'} : $_->{'width'} * 8 ) - 1;
                my $ymax = $y + ( defined( $_->{'pix_height'} ) ? $_->{'pix_height'} : $_->{'height'} * 8 ) - 1;
                sprintf( "\t{ .position = { .x.part.integer = %d, .y.part.integer = %d, .xmax = %d, .ymax = %d }, .state_index = %s }",
                    $x, $y, $xmax, $ymax,
                    $_->{'asset_state_index'},
                )
            } @{ $screen->{'hotzones'} } );
        push @{ $main::c_dataset_lines->{ $dataset } }, "\n};\n\n";
    }

    # flow rules
    push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "// Screen '%s' flow rules\n", $screen->{'name'} );
    foreach my $table ( @{ $main::syntax->{'valid_whens'} } ) {
        if ( defined( $screen->{'rules'} ) and defined( $screen->{'rules'}{ $table } ) ) {
            my $num_rules = scalar( @{ $screen->{'rules'}{ $table } } );
            if ( $num_rules ) {
                push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "struct flow_rule_s *screen_%s_%s_rules[ %d ] = {\n\t",
                    $screen->{'name'}, $table, $num_rules );
                push @{ $main::c_dataset_lines->{ $dataset } }, join( ",\n\t",
                    map {
                        sprintf( "&all_flow_rules[ %d ]", $rule_global_to_dataset_index->{ $_ } )
                    } @{ $screen->{'rules'}{ $table } }
                );
                push @{ $main::c_dataset_lines->{ $dataset } }, "\n};\n";
            }
        }
    }

}

sub generate_screens {
    my $dataset = shift;

    # generate the list of dataset screens,  return immediately if empty
    my @dataset_screens = map { $main::all_screens[ $_ ] } @{ $main::dataset_dependency{ $dataset }{'screens'} };
    return if not scalar( @dataset_screens );

    push @{ $main::c_dataset_lines->{ $dataset } }, <<EOF_SCREENS

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
    my @dataset_screens = map { $main::all_screens[ $_ ] } @{ $main::dataset_dependency{ $dataset }{'screens'} };
    return if not scalar( @dataset_screens );

    my $num_screens = scalar( @dataset_screens );

    # output global map data structure
    push @{ $main::c_dataset_lines->{ $dataset } }, <<EOF_MAP

////////////////////////////
// Map definition
////////////////////////////

// dataset map

EOF_MAP
;
    push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "struct map_screen_s all_screens[ %d ] = {\n", $num_screens );

    push @{ $main::c_dataset_lines->{ $dataset } }, join( ",\n", map {
            my $screen_name = $_->{'name'};
            my $screen = $_;
            my $num_animated_btiles = scalar( grep { $_->{'is_animated'} } @{ $_->{'btiles'} } );
            sprintf( "\t// Screen '%s'\n\t{\n", $_->{'name'} ) .

            sprintf( "\t\t.global_screen_num = %d,\n", $main::screen_name_to_index{ $_->{'name'} } ) .

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
            ( scalar( @main::all_items) ? sprintf( "\t\t.item_data = { %d, %s },\t// item_data\n",
                scalar( @{$_->{'items'}} ), ( scalar( @{$_->{'items'}} ) ? sprintf( 'screen_%s_items', $_->{'name'} ) : 'NULL' ) )
                : '' ) .

            # only output if CRUMBS are used
            ( scalar( @main::all_crumb_types) ? sprintf( "\t\t.crumb_data = { %d, %s },\t// item_data\n",
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
                } @{ $main::syntax->{'valid_whens'} } ) . "\n" .

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

    push @{ $main::c_dataset_lines->{ $dataset } }, "\n};\n\n";

}

sub generate_global_screen_data {

    my $dataset = 'home';

    # generate global screen_dataset_map variable with screen->dataset mapping
    push @{ $main::c_dataset_lines->{ $dataset } }, "\n// Global screen->dataset mapping table\n";
    push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "struct screen_dataset_map_s screen_dataset_map[ %d ] = {\n", scalar( @main::all_screens) );
    foreach my $global_screen_index ( 0 .. ( scalar( @main::all_screens) - 1 ) ) {
        my $screen = $main::all_screens[ $global_screen_index ];
        my $screen_dataset = ( $main::game_config->{'zx_target'} eq '48' ? 'home' : $screen->{'dataset'} );
        push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "\t{ .dataset_num = %d, .dataset_local_screen_num = %d },\t// Screen '%s'\n",
            $screen->{'dataset'},
            $main::dataset_dependency{ $screen_dataset }{'screen_global_to_dataset_index'}{ $global_screen_index },
            $screen->{'name'}
        );
    }
    push @{ $main::c_dataset_lines->{ $dataset } }, "};\n\n";

    # screen asset state tables
    foreach my $screen ( @main::all_screens ) {
        push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "// Screen '%s' asset state table\n", $screen->{'name'} );
        push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "struct asset_state_s screen_%s_asset_state[ %d ] = {\n\t",
            $screen->{'name'}, scalar( @{ $screen->{'asset_states'} } )
        );
        push @{ $main::c_dataset_lines->{ $dataset } }, join( "\n\t",
            map {
                sprintf( "{ .asset_state = %s, .asset_initial_state = %s },\t// %s",
                    $_->{'value'}, $_->{'value'}, $_->{'comment'},
                )
            } @{ $screen->{'asset_states'} }
        );
        push @{ $main::c_dataset_lines->{ $dataset } }, "\n};\n\n";
    }

    # global table of asset state tables for all screens
    push @{ $main::c_dataset_lines->{ $dataset } }, "// Global table of asset state tables for all screens\n";
    push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "struct asset_state_table_s all_screen_asset_state_tables[ %d ] = {\n\t",
        scalar( @main::all_screens ) );
    push @{ $main::c_dataset_lines->{ $dataset } }, join( ",\n\t",
        map {
            sprintf( "{ .num_states = %d, .states = &screen_%s_asset_state[0] }",
                scalar( @{$_->{ 'asset_states' } } ), $_->{'name'}
            )
        } @main::all_screens
    );
    push @{ $main::c_dataset_lines->{ $dataset } }, "\n};\n\n";

}

1;

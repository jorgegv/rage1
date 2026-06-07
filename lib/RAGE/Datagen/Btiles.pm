package RAGE::Datagen::Btiles;

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
## RAGE::Datagen::Btiles — BTile validation/compilation and C emission for
## datagen (Task 6, Stage 2 extraction).  Moved verbatim from tools/datagen.pl;
## the only edits are the mechanical scaffold bindings: the shared globals are
## reached via their RAGE::Datagen::Context aliases (@main::all_btiles,
## %main::dataset_dependency, %main::btile_name_to_index,
## %main::conditional_build_features, @main::h_game_data_lines and the
## per-dataset C emit accumulator $main::c_dataset_lines), the sibling helper is
## imported (pixels_to_byte from Util), and the two callbacks that stay in
## datagen.pl — asset_backend() (shared with the Sprite emitter) and
## btile_deduplicate_arena_best() (loaded into main:: by RAGE::BTileUtils, which
## has no package declaration) — are called as main::asset_backend() and
## main::btile_deduplicate_arena_best().  Behaviour (and emitted bytes) is
## unchanged.
##
################################################################################

use strict;
use warnings;
use utf8;

# scaffold aliases (RAGE::Datagen::Context) populated at runtime by datagen.pl;
# silence the benign "used only once" check for these main:: globals.
no warnings 'once';

use RAGE::Datagen::Util qw( pixels_to_byte );

use Exporter 'import';
our @EXPORT_OK = qw( validate_and_compile_btile generate_btiles );

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

sub generate_btiles {
    my $dataset = shift;

    # generate the list of dataset btiles, return immediately if empty
    my @dataset_btiles = map { $main::all_btiles[ $_ ] } @{ $main::dataset_dependency{ $dataset }{'btiles'} };
    return if not scalar( @dataset_btiles );

    push @main::h_game_data_lines, <<EOF_TILES_H

////////////////////////////
// Big Tile definitions
////////////////////////////

EOF_TILES_H
;

    push @{ $main::c_dataset_lines->{ $dataset } }, <<EOF_TILES

////////////////////////////
// Big Tile definitions
////////////////////////////

EOF_TILES
;


    # generate the tiles

    my $animated_btiles = $main::conditional_build_features{'ANIMATED_BTILES'} || 0;

    my $gamearea_color_full = $main::conditional_build_features{'GAMEAREA_COLOR_FULL'} || 0;

    # All btiles carry inline pixel_bytes.  (R10 retired the CPC full-colour
    # extern path, where pixel bytes lived in a cpctelera-generated .c/.h.)
    my @inline_btiles = @dataset_btiles;

    # Task 5: the platform asset backend owns the per-cell byte format and size.
    # Recompute pixel_bytes here (generation time, when PLATFORM is fully known)
    # so the cell bytes are the platform's: ZX = 8-byte 1bpp (byte-identical to
    # the parse-time compile); CPC mode 1 = 16-byte mode-1 pixel-cells (CPCGfx).
    my $bpc = main::asset_backend()->bytes_per_cell();
    foreach my $tile ( @inline_btiles ) {
        $tile->{'pixel_bytes'} = main::asset_backend()->btile_cell_bytes( $tile );
    }

    # generate the offsets and byte arena for INLINE btiles only.  Cells are
    # $bpc bytes (8 on ZX, 16 on CPC mode 1).  The dedupe schema works on the
    # cell granularity it was built for (8-byte cells); for other cell sizes we
    # emit the arena without dedup (a CPC memory optimisation can revisit this).
    my @orig_cell_offsets;
    my @orig_byte_arena;
    foreach my $tile ( @inline_btiles ) {
        my $initial_offset = scalar( @orig_byte_arena );
        push @orig_byte_arena, map { @$_ } @{ $tile->{'pixel_bytes'} };
        my $offset = 0;
        while ( $offset < $bpc * scalar( @{ $tile->{'pixel_bytes'} } ) ) {
            push @orig_cell_offsets, $initial_offset + $offset;
            $offset += $bpc;
        }
    }

    # deduplication and arena output — only needed when there are inline tiles
    my @cell_offsets;
    if ( @inline_btiles ) {
        my ( $new_cell_offsets, $new_arena );
        if ( $bpc == 8 ) {
            # ZX: 8-byte-cell deduplication (byte-identical to historical output)
            ( $new_cell_offsets, $new_arena ) = main::btile_deduplicate_arena_best( \@orig_cell_offsets, \@orig_byte_arena );
        } else {
            # CPC (non-8-byte cells): no dedup — emit cells as-is
            $new_cell_offsets = \@orig_cell_offsets;
            $new_arena        = \@orig_byte_arena;
        }
        @cell_offsets = @$new_cell_offsets;
        my @byte_arena = @$new_arena;

        # generate the code for the arena (offsets will be used later)
        push @{ $main::c_dataset_lines->{ $dataset } }, "// Dataset BTILE byte arena\n";
        push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "uint8_t all_dataset_btile_data[ %d ] = {\n", scalar( @byte_arena ) );
        my @bytes = @byte_arena;	# splice (below) is destructive!
        while ( @bytes ) {		# output the arena in 16-byte chunks
            push @{ $main::c_dataset_lines->{ $dataset } }, "\t" . join('', map { sprintf( '0x%02x,', $_ ) } splice( @bytes, 0, 16 ) ) . "\n";
        }
        push @{ $main::c_dataset_lines->{ $dataset } }, "};\n";
    }

    # generate btile data structs (frame arrays, attr arrays, sequence arrays)
    # btiles always have 'frames' == 1, or the number of frames if specified
    my $cell_index = 0;
    foreach my $tile ( @dataset_btiles ) {

        push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "\n// Start of Big tile '%s'\n\n", $tile->{'name'} );

        # Inline BTile — frame tiles reference the shared arena.
        foreach my $frame ( 0 .. ( $tile->{'frames'} - 1 ) ) {
            my $num_cells = scalar( @{ $tile->{'pixel_bytes'} } ) / $tile->{'frames'};
            my @btile_cell_offsets = @cell_offsets[ $cell_index .. ( $cell_index + $num_cells - 1 ) ];
            push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "uint8_t *btile_%s_frame_%d_tiles[ %d ] = {\n\t%s\n};\n",
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
                push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "uint8_t btile_%s_frame_%d_attrs[ %d ] = {\n\t%s\n};\n",
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
                push @{ $main::c_dataset_lines->{ $dataset } },
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
                push @{ $main::c_dataset_lines->{ $dataset } },
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
                push @{ $main::c_dataset_lines->{ $dataset } },
                    sprintf( "uint8_t btile_%s_sequence_%s_frame_numbers[ %d ] = { %s };\n",
                        $tile->{'name'},
                        $seq->{'name'},
                        scalar( @{ $seq->{'frame_list'} } ),
                        join( ',', @{ $seq->{'frame_list'} } ),
                    );
            }

            # now the table of sequences itself
            if ( scalar( @{ $tile->{'sequences'} } ) ) {
                push @{ $main::c_dataset_lines->{ $dataset } },
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
            push @main::h_game_data_lines, sprintf( "#define BTILE_%s\t( &home_assets->all_btiles[ %d ] )\n",
                uc( $tile->{'name'} ),
                $main::dataset_dependency{ $dataset }{'btile_global_to_dataset_index'}{ $main::btile_name_to_index{ $tile->{'name'} } },
            );
            push @main::h_game_data_lines, sprintf( "#define BTILE_ID_%s\t%d\n",
                uc( $tile->{'name'} ),
                $main::dataset_dependency{ $dataset }{'btile_global_to_dataset_index'}{ $main::btile_name_to_index{ $tile->{'name'} } },
            );
        } else {
            push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "#define BTILE_%s\t( &home_assets->all_btiles[ %d ] )\n",
                uc( $tile->{'name'} ),
                $main::dataset_dependency{ $dataset }{'btile_global_to_dataset_index'}{ $main::btile_name_to_index{ $tile->{'name'} } },
            );
            push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "#define BTILE_ID_%s\t%d\n",
                uc( $tile->{'name'} ),
                $main::dataset_dependency{ $dataset }{'btile_global_to_dataset_index'}{ $main::btile_name_to_index{ $tile->{'name'} } },
            );
        }

        push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "\n// End of Big tile '%s'\n\n", $tile->{'name'} );
    }

    # generate the global btile table for this dataset

    # the btile_s structures differ when using (or not) ANIMATED_BTILES
    push @{ $main::c_dataset_lines->{ $dataset } }, "// Dataset BTile table\n";
    push @{ $main::c_dataset_lines->{ $dataset } }, sprintf( "struct btile_s all_btiles[ %d ] = {\n", scalar( @dataset_btiles ) );
    foreach my $tile ( @dataset_btiles ) {
        if ( $animated_btiles ) {
            push @{ $main::c_dataset_lines->{ $dataset } },
                sprintf( "\t{ .num_rows = %d, .num_cols = %d, ",
                    $tile->{'rows'},
                    $tile->{'cols'}
                );
            push @{ $main::c_dataset_lines->{ $dataset } },
                sprintf( ".num_frames = %d, .frames = &btile_%s_frames[0], ",
                    $tile->{'frames'},
                    $tile->{'name'}
                );
            push @{ $main::c_dataset_lines->{ $dataset } },
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
                push @{ $main::c_dataset_lines->{ $dataset } },
                    sprintf( "\t{ %d, %d, &btile_%s_frame_0_tiles[0], &btile_%s_frame_0_attrs[0] },\n",
                        $tile->{'rows'},
                        $tile->{'cols'},
                        $tile->{'name'},
                        $tile->{'name'} );
            } else {
                push @{ $main::c_dataset_lines->{ $dataset } },
                    sprintf( "\t{ %d, %d, &btile_%s_frame_0_tiles[0] },\n",
                        $tile->{'rows'},
                        $tile->{'cols'},
                        $tile->{'name'} );
            }
        }
    }
    push @{ $main::c_dataset_lines->{ $dataset } }, "};\n";
    push @{ $main::c_dataset_lines->{ $dataset } }, "// End of Dataset BTile table\n\n";


}

1;

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

use strict;
use warnings;
use utf8;

use File::Basename;

sub btile_get_png_tiledef_filename {
    my $png_file = shift;
    return dirname( $png_file ) . '/' . basename( $png_file, '.png', '.PNG' ) . '.tiledef';
}

# reads the associated .tiledef file for a given PNG file and returns the
# list of btiles defined in the file
# returns: listref of hashrefs - { name =>, row =>, col =>, width =>, height => , file => , num_cells => ...}
sub btile_read_png_tiledefs {
    my $png_file = shift;
    my @tiledefs;

    my $tiledef_file = btile_get_png_tiledef_filename( $png_file );

    open TILEDEF, $tiledef_file or
        die "Could not open $tiledef_file for reading\n";
    my $linecount = 0;
    while ( my $line = <TILEDEF> ) {
        $linecount++;
        chomp $line;
        $line =~ s/#.*$//g;		# remove comments
        next if $line =~ m/^$/;		# skip line if empty
        $line =~ s/\s+/ /g;		# replace multiple spaces with one

        # get fields - type and metadata may be empty
        my ( $name, $row, $col, $width, $height, $type, @metadata ) = split( /\s+/, $line );

        # setup the type of tile
        my $default_type = lc( $type || 'obstacle' );
        grep { $default_type } qw( obstacle item decoration crumb ) or
            die "$tiledef_file:$linecount: '$type' is not a valid BTILE type\n";

        # process the metadata
        my $metadata;
        foreach my $meta ( @metadata ) {
            if ( not ( $meta =~ /([\w\.]+)=(.*)/ ) ) {
                die "$tiledef_file:$linecount: metadata syntax error, both key and value are needed\n"
            }
            my ( $key, $value ) = ( $1, $2 );
            if ( $key =~ /^(\w+)\.(\w+)$/ ) {
                # key has "section.param" format, so save with an indirection level
                my ( $section, $param ) = ( $1, $2 );
                $metadata->{ $section }{ $param } = $value;
            } else {
                # key has plain format "param", so save the value directly
                $metadata->{ $key } = $value;
            }
        }

        # save the tiledef
        push @tiledefs, {
            name		=> $name,
            default_type	=> $default_type,
            cell_row		=> $row,
            cell_col		=> $col,
            cell_width		=> $width,
            cell_height		=> $height,
            pixel_pos_x		=> $col * 8,
            pixel_pos_y		=> $row * 8,
            pixel_width		=> $width * 8,
            pixel_height	=> $height * 8,
            tiledef_line	=> $line,
            png_file		=> $png_file,
            metadata		=> $metadata,
        };
    }
    close TILEDEF;
    return \@tiledefs;    
}

############################################################
##
## BTILE CELL-DATA DEDUPLICATION FUNCTIONS
##
############################################################
##
## See doc/BTILE-DATA-DEDUPE.md document for descriptions
## of the algorithms below
##
############################################################

# Utility functions

sub cell_hash {
    my $cell_bytes = shift;
    return join( '', map { sprintf( "%02x", $_ ) } @$cell_bytes );
}

sub lists_match {
    my ( $l1, $l2 ) = @_;
    my $l1_size = scalar( @$l1 );
    my $l2_size = scalar( @$l2 );

    return undef
        if ( $l1_size != $l2_size );

    foreach my $i ( 0 .. $l1_size - 1 ) {
        return undef
            if ( $l1->[ $i ] !=  $l2->[ $i ] );
    }

    return 1;
}

# returns the number of overlap bytes between the end of @$left and the
# beginning of @$right - @$left and @$right must both have 8 elements
sub max_length_match {
    my ( $left, $right ) = @_;
    if ( ( scalar( @$left ) != 8 ) or ( scalar( @$right ) != 8 ) ) {
        die "should have length 8!\n";
    }
    foreach my $i ( 0 .. 7 ) {
        if ( lists_match( [ @$left[ $i .. 7 ] ], [ @$right[ 0 .. ( 7 - $i ) ] ] ) ) {
            return ( 8 - $i );
        }
    }
    return 0;
}

# args:
#   offsets: listref of offsets into the uncompressed arena (normally multiples of 8)
#   arena: listref of cell byte data
# returns: a 2 element list (offsets, arena)
#   comp_offsets: listref of offsets into the compressed arena in the same order as the original ones
#   comp_arena: listref of deduplicated cell byte data
#
sub btile_deduplicate_arena_algo2 {
    my ( $offsets, $arena ) = @_;

    my @new_arena;
    my @new_offsets;

    # hash: byte_sequence => index_in_arena
    my %byte_sequence_pos;

    foreach my $offset ( @$offsets ) {
        my $cell_bytes = [ @$arena[ $offset .. ( $offset + 7 ) ] ];
        my $cell_hash = cell_hash( $cell_bytes );
        if ( not defined( $byte_sequence_pos{ $cell_hash } ) ) {
            my $cur_index = scalar( @new_arena );	# save current pointer

            # if we still have not emitted any bytes, just emit the full
            # cell and go to the next one
            if ( $cur_index == 0 ) {
                push @new_arena, @$cell_bytes;
                push @new_offsets, 0;
                $byte_sequence_pos{ $cell_hash } = 0;
                next;
            }

            # see if some bytes match the end of the arena
            my $max_length_match = max_length_match(
                [ @new_arena[ ( $cur_index - 8 ) .. ( $cur_index - 1 ) ] ],
                [ @$cell_bytes ]
            );

            # set pointer back as needed
            my $pre_index = $cur_index - $max_length_match;

            # save the current sequence ptr for later reuse
            $byte_sequence_pos{ $cell_hash } = $pre_index;

            # save cell data pointer
            push @new_offsets, $pre_index;

            # emit bytes to the arena
            if ( $max_length_match < 8 ) {
                push @new_arena, @$cell_bytes[ $max_length_match .. 7 ];
            } else {
                die "should never be greater than 8!\n";
            }

            # save all the new cell hashes that we have due to appending N
            # non-matched bytes to the arena
            if ( $cur_index >= 8 ) {
                foreach my $i ( ( $cur_index - 8 ) .. ( $cur_index - $max_length_match ) ) {
                    my $hash = cell_hash( [ @new_arena[ $i .. ( $i + 7 ) ] ] );
                    $byte_sequence_pos{ $hash } = $i;
                    }
            }
        } else {
            # if the cell has been seen, just use its pointer
            push @new_offsets, $byte_sequence_pos{ $cell_hash };
        }
    }

    return ( \@new_offsets, \@new_arena );
}

# Compresses an uncompressed arena into a deduplicated one (Algorithm 3)
#
# args:
#   offsets: listref of offsets into the uncompressed arena (normally multiples of 8)
#   arena: listref of cell byte data
#   initial_cell: index of the first cell to process
# returns: a 2 element list (offsets, arena)
#   comp_offsets: listref of offsets into the compressed arena in the same order as the original ones
#   comp_arena: listref of deduplicated cell byte data

sub btile_deduplicate_arena_algo3 {
    my ( $cell_offsets, $arena, $initial_cell ) = @_;

    # these are the two compressed data pieces that the function returns
    my @comp_offsets;
    my @comp_arena;

    # some convenient values
    my $num_cells = scalar( @$cell_offsets );

    # create 7 dictionaries for N leading bytes of each cell (N=1..7)
    #
    # $shared_prefix_offsets{ $n }{ $hash }: listref of indexes of all cells which share the first $n bytes
    #
    my %shared_prefix_offsets;
    foreach my $j ( 0 .. $num_cells - 1 ) {
        # associate the hash of the first N bytes to each cell
        # so that they can be easily located later
        foreach my $n ( 1 .. 7 ) {
            my $hash = cell_hash( [ @$arena[ $cell_offsets->[ $j ] .. ( $cell_offsets->[ $j ] + $n - 1 ) ] ] );
            push @{ $shared_prefix_offsets{ $n }{ $hash } }, $j;
        }
    }

    # create the compressed data areas (cells and arena)
    # applying the compression algorithm

    # hash: byte_sequence => index_in_arena
    # stores the position of emitted byte sequences in the compressed arena
    my %byte_sequence_pos_in_comp_arena;

    # keeps track of already emited cells to skip them when needed
    my %cell_already_emitted;

    # keeps track of the order in which the original cells are emitted.  We
    # need this for the final reordering of the offset list, so that offsets
    # in the original and compressed list correspond to the same cell (=byte
    # sequence)
    my %orig_to_comp_offsets;

    # do some initial preconditioning
    my $cells_remaining = $num_cells;
    my $cell_index = 0;

    # the initial cell is output as-is
    my $cell_bytes = [ @$arena[ $cell_offsets->[ $initial_cell ] .. $cell_offsets->[ $initial_cell ] + 7 ] ];
    my $cell_hash = cell_hash( $cell_bytes );
    push @comp_offsets, 0;			# initial cell offset at comp arena is 0
    push @comp_arena, @$cell_bytes;		# emit initial cell bytes to comp arena
    $orig_to_comp_offsets{ $initial_cell } = 0;	# initial cell is output at pos 0 in @comp_offsets
    $cell_already_emitted{ $initial_cell }++;	# do housekeeping
    $cells_remaining--;

    # now emit the rest of the cells
    # do the main deduplication loop
    while ( $cells_remaining ) {

        # reset variable used for the search
        my $index_of_cell_to_emit = undef;

        # first we try to match from the 7 indexes
        # starting by the longest match index and descending
        my $matched_length = 0;
        foreach my $prefix_length ( 7, 6, 5, 4, 3, 2, 1 ) {

            # extract the last N bytes from the arena and generate its hash for searching
            my @last_arena_bytes = @comp_arena[ -$prefix_length .. -1 ];
            my $last_arena_bytes_hash = cell_hash( \@last_arena_bytes );

            # if the prefix exists in the index, walk the list of cells that
            # share that prefix and select the first one that has not been
            # already emitted
            if ( defined( $shared_prefix_offsets{ $prefix_length }{ $last_arena_bytes_hash } ) ) {
                foreach my $cell ( @{ $shared_prefix_offsets{ $prefix_length }{ $last_arena_bytes_hash } } ) {
                    if ( not $cell_already_emitted{ $cell } ) {
                        $index_of_cell_to_emit = $cell;
                        $matched_length = $prefix_length;
                        last;	# found
                    }
                }
            }
            last if defined( $index_of_cell_to_emit );
        }

        # if we do not find any match in the indexes, we just emit the next
        # cell, so walk the general list skipping any cells that have been
        # already emitted
        if ( not defined( $index_of_cell_to_emit ) ) {
            while ( $cell_index < $num_cells ) {
                if ( $cell_already_emitted{ $cell_index } ) {
                    $cell_index++;
                } else {
                    $index_of_cell_to_emit = $cell_index++;
                    last;
                }
            }
        }

        # we should have already selected a cell to emit here, either an
        # overlapping one or a fresh one
        if ( not defined( $index_of_cell_to_emit ) ) {
            die "Should not happen!\n";
        }

        # now emit the bytes corresponding to the cell we selected in the
        # previous searches
        my $comp_cell_new_index = scalar( @comp_offsets );	# save for later
        if ( $matched_length == 0 ) {
            # if matched_length == 0, this means we selected a fresh cell
            # so emit it as-is - 8 bytes
            push @comp_offsets, scalar( @comp_arena );	# current arena offset where new bytes start
            push @comp_arena, @$arena[ $cell_offsets->[ $index_of_cell_to_emit ] .. ( $cell_offsets->[ $index_of_cell_to_emit ] + 7 ) ];
        } else {
            # if an overlapping one was selected, we must output only the
            # non-overlapping bytes - at most 7 bytes
            push @comp_offsets, ( scalar( @comp_arena ) - $matched_length );
            push @comp_arena, @$arena[ ( $cell_offsets->[ $index_of_cell_to_emit ] + $matched_length ) .. ( $cell_offsets->[ $index_of_cell_to_emit ] + 7 ) ];
        }

        # comp bytes emitted, do housekeeping
        $orig_to_comp_offsets{ $index_of_cell_to_emit } = $comp_cell_new_index;
        $cell_already_emitted{ $index_of_cell_to_emit }++;
        $cells_remaining--;

        # save all the new cell hashes that we have due to appending N
        # non-matched bytes to the arena
        my $num_new_sequences = 8 - $matched_length;
        my $last_arena_offset = scalar( @comp_arena ) - 1 ;
        foreach my $i ( 0 .. ( $num_new_sequences - 1 ) ) {
            my $pos = $last_arena_offset - $i - 7;
            my $seq = [ @comp_arena[ $pos .. ( $pos + 7 ) ] ];
            my $hash = cell_hash( $seq );
            $byte_sequence_pos_in_comp_arena{ $hash } = $pos;
        }
    }

    # return the compressed data
    # the compressed arena is returned as-is, but the compressed offset list
    # must be reordered to match the order of the original offset list
    return ( [ map { $comp_offsets[ $orig_to_comp_offsets{ $_ } ] } ( 0 .. $num_cells - 1 ) ], \@comp_arena );
}

# Compresses an uncompressed arena into a deduplicated one (Algorithm 4)
#
# args:
#   offsets: listref of offsets into the uncompressed arena (normally multiples of 8)
#   arena: listref of cell byte data
# returns: a 2 element list (offsets, arena)
#   comp_offsets: listref of offsets into the compressed arena in the same order as the original ones
#   comp_arena: listref of deduplicated cell byte data

sub btile_deduplicate_arena_algo4 {
    my ( $cell_offsets, $arena ) = @_;

    my $minimum_size = 999999999;
    my $minimum_initial_cell = undef;
    foreach my $initial_cell ( 0 .. scalar( @$cell_offsets ) - 1 ) {
        my ( $new_offsets, $new_arena ) = btile_deduplicate_arena_algo3( $cell_offsets, $arena, $initial_cell );
        if ( scalar( @$new_arena ) < $minimum_size ) {
            $minimum_size = scalar( @$new_arena );
            $minimum_initial_cell = $initial_cell;
        }
    }
    return btile_deduplicate_arena_algo3( $cell_offsets, $arena, $minimum_initial_cell );
}

# Compresses an uncompressed arena into a deduplicated one (Best algorithm)
#
# args:
#   offsets: listref of offsets into the uncompressed arena (normally multiples of 8)
#   arena: listref of cell byte data
# returns: a 2 element list (offsets, arena)
#   comp_offsets: listref of offsets into the compressed arena in the same order as the original ones
#   comp_arena: listref of deduplicated cell byte data
#
# Applies all known algorithms and returns the data from the one with best results

sub btile_deduplicate_arena_best {
    my ( $offsets, $arena ) = @_;

    my ( $algo2_offsets, $algo2_arena ) = btile_deduplicate_arena_algo2( $offsets, $arena );
    my ( $algo4_offsets, $algo4_arena ) = btile_deduplicate_arena_algo4( $offsets, $arena );

    if ( scalar( @$algo2_arena ) < scalar( @$algo4_arena ) ) {
        return btile_deduplicate_arena_algo2( $offsets, $arena );
    } else {
        return btile_deduplicate_arena_algo4( $offsets, $arena );
    }
}

1;

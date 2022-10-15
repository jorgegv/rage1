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

# Test 4: repeat Test 3 using each of the original tiles as the first one
# and pick the best results

use strict;
use warnings;
use utf8;

use File::Slurp;
use Data::Dumper;

my $debug = 0;

##
## Utility functions
##

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

sub hex_bytes {
    return join( ' ', map { sprintf( '%02x', $_ ) } @_ );
}

# main compression function
#
# compresses an uncompressed arena into a deduplicated one
# args:
#   offsets: listref of offsets into the uncompressed arena (normally multiples of 8)
#   arena: listref of cell byte data
#   initial_cell: index of the first cell to process
# returns: a 2 element list (offsets, arena)
#   comp_offsets: listref of offsets into the compressed arena in the same order as the original ones
#   comp_arena: listref of deduplicated cell byte data

sub deduplicate_arena {
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

    if ( $debug ) {
        print "** Dictionaries:\n", join( '', 
            map { sprintf( "  %d-byte prefix: %d entries\n", $_, scalar( keys %{ $shared_prefix_offsets{ $_ } } ) ) } (7,6,5,4,3,2,1) );
        foreach my $n ( 7,6,5,4,3,2,1 ) {
            print "** Prefix $n:\n";
            foreach my $p ( sort keys %{ $shared_prefix_offsets{ $n } } ) {
                printf "    %s:\n      ", $p;
                print join( "\n      ", map { sprintf( "[ %s ]", join( ',', map { sprintf( '%02x', $_ ) } @$arena[ $cell_offsets->[ $_ ] .. ( $cell_offsets->[ $_ ] + $n - 1 )  ]) ) } @{ $shared_prefix_offsets{ $n }{ $p } } );
                print "\n";
            }
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

        if ( $debug ) {
            print "-----------------------------------------------------------------------------\n";
            printf "Cells remaining: %d\n", $cells_remaining;
            printf "Comp Arena: %s\n", hex_bytes( @comp_arena );
        }

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
                        if ( $debug ) {
                            printf "Emitted cell %d with shared %d-byte prefix: %s\n",
                                $index_of_cell_to_emit,
                                $prefix_length,
                                hex_bytes( @$arena[ $cell_offsets->[ $index_of_cell_to_emit ] .. ( $cell_offsets->[ $index_of_cell_to_emit ] + 7 ) ] );
                        }
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
                    if ( $debug ) {
                        printf "Emitted cell %d with no shared prefix: %s\n",
                            $index_of_cell_to_emit, hex_bytes( @$arena[ $cell_offsets->[ $index_of_cell_to_emit ] .. ( $cell_offsets->[ $index_of_cell_to_emit ] + 7 ) ] );
                    }
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

##
## Main Program
##

my $all_state;
eval( read_file( 'internal_state.dmp' ) );

my @all_btiles = @{ $all_state->{'btiles'} };

my @orig_offsets;
my @orig_byte_arena;

my @all_cells;

# create the uncompressed (orig) data areas (cells and arena)
foreach my $btile ( @all_btiles ) {
    foreach my $cell_bytes ( @{ $btile->{'pixel_bytes'} } ) {
        # each cell is an 8-byte array
        my $cur_index = scalar( @orig_byte_arena );
        push @orig_offsets, $cur_index;		# pointer to cell bytes
        push @orig_byte_arena, @$cell_bytes;	# cell bytes
        push @all_cells, {
            orig_index		=> scalar( @all_cells ),
            bytes		=> $cell_bytes,
            btile		=> $btile->{'name'},
            arena_offset	=> $cur_index,
        };
    }
}

# run deduplication
foreach my $starting_cell ( 0 .. scalar( @orig_offsets ) - 1 ) {
    my ( $new_cell_offsets, $new_comp_arena ) = deduplicate_arena( \@orig_offsets, \@orig_byte_arena, $starting_cell );

    my @comp_offsets = @$new_cell_offsets;
    my @comp_byte_arena = @$new_comp_arena;

    # verification
    my @veri_byte_arena;
    foreach my $t ( @$new_cell_offsets ) {
        push @veri_byte_arena, @$new_comp_arena[ $t .. ( $t + 7 ) ];
    }

    # print stats
    printf "Original     : %d bytes (%d cells)\n", scalar( @orig_byte_arena ), scalar( @orig_offsets );
    printf "Compressed   : %d bytes (%d cells)\n", scalar( @comp_byte_arena ), scalar( @comp_offsets );
    printf "Reconstructed: %d bytes\n", scalar( @veri_byte_arena );
    printf "Original/Reconstructed compare: %s\n", ( lists_match( \@orig_byte_arena, \@veri_byte_arena ) ? 'MATCH' : 'NO MATCH' );
    printf "Dedupe/Original compression ratio: %-4.1f%%\n", 100 * scalar( @comp_byte_arena ) / scalar( @orig_byte_arena );
    printf "Starting cell: %d\n", $starting_cell;
}

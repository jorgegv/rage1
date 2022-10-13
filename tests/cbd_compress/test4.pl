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

# main compression function
#
# compresses an uncompressed arena into a deduplicated one
# args:
#   offsets: listref of offsets into the uncompressed arena (normally multiples of 8)
#   arena: listref of cell byte data
#   initial_cell: index of the first cell to process
# returns: a 2 element list (offsets, arena)
#   offsets: listref of offsets into the compressed arena in the same order as the original ones
#   arena: listref of deduplicated cell byte data

sub deduplicate_arena {
    my ( $offsets, $arena, $initial_cell ) = @_;

    my @comp_cells;
    my @comp_byte_arena;

    # create 7 dictionaries for N leading bytes of each cell
    #
    # $start_seq_cells{ $n }{ $hash }: listref of indexes of all cells which share the first $n bytes
    #
    my %start_seq_cells;
    foreach my $j ( 0 .. scalar( @$offsets ) - 1 ) {
        # associate the hash of the first N bytes to each cell
        # so that they can be easily located later
        foreach my $i ( 1 .. 7 ) {
            my $hash = cell_hash( [ @$arena[ $offsets->[ $j ] .. ( $offsets->[ $j ] + $i - 1 ) ] ] );
            push @{ $start_seq_cells{ $i }{ $hash } }, $j;
        }
    }

    # create the compressed data areas (cells and arena)
    # applying the compression algorithm

    # hash: byte_sequence => index_in_arena
    my %byte_sequence_pos;

    # to skip cells already emited if necessary
    my %cell_already_emitted;

    # to keep track of the order in which the cells are emitted
    my %orig_to_comp_cells;

    # some preconditioning
    my $cells_remaining = scalar( @$offsets );
    my $num_cells = scalar( @$offsets );

    my $cell_index = 0;

    # initial iteration
    # the initial cell is output as-is
    my $cell_bytes = [ @$arena[ $offsets->[ $initial_cell ] .. $offsets->[ $initial_cell ] + 7 ] ];
    my $cell_hash = cell_hash( $cell_bytes );

    push @comp_cells, 0;			# initial cell offset at comp arena is 0
    push @comp_byte_arena, @$cell_bytes;	# emit initial cell bytes to comp arena
    $orig_to_comp_cells{ $initial_cell } = 0;	# initial cell is output at pos 0

    # do housekeeping
    $cell_already_emitted{ $initial_cell }++;
    $cells_remaining--;

    # now emit the rest of the cells
    while ( $cells_remaining ) {

        my $index_of_cell_to_emit = undef;

        # first we try to match from the 7 indexes
        # starting by the longest match index and descending
        my $matched_length = 0;
        foreach my $match_len ( 7, 6, 5, 4, 3, 2, 1 ) {
            my @last_arena_bytes = @comp_byte_arena[ -$match_len .. -1 ];
            my $last_arena_bytes_hash = cell_hash( \@last_arena_bytes );
            if ( defined( $start_seq_cells{ $match_len }{ $last_arena_bytes_hash } ) ) {
                foreach my $c ( @{ $start_seq_cells{ $match_len }{ $last_arena_bytes_hash } } ) {
                    if ( not $cell_already_emitted{ $c } ) {
                        $index_of_cell_to_emit = $c;
                        $matched_length = $match_len;
                        last;	# found
                    }
                }
            }
            last if defined( $index_of_cell_to_emit );
        }

        # if we do not find any match in the indexes, we just emit the next
        # cell, so walk the general list skipping any that have been emitted
        # already
        if ( not defined( $index_of_cell_to_emit ) ) {
            while ( $cell_index < ( $num_cells - 1 ) ) {
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

        my $comp_cell_current_index = scalar( @comp_cells );
        if ( $matched_length == 0 ) {
            # if matched_length == 0, this means we selected a fresh cell
            # so emit it as-is
            push @comp_cells, scalar( @comp_byte_arena );	# current index
            push @comp_byte_arena, @$arena[ $offsets->[ $index_of_cell_to_emit ] .. ( $offsets->[ $index_of_cell_to_emit ] + 7 ) ];
        } else {
            # if an overlapping one was selected, we must output only the
            # non-overlapping bytes - at most 7 bytes
            push @comp_cells, ( scalar( @comp_byte_arena ) - $matched_length );
            push @comp_byte_arena, @$arena[ ( $offsets->[ $index_of_cell_to_emit ] + $matched_length ) .. ( $offsets->[ $index_of_cell_to_emit ] + 7 ) ];
        }

        # cell bytes emitted, do housekeeping
        $orig_to_comp_cells{ $index_of_cell_to_emit } = $comp_cell_current_index;
        $cell_already_emitted{ $index_of_cell_to_emit }++;
        $cells_remaining--;

        # save all the new cell hashes that we have due to appending N
        # non-matched bytes to the arena
        my $num_new_sequences = 8 - $matched_length;
        my $last_arena_index = scalar( @comp_byte_arena ) - 1 ;
        foreach my $i ( 0 .. ( $num_new_sequences - 1 ) ) {
            my $pos = $last_arena_index - $i - 7;
            my $seq = [ @comp_byte_arena[ $pos .. ( $pos + 7 ) ] ];
            my $hash = cell_hash( $seq );
            $byte_sequence_pos{ $hash } = $pos;
        }
    }

    return ( [ map { $comp_cells[ $orig_to_comp_cells{ $_ } ] } ( 0 .. $num_cells - 1 ) ], \@comp_byte_arena );
}

##
## Main Program
##

my $all_state;
eval( read_file( 'internal_state.dmp' ) );

my @all_btiles = @{ $all_state->{'btiles'} };

my @orig_cells;
my @orig_byte_arena;

my @all_cells;

# create the uncompressed (orig) data areas (cells and arena)
foreach my $btile ( @all_btiles ) {
    foreach my $cell_bytes ( @{ $btile->{'pixel_bytes'} } ) {
        # each cell is an 8-byte array
        my $cur_index = scalar( @orig_byte_arena );
        push @orig_cells, $cur_index;		# pointer to cell bytes
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
my $starting_cell = 0;
my ( $new_cell_offsets, $new_comp_arena ) = deduplicate_arena( \@orig_cells, \@orig_byte_arena, $starting_cell );
my @comp_cells = @$new_cell_offsets;
my @comp_byte_arena = @$new_comp_arena;

# verification
my @veri_byte_arena;
foreach my $t ( @$new_cell_offsets ) {
    push @veri_byte_arena, @$new_comp_arena[ $t .. ( $t + 7 ) ];
}

# print stats
printf "Original     : %d bytes (%d cells)\n", scalar( @orig_byte_arena ), scalar( @orig_cells );
printf "Compressed   : %d bytes (%d cells)\n", scalar( @comp_byte_arena ), scalar( @comp_cells );
printf "Reconstructed: %d bytes\n", scalar( @veri_byte_arena );
printf "Original/Reconstructed compare: %s\n", ( lists_match( \@orig_byte_arena, \@veri_byte_arena ) ? 'MATCH' : 'NO MATCH' );
printf "Dedupe/Original compression ratio: %-4.1f%%\n", 100 * scalar( @comp_byte_arena ) / scalar( @orig_byte_arena );

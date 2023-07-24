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

# Test 2: identify 8-byte sequences, and try to output less than 8 bytes by
# matching at the end of the arena.  Perhaps the full 8-byte sequence is not
# present, but e.g.  the first 6 bytes are present and at the end of the
# arena, and so only 2 bytes need to be emitted

use strict;
use warnings;
use utf8;

use File::Slurp;
use Data::Dumper;

# create the compressed data areas (btiles and arena)
# applying the compression algorithm


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

# returns the number of overlap bytes between the end of @$arena and the
# beginning of @$new - @$arena and @$new must both have 8 elements
sub max_length_match {
    my ( $arena, $new ) = @_;
    if ( ( scalar( @$arena ) != 8 ) or ( scalar( @$new ) != 8 ) ) {
        die "should have length 8!\n";
    }
    foreach my $i ( 0 .. 7 ) {
        if ( lists_match( [ @$arena[ $i .. 7 ] ], [ @$new[ 0 .. ( 7 - $i ) ] ] ) ) {
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
# returns: a 2 element list (offsets, arena)
#   comp_offsets: listref of offsets into the compressed arena in the same order as the original ones
#   comp_arena: listref of deduplicated cell byte data

sub deduplicate_arena {
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

##
## Main program
##

my $all_state;
eval( read_file( 'internal_state.dmp' ) );

my @all_btiles = @{ $all_state->{'btiles'} };

my @orig_cells;
my @orig_byte_arena;

# create the uncompressed (orig) data areas (btiles and arena)
foreach my $btile ( @all_btiles ) {
    foreach my $cell_bytes ( @{ $btile->{'pixel_bytes'} } ) {
        # each cell is an 8-byte array
        my $cur_index = scalar( @orig_byte_arena );
        push @orig_cells, $cur_index;		# pointer to cell bytes
        push @orig_byte_arena, @$cell_bytes;	# cell bytes
    }
}

my ( $new_offsets, $new_arena ) = deduplicate_arena( \@orig_cells, \@orig_byte_arena );
my @comp_cells = @$new_offsets;
my @comp_byte_arena = @$new_arena;

# verification
my @veri_byte_arena;
foreach my $t ( @comp_cells ) {
    push @veri_byte_arena, @comp_byte_arena[ $t .. ( $t + 7 ) ];
}

# print stats
printf "Original     : %d bytes (%d cells)\n", scalar( @orig_byte_arena ), scalar( @orig_cells );
printf "Compressed   : %d bytes (%d cells)\n", scalar( @comp_byte_arena ), scalar( @comp_cells );
printf "Reconstructed: %d bytes\n", scalar( @veri_byte_arena );
printf "Original/Reconstructed compare: %s\n", ( lists_match( \@orig_byte_arena, \@veri_byte_arena ) ? 'MATCH' : 'NO MATCH' );
printf "Dedupe/Original compression ratio: %-4.1f%%\n", 100 * scalar( @comp_byte_arena ) / scalar( @orig_byte_arena );

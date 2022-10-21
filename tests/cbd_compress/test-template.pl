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

# Test N: description

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
# returns: a 2 element list (offsets, arena)
#   comp_offsets: listref of offsets into the compressed arena in the same order as the original ones
#   comp_arena: listref of deduplicated cell byte data

sub deduplicate_arena {
    my ( $cell_offsets, $arena ) = @_;

    # algorithm here...

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
my ( $new_cell_offsets, $new_comp_arena ) = deduplicate_arena( \@orig_offsets, \@orig_byte_arena );

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

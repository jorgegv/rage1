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

# Test 1: only identify only 8-byte sequences

use strict;
use warnings;
use utf8;

use File::Slurp;
use Data::Dumper;

my $all_state;
eval( read_file( 'internal_state.dmp' ) );

my @all_btiles = @{ $all_state->{'btiles'} };

my @orig_cells;
my @orig_byte_arena;

my @comp_cells;
my @comp_byte_arena;
# create the uncompressed (orig) data areas (btiles and arena)
foreach my $btile ( @all_btiles ) {
    foreach my $cell_bytes ( @{ $btile->{'pixel_bytes'} } ) {
        # each cell is an 8-byte array
        my $cur_index = scalar( @orig_byte_arena );
        push @orig_cells, $cur_index;		# pointer to cell bytes
        push @orig_byte_arena, @$cell_bytes;	# cell bytes
    }
}

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

# hash byte_sequence => index_in_arena
my %byte_sequence;

foreach my $btile ( @all_btiles ) {
    foreach my $cell_bytes ( @{ $btile->{'pixel_bytes'} } ) {
        my $cell_hash = cell_hash( $cell_bytes );
        if ( defined( $byte_sequence{ $cell_hash } ) ) {
            push @comp_cells, $byte_sequence{ $cell_hash };
        } else {
            my $cur_index = scalar( @comp_byte_arena );	# save current pointer
            push @comp_cells, $cur_index;		# save cell and data
            push @comp_byte_arena, @$cell_bytes;
            $byte_sequence{ $cell_hash } = $cur_index;	# save the current sequence ptr for later reuse
        }
    }
}

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

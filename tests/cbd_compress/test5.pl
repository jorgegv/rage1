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

# Test 5: deduplicate using Kigsaw algorithm (see doc/BTILE-DATA-DEDUPE.md)

use strict;
use warnings;
use utf8;

use File::Slurp;
use Data::Dumper;

my $debug_index		= 0;
my $debug_search	= 0;
my $debug_sequences	= 0;
my $debug_matches	= 0;

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

# returns a list of the common elements to two list(refs)
# we assume no elements are repeated inside each list
sub common_elements {
    my ( $list_a, $list_b ) = @_;
    my %seen;
    foreach my $element ( @$list_a, @$list_b ) { $seen{ $element }++; }
    return ( grep { $seen{ $_ } == 2 } keys %seen );
}

sub hex_bytes {
    return join( ' ', map { sprintf( '%02x', $_ ) } @_ );
}

sub list_max {
    my @sorted = sort { $b <=> $a } @_;
    return $sorted[ 0 ];
}

sub min {
    my ( $a, $b ) = @_;
    return ( $a > $b ? $b : $a );
}

sub dump_list_of_sequences {
    my $sequences = shift;
    foreach my $seq ( @$sequences ) {
        printf "  [ %s ]\n", hex_bytes( @$seq );
    }
}

# returns the sequence composed by overlapping the last $n elements of
# $list_a over the first $n of $list_b
sub overlapped_sequences {
    my ( $list_a, $list_b, $overlap ) = @_;
    return ( @$list_a, @$list_b[ $overlap .. scalar( @$list_b ) - 1 ] );
}

# Jigsaw: stage 1
sub jigsaw_dedupe {
    my $sequences = shift;

    # maximum length found in the provided sequences
    my $max_length = list_max( map { scalar( @$_ ) } @$sequences );
    if ( $debug_sequences ) {
        printf "max_length: %d\n", $max_length;
        printf "sequences: %d\n", scalar( @$sequences );
        dump_list_of_sequences( $sequences );
    }

    #############################
    # first prepare the indexes
    #############################
    my %prefix_cells;
    my %suffix_cells;

    foreach my $length ( reverse ( 1 .. $max_length ) ) {
        if ( $debug_index ) {
            printf "building indexes, length = %d bytes\n", $length;
        }
        my $seq_index = 0;
        foreach my $seq ( @$sequences ) {
            # only add the sequence to the relevant indexes
            if ( scalar( @$seq ) >= $length ) {
                # add the sequence to the prefix index
                push @{ $prefix_cells{ $length }{ cell_hash( [ @$seq[ 0 .. ( $length - 1 ) ] ] ) } }, $seq_index;
                # add the sequence to the suffix index
                push @{ $suffix_cells{ $length }{ cell_hash( [ @$seq[ ( scalar( @$seq ) - $length ) .. ( scalar( @$seq ) - 1 ) ] ] ) } }, $seq_index;
            }
            # index for next sequence
            $seq_index++;
        }
    }
    # debug: output the indexes
    if ( $debug_index ) {
        print "Prefix indexes:\n";
        foreach my $length ( sort { $b <=> $a } keys %prefix_cells ) {
            printf "  %d-byte:\n", $length;
            foreach my $prefix ( sort keys %{ $prefix_cells{ $length } } ) {
                printf "    %s: [ %s ]\n", $prefix, join( ',', @{ $prefix_cells{ $length }{ $prefix } } );
            }
        }
        print "Suffix indexes:\n";
        foreach my $length ( sort { $b <=> $a } keys %suffix_cells ) {
            printf "  %d-byte:\n", $length;
            foreach my $suffix ( sort keys %{ $suffix_cells{ $length } } ) {
                printf "    %s: [ %s ]\n", $suffix, join( ',', @{ $suffix_cells{ $length }{ $suffix } } );
            }
        }
    }

    #############################################
    # start the search by the longest sequences
    #############################################
    my @new_sequences;
    my %matched_sequences;

    foreach my $length ( reverse ( 1 .. $max_length ) ) {
        if ( defined( $prefix_cells{ $length } ) and defined( $suffix_cells{ $length } ) ) {
            my %seen;
            foreach my $element ( keys %{ $prefix_cells{ $length } }, keys %{ $suffix_cells{ $length } } ) { 
                $seen{ $element }++;
            }
            my @common_sequences =  grep { $seen{ $_ } == 2 } keys %seen;
            if ( $debug_search ) {
                print "common_sequences: ";
                print Dumper( \@common_sequences );
            }

            # just match among the common sequences
            foreach my $common_seq ( @common_sequences ) {

                # get the first non-matched element from the list of
                # elements that have the current suffix
                my $seq_a_index;
                do {
                    $seq_a_index = pop @{ $suffix_cells{ $length }{ $common_seq } };
                } while ( defined( $seq_a_index ) and $matched_sequences{ $seq_a_index } );

                # if not defined, we have finished with this common sequence, skip to next
                next if not defined( $seq_a_index );

                # mark as matched
                $matched_sequences{ $seq_a_index }++;

                # get the first non-matched element from the list of
                # elements that have the current prefix
                my $seq_b_index;
                do {
                    $seq_b_index = pop @{ $prefix_cells{ $length }{ $common_seq } };
                } while ( defined( $seq_b_index ) and $matched_sequences{ $seq_b_index } );

                # if not defined, we have finished with this common_sequence, skip to next
                if ( not defined( $seq_b_index ) ) {
                    # undo matching of seq_a, if here it was defined
                    $matched_sequences{ $seq_a_index }--;
                    next;
                }

                # mark as matched
                $matched_sequences{ $seq_b_index }++;

                # build the new sequence as the overlapping of the previous ones
                my $new_seq = [ overlapped_sequences( 
                        $sequences->[ $seq_a_index ],
                        $sequences->[ $seq_b_index ],
                        $length 
                    ) ];
                if ( $debug_matches ) {
                    printf "match (%d bytes): [ %s ] + [ %s ] -> [ %s ]\n",
                        $length,
                        hex_bytes( @{ $sequences->[ $seq_a_index ] } ),
                        hex_bytes( @{ $sequences->[ $seq_b_index ] } ),
                        hex_bytes( @$new_seq );
                }

                # save it and mark the component sequenes as matched
                push @new_sequences, $new_seq;
            }
        }
    }

    ##############################################################
    # add the non-matched sequences to the list of new sequences
    ##############################################################
    push @new_sequences, map { $sequences->[ $_ ] }
        grep { not defined( $matched_sequences{ $_ } ) or not $matched_sequences{ $_ } }
        ( 0 .. scalar( @$sequences ) - 1 );

    # return the new sequence list
    return \@new_sequences;
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

    # first, prepare all the initial 8-byte sequences
    # @sequences is a list of listrefs
    my @sequences = map { [ @$arena[ $_ .. $_ + 7 ] ] } @$cell_offsets;

    # apply algorithm until no changes (stage 2)
    my $new_sequences = \@sequences;
    my $old_num_seqs = 0;
    while ( $old_num_seqs != scalar( @$new_sequences ) ) {
        $old_num_seqs = scalar( @$new_sequences );
        $new_sequences = jigsaw_dedupe( $new_sequences );
    }

    # stage 3: create the new arena and pointer list

    # $new_sequences is a listref of listrefs, so just deference the listref
    # and emit its elements straight away
    my @comp_arena;
    push @comp_arena, map { @$_ } @$new_sequences;

    # now create the 8-byte sequence index
    my %sequence_index;
    foreach my $index ( 0 .. scalar( @comp_arena ) - 8 ) {
        my $cell_hash = cell_hash( [ @comp_arena[ $index .. $index + 7 ] ] );
        $sequence_index{ $cell_hash } = $index;
    }

    # now remap the original offset list into the new one
    my @comp_offsets;
    push @comp_offsets, map { $sequence_index{ cell_hash( $_ ) } } @sequences;

    # return values
    return ( \@comp_offsets, \@comp_arena );
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

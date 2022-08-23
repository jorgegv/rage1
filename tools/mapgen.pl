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

use FindBin;
use lib "$FindBin::Bin/../lib";

require RAGE::PNGFileUtils;
require RAGE::BTileUtils;

use Data::Dumper;
use File::Basename;
use Getopt::Std;

# arguments: 2 or more PNG files, plus some required switches (screen
# dimensions an output directory)

our( $opt_w, $opt_h, $opt_o );
getopts('w:h:o:');
( defined( $opt_w ) and
    defined( $opt_h ) and
    defined( $opt_o ) and
    ( scalar( @ARGV ) >= 2 )
    ) or
    die "usage: " . basename( $0 ) . " -w <screen_cols> -h <screen_rows> -o <out_dir> <map_png> <btile_png> [<btile_png>]...\n";

# collect arguments
my ($screen_cols, $screen_rows, $output_dir ) = ( $opt_w, $opt_h, $opt_o );
my @png_files = @ARGV;	# remaining args after option processing

# Stages:

# 1.  Process the list of PNG files and classify them as BTILE or MAP
# images.
#
# PNGs for which a corresponding TILEDEF file exists will be considered as
# containing BTILES.  A PNG that does not have a matching TILEDEF file will
# be considered the main map.  There can be only one PNG without TILEDEF
# file.

my @btile_files;
my @map_files;
foreach my $f ( @png_files ) {
    my $tiledef_file = dirname( $f ) . '/' . basename( $f, '.png', '.PNG' ) . '.tiledef';
    if ( -e $tiledef_file ) {
        push @btile_files, $f;
    } else {
        push @map_files, $f;
    }
}
if ( scalar( @map_files ) > 1 ) {
    print STDERR "Error: all PNG files except the main map must have associated .tiledef files\n";
    printf STDERR "Files with no associated .tiledef:\n   %s", join( "\n   ", @map_files );
    die "\n";
}
my $map_png_file = $map_files[0];	# first and only element

# 2. Process the list of BTILE files:
#   - Process the TILEDEF file
#   - Get all cell data for each BTILE
#   - Add this to a global list of BTILEs
#   - Associate the hash of the top-left cell with its BTILE index into
#     the BTILE list.  There may be more than one BTILE with the same
#     top-left cell, so this should be handled with a listref
#   - The hash of the cell is the 'hexdump' field, which is just the
#     concatenation of the 8 bytes plus the attr byte, all in hex form

my @all_btiles;		# list of all found btiles
my %btile_index;	# map of cell->hexdump => btile index

# process all PNG Btile files
foreach my $png_file ( @btile_files ) {

    # get all the tiledefs for the file
    my $tiledefs = btile_read_png_tiledefs( $png_file );

    # load the PNG and convert it to the ZX Spectrum color palette
    my $png = load_png_file( $png_file );
    map_png_colors_to_zx_colors( $png );

    # process the PNG's cells and extract the btiles
    foreach my $tiledef ( @$tiledefs ) {

        # get all cell data for the btile
        my $btile_data = png_get_all_cell_data(
            $png,
            $tiledef->{'cell_row'},
            $tiledef->{'cell_col'},
            $tiledef->{'cell_width'},
            $tiledef->{'cell_height'}
        );

        # save the current index in the main btile list
        my $current_btile_index = scalar( @all_btiles );

        # store the btile cell data into the main btile list
        push @all_btiles, $btile_data;

        # ...and update the index
        push @{ $btile_index{ $btile_data->[0][0]{'hexdump'} } }, $current_btile_index;
    }
}

# At this point, we have a global list of BTILEs ( @all_btiles ) and a index
# of hashes for the top-left cell of each one of them ( %btile_index ), so
# that we can quickly search for all the tiles that have that cell

# Since there may be more than one BTILE with the same top-left cell, we now
# sort the lists associated to the cell hashes, in descending size order
# (number of cells).  We are interested in finding first the biggest BTILEs
# when searching.  Most of the time the lists will have only one element,
# but we need to account for all cases.

sub btile_cell_size {
    my $btile_data = shift;
    return scalar( @$btile_data ) * scalar( @{ $btile_data->[0] } );
}

foreach my $hash ( keys %btile_index ) {
    my @sorted = sort { btile_cell_size( $all_btiles[ $a ] ) <=> $all_btiles[ $b ]} @{ $btile_index{ $hash } };
    $btile_index{ $hash } = \@sorted;
}

# 3. Process the main map image:
#   - Get the full list of cell data for it

# load the PNG and convert it to the ZX Spectrum color palette
my $png = load_png_file( $map_png_file );
map_png_colors_to_zx_colors( $png );

# Make sure the map PNG has valid dimensions
my $map_height = scalar( @$png );
my $map_width = scalar( @{ $png->[0] } );
if ( ( $map_width % 8 ) or ( $map_height % 8 ) ) {
    die "Dimensions of PNG map file $map_png_file (${map_width}x${map_height} pixels) are not a multiple of 8\n";
}

# Make sure that an integer number of screens can fit in the PNG map file
my $map_rows = $map_height / 8;
if ( ( $map_rows % $screen_rows ) ) {
    die "Cell rows of PNG map file $map_png_file ($map_rows) must be a multiple of screen height ($screen_rows rows)\n";
}

my $map_cols = $map_width / 8;
if ( ( $map_cols % $screen_cols ) ) {
    die "Cell columns of PNG map file $map_png_file ($map_cols) must be a multiple of screen width ($screen_cols columns)\n";
}

# load cell data from PNG
my $main_map_cell_data = png_get_all_cell_data( $png );

# At this point we also have the cell data for the main map.  Now we only
# need to walk the main map cells trying to match them with the BTILEs we
# know

# 4. Walk the main map cells (MxN size) for each map screen (RxC size):
#   - Check it the status is not "matched" (it may habe been marked as such
#     by previous identified BTILEs). Skip if it is already "matched"
#   - Calculate the hash for the map cell
#   - Search for the hash in the BTILE index (it should exist, error if
#     it doesn't)
#   - If there is only one match, it means that there is only one tile with
#     that cell, so verify that the remaining cells also match, and mark the
#     status for that cells as "matched" in the status array
#   - If there is more than one match, we should verify all the BTILEs,
#     starting by the bigger ones.  Hopefully one of them will match.  We
#     will stop the search and mark the relevant cell status as "matched" in
#     the status array
#   - When we have fully identified the BTILE, we save the name, position
#     and current screen number in the global BTILE instances list
#
# Repeat this process for all map screens
#
# R and C have been passed as parameters, they are in vars $screen_rows and
# $screen_cols
#
# M and N are the global map dimensions, they are in vars $map_rows and
# $map_cols
#
# Screens are arranged in a rectangular map of ( M/R x N/C ) screens.  We
# will walk the screens in left-right,top-bottom order, and also in the same
# order the cells inside each screen.  The row and column indexes for the
# current screen will be held in vars $screen_row and $screen_col

# returns true if a given btile matches the cells in the map at position
# (row,col).  Btile must be completely inside the map, if it is partially
# outside, it will return false
sub match_btile_in_map {
    my ( $map, $btile_data, $test_row, $test_col ) = @_;
    foreach my $r ( 0 .. ( @$btile_data - 1 ) ) {
        foreach my $c ( 0 .. ( @{ $btile_data->[0] } - 1 ) ) {

            # return undef if out of the map
            return undef if ( ( $test_row + $r ) >= $map_rows );
            return undef if ( ( $test_col + $c ) >= $map_cols );

            # return undef as soon as there is a cell mismatch
            return undef if ( $map->[ $test_row + $r ][ $test_col + $c ]{'hexdump'} ne
                $btile_data->[ $r ][ $c ]{'hexdump'} );
        }
    }

    # all btile cells matched the cells on the map, so return true
    return 1;
}

# This var will hold the checked cells.  We do not want to re-check the
# cells corresponding to a matched btile.  At the end of matching, this
# bidimensional array should have the same size as the main map (in cells),
# and all values should be defined and >=1
my $checked_cells;

# this list will hold the matched btiles, with all associated metadata
my @matched_btiles;

# walk the screen array
foreach my $screen_row ( 0 .. ( $map_rows / $screen_rows - 1 ) ) {
    foreach my $screen_col ( 0 .. ( $map_cols / $screen_cols - 1 ) ) {

        # walk the cell array on each screen
        foreach my $cell_row ( 0 .. ( $screen_rows - 1 ) ) {
            foreach my $cell_col ( 0 .. ( $screen_cols - 1 ) ) {

                my $global_cell_row = $screen_row * $screen_rows + $cell_row;
                my $global_cell_col = $screen_col * $screen_cols + $cell_col;

                # skip if the cell has already been checked by a previously
                # matched btile
                next if $checked_cells->[ $global_cell_row ][ $global_cell_col ];

                # ...otherwise mark the cell as checked and continue
                $checked_cells->[ $global_cell_row ][ $global_cell_col ]++;

                # get the hash of the top-left cell
                my $top_left_cell_hash = $main_map_cell_data->[ $global_cell_row ][ $global_cell_col ];

                # if there are one or more btiles with that cell hash as its
                # top-left, try to match all btiles from the list.
                if ( defined( $btile_index{ $top_left_cell_hash } ) ) {

                    #  The list is ordered from bigger to smaller btile, so
                    # the biggest btile will be matched first.  First match
                    # wins
                    foreach my $btile_index ( @{ $btile_index{ $top_left_cell_hash } } ) {
                        my $btile_data = $all_btiles[ $btile_index ];
                        my $btile_rows = scalar( @$btile_data );
                        my $btile_cols = scalar( @{ $btile_data->[0] } );
                        if ( match_btile_in_map( $main_map_cell_data, $btile_data, $global_cell_row, $global_cell_col ) ) {

                            # if a match was found, add it to the list of matched btiles
                            push @matched_btiles, {
                                screen_row	=> $screen_row,
                                screen_col	=> $screen_col,
                                cell_row	=> $cell_row,
                                cell_col	=> $cell_col,
                                global_cell_row	=> $global_cell_row,
                                global_cell_col	=> $global_cell_col,
                                btile_index	=> $btile_index,
                            };

                            # we also mark all of its cells as checked
                            foreach my $r ( 0 .. ( ) ) {
                                foreach my $c ( 0 .. ( ) ) {
                                    $checked_cells->[ $global_cell_row + $r ][ $global_cell_col + $c ]++;
                                }
                            } # end of mark-as-checked

                            # whenever we find a match, skip the rest of btiles
                            last;
                        }

                    } # end of btile-list-walk-for-matches

                } # end of some-matches-found
 
            }
        } # end of cell-walk inside a screen

    }
} # end of screen-walk

# At this point, we have:
#   - A list of matched BTILEs, with its associated metadata:  screen
#     [row,col in the screen map], position of btile inside/relative to the
#     screen [row,col], global position [row,col] inside the main map, and
#     the BTILE index inside the @all_btiles global list
#   - A bidimensional array of cell status, with the same dimensions as the
#     cell data for the main map

# 5.  Check thet all cells in the status map are in state "checked".  This
# means that the whole map has been compiled successfully

my @non_checked_cells;
foreach my $r ( 0 .. ( ) ) {
    foreach my $c ( 0 .. ( ) ) {
        if ( not $checked_cells->[ $r ][ $c ] ) {
            push @non_checked_cells, "  Cell ($r,$c) was not checked";
        }
    }
}
if ( scalar( @non_checked_cells ) ) {
    die "Error: The following main map cells were not checked for BTILEs:" .
        join( "\n", @non_checked_cells ) . "\n";
}

# 6.  Walk the screen list and create the associated GDATA file for tat
# screen with all its associated data:
#   - BTILE definitions
#   - HOTZONE definitions
#   - ITEM definitions

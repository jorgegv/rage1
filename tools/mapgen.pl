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

use Data::Dumper;
use File::Basename;
use Getopt::Std;

# arguments: 2 or more PNG files, plus some required switches (screen
# dimensions an output directory)

our( $opt_w, $opt_h, $opt_o );
getopts('w:h:o:');
( defined( $opt_w ) and defined( $opt_h ) and defined( $opt_o ) ) or
    die "usage: " . basename( $0 ) . " -w <screen_width> -h <screen_height> -o <output_dir> <map_png_file> <btile_png_file_1> [<btile_png_file_2>]...\n";

# collect arguments
my ($screen_width, $screen_height, $output_dir ) = ( $opt_w, $opt_h, $opt_o );
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
    my $tiledef_file = dirname( $f ) . '/' . basename( $f ) . '.tiledef';
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

    # process the PNG's cells and extract the btile
    my $png = load_png_file( $png_file );
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
        my $btile_index = scalar( @all_btiles );

        # store the btile cell data into the main btile list
        push @all_btiles, $btile_data;

        # ...and update the index
        push @{ $btile_index->{ $btile_data->[0][0]{'hexdump'} } }, $btile_index;
    }
}

# At this point, we have a global list of BTILEs ( @all_btiles ) and a index
# of hashes for the top-left cell of each one of them ( %btile_index ), so
# that we can quickly search for all the tiles that have that cell

# 3. Process the main map image:
#   - Get the full list of cell data for it

my $png = load_png_file( $map_png_file );
my $main_map_cell_data = png_get_all_cell_data( $png );

# At this point we also have a the cell data for the main data.  Now we only
# need to walk the main map cells trying to match them with the BTILEs we
# know

# TBC

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

# At this point, we should have:
#   - A list of screens, each with a list of BTILE instances.  Each BTILE
#     instance has an associated name and position (r,c)
#   - A list of cell status, with the same dimensions as the cell data for
#     the main map

# 5.  Check thet all cells in the status map are in state "matched".  This
# means that the whole map has been compiled successfully

# 6.  Walk the screen list and create the associated GDATA file for tat
# screen with all its associated data:
#   - BTILE definitions
#   - HOTZONE definitions
#   - ITEM definitions

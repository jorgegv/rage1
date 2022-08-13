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

my $png_file = $ARGV[0];

defined( $png_file ) or
    die "usage: $0 <png_file>\n";

my $png = load_png_file( $png_file );
my $cells = png_get_all_cell_data( $png, 1, 1, 3, 2 );
print Dumper( $cells );

# arguments: 2 or more PNG files, plus some required switches (e.g.  for
# setting the screen dimensions)

# PNGs for which a corresponding TILEDEF file exists will be considered as
# containing BTILES

# A PNG that does not have a matching TILEDEF file will be considered the
# main map

# There can be only one PNG without TILEDEF file

# Stages:

# 1. Process the list of PNG files and classify them as BTILE or MAP images

# 2. Process the list of BTILE files:
#   - Process the TILEDEF file
#   - Get all cell data for each BTILE
#   - Add this to a global list of BTILEs
#   - Calculate the hash of the top-left cell hash and associate it with the
#     BTILE number.  There may be more than one BTILE with the same top-left
#     cell, so this should be handled with a listref
#   - The hash can be as simple as concatenating the 8 bytes plus the attr
#     byte, all in hex form

# At this point, we have a list of BTILEs and a dictionary of hashes for the
# top-left cell of each one of them, so that we can quickly search for all
# the tiles that have that cell

# 3. Process the main map image:
#   - Get the full list of cell data for it

# At this point we also have a the cell data for the main data.  Now we only
# need to walk the main map cells trying to match them with the BTILEs we
# know

# 4. Walk the main map cells (MxN size) for each map screen (RxC size):
#   - Check it the status is not "matched" (it may habe been marked as such
#     by previous identified BTILEs). Skip if it is already "matched"
#   - Calculate the hash for the map cell
#   - Search for the hash in the BTILE dictionary (it should exist, error if
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

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
use File::Basename qw( basename );
use Getopt::Long;
use GD;

# arguments: 2 or more PNG files, plus some required switches (screen
# dimensions, output directory, etc.)

# variables for CLI arguments
my ( $screen_cols, $screen_rows );
my ( $game_data_dir, $game_area_top, $game_area_left );
my ( $hero_sprite_width, $hero_sprite_height );
my $hotzone_color = '00FF00';
my $auto_hotzones;
my $auto_hotzone_bgcolor = '000000';
my $auto_hotzone_width = 8;
my $generate_check_map;
my $auto_tileset_btiles;
my $auto_tileset_max_rows = 16;
my $auto_tileset_max_cols = 16;

# global variables
my %map_crumb_types;

# parse CLI options
(
    GetOptions(
        "screen-cols=i"			=> \$screen_cols,
        "screen-rows=i"			=> \$screen_rows,
        "game-data-dir=s"		=> \$game_data_dir,
        "game-area-top=i"		=> \$game_area_top,
        "game-area-left=i"		=> \$game_area_left,
        "auto-hotzones"			=> \$auto_hotzones,		# optional, default false
        "hotzone-color:s"		=> \$hotzone_color,		# optional, default '00FF00'
        "auto-hotzone-bgcolor:s"	=> \$auto_hotzone_bgcolor,	# optional, default '000000'
        "auto-hotzone-width:i"		=> \$auto_hotzone_width,	# optional, default 4
        "generate-check-map"		=> \$generate_check_map,	# optional, default false
        "hero-sprite-width=i"		=> \$hero_sprite_width,
        "hero-sprite-height=i"		=> \$hero_sprite_height,
        "auto-tileset-btiles"		=> \$auto_tileset_btiles,	# optional, default false
        "auto-tileset-max-rows:i"	=> \$auto_tileset_max_rows,	# optional, default 16
        "auto-tileset-max-cols:i"	=> \$auto_tileset_max_cols,	# optional, default 16
    )
    and ( scalar( @ARGV ) >= 2 )
    and defined( $screen_cols )
    and defined( $screen_rows )
    and defined( $game_data_dir )
    and defined( $game_area_top )
    and defined( $game_area_left )
    and defined( $hero_sprite_width )
    and defined( $hero_sprite_height )
) or die "usage: " . basename( $0 ) . " <options> <map_png> <btile_png> [<btile_png>]...\n" . <<EOF_HELP

Where <options> can be the following:

Required:

    --screen-cols <cols>		Width of each screen, in 8x8 cells [1-32]
    --screen-rows <rows>		Height of each screen, in 8x8 cells [1-24]
    --game-data-dir <dir>		game_data directory where Map and Flow GDATA files will be generated
    --game-area-top <row>		Top row of the Game Area [0-23]
    --game-area-left <col>		Left column of the Game Area [0-31]
    --hero-sprite-width <n>		Width of the Hero sprite, in pixels [>0]
    --hero-sprite-height <n>		Height of the Hero sprite, in pixels [>0]

Optional:

    --auto-hotzones			Enable HOTZONE autodetection between adjacent screens
    --auto-hotzone-bgcolor		When --auto-hotzones is enabled, specifies background color
    --auto-hotzone-width		When --auto-hotzones is enabled, specifies HOTZONE width in pixels (default: 4)
    --hotzone-color			When --auto-hotzones is disabled, specifies HOTZONE color to match (default: 000000)
    --generate-check-map		Generates a check-map with outlines for the matched objects (PNG)
    --auto-tileset-btiles		Automatically creates BTILE definitions for all possible BTILEs in tilesets
    --auto-tileset-max-rows		Maximum rows for automatically created BTILE definitions (default: 16)
    --auto-tileset-max-cols		Maximum cols for automatically created BTILE definitions (default: 16)

Colors are specified as RRGGBB (RGB components in hex notation)

EOF_HELP
;

##########################
## 0. Validate args
##########################

( ( $screen_cols >= 1 ) and ( $screen_cols <= 32 ) ) or
    die "--screen-cols must be in 1-32 range\n";
( ( $screen_rows >= 1 ) and ( $screen_rows <= 24 ) ) or
    die "--screen-rows must be in 1-24 range\n";
( ( $game_area_top >= 0 ) and ( $game_area_top <= 23 ) ) or
    die "--game-area-top must be in 0-23 range\n";
( ( $game_area_left >= 0 ) and ( $game_area_left <= 31 ) ) or
    die "--game-area-left must be in 0-31 range\n";
( $hero_sprite_width > 0 ) or
    die "--hero-sprite-width must be greater than 0\n";
( $hero_sprite_height > 0 ) or
    die "--hero-sprite-height must be greater than 0\n";

# continue

my @png_files = @ARGV;	# remaining args after option processing

# screen dimensions in pixels
my $screen_width = $screen_cols * 8;
my $screen_height = $screen_rows * 8;

# Stages:

###########################################################################
###########################################################################
##
## 1.  Process the list of PNG files specified on the command line and
## classify them as BTILE or MAP images.
##
###########################################################################
###########################################################################

# PNGs for which a corresponding TILEDEF file exists will be considered as
# containing BTILES.  A PNG that does not have a matching TILEDEF file will
# be considered the main map.  There can be only one PNG without TILEDEF
# file.  The map file can have an optional MAPDEF file with screen metadata.

print "Checking input files...\n";

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
    print STDERR "** Error: all PNG files except the main map must have associated .tiledef files\n";
    printf STDERR "** Files with no associated .tiledef:\n   %s", join( "\n   ", @map_files );
    die "\n";
}
my $map_png_file = $map_files[0];	# first and only element

print  "-- Map PNG: $map_png_file\n";
printf "-- BTile PNG: $_\n" for ( @btile_files );

###########################################################################
###########################################################################
##
## 2. Process the list of BTILE files and create the structs
##
###########################################################################
###########################################################################

print "Loading BTILEs...\n";

# Steps:
#   - Process the TILEDEF file
#   - Get all cell data for each BTILE
#   - Add this to a global list of BTILEs
#   - Associate the hash of the top-left cell with its BTILE index into
#     the BTILE list.  There may be more than one BTILE with the same
#     top-left cell, so this should be handled with a listref
#   - The hash of the cell is the 'hexdump' field, which is just the
#     concatenation of the 8 bytes plus the attr byte, all in hex form

my @all_btiles;			# list of all found btiles
my %btile_index;		# map of cell->hexdump => btile index

sub is_background_btile {
    my $btile_data = shift;
    foreach my $rows ( @$btile_data ) {
        foreach my $val ( @$rows ) {
            # return immediately when we find something non-bg
            return undef
                # background is 8 zero bytes (ignore the 9th, it's the attribute)
                if ( $val->{'hexdump'} !~ '^0000000000000000' );
        }
    }
    # everything was bg, return true
    return 1;
}

# generates the
sub generate_btiles {
    my ( $png, $tiledefs, $png_file, $prefix ) = @_;

    my $file_prefix = basename( $png_file, '.png', '.PNG' ) . $prefix;

    my @generated_btiles;
    foreach my $tiledef ( @$tiledefs ) {

        # get all cell data for the btile
        my $btile_data = png_get_all_cell_data(
            $png,
            $tiledef->{'cell_row'},
            $tiledef->{'cell_col'},
            $tiledef->{'cell_width'},
            $tiledef->{'cell_height'}
        );

        # prepare btile cell data struct
        my $btile = {
            name		=> $file_prefix . '_' . $tiledef->{'name'},
            default_type	=> $tiledef->{'default_type'},
            metadata		=> $tiledef->{'metadata'},
            cell_row		=> $tiledef->{'cell_row'},
            cell_col		=> $tiledef->{'cell_col'},
            cell_width		=> $tiledef->{'cell_width'},
            cell_height		=> $tiledef->{'cell_height'},
            cell_data		=> $btile_data,
            png_file		=> $png_file,
        };

        # store the btile cell data into the main btile list and update the index
        push @generated_btiles, $btile;

        # if automatic generation of btiles in tilesets has been requested,
        # create the list of all possible subtiles of all sizes (up to the
        # current btile size), except those that are full background
        if ( $auto_tileset_btiles ) {
            my $height = $tiledef->{'cell_height'};
            my $width = $tiledef->{'cell_width'};
            foreach my $cur_height ( 1 .. $height ) {
                foreach my $cur_width ( 1 .. $width ) {
                    foreach my $cur_row ( $tiledef->{'cell_row'} .. ( $tiledef->{'cell_row'} + $height - $cur_height ) ) {
                        foreach my $cur_col ( $tiledef->{'cell_col'} .. ( $tiledef->{'cell_col'} + $width - $cur_width ) ) {
                            my $btile_name = sprintf("%s_r%03dc%03dw%03dh%03d",$file_prefix,$cur_row,$cur_col,$cur_width,$cur_height);
                            my $btile_data = png_get_all_cell_data( $png, $cur_row, $cur_col, $cur_width, $cur_height );
                            if ( not is_background_btile( $btile_data ) ) {
                                my $btile = {
                                    name		=> $btile_name,
                                    default_type	=> $tiledef->{'default_type'},,
                                    metadata		=> $tiledef->{'metadata'},,
                                    cell_row		=> $cur_row,
                                    cell_col		=> $cur_col,
                                    cell_width		=> $cur_width,
                                    cell_height		=> $cur_height,
                                    cell_data		=> $btile_data,
                                    png_file		=> $png_file,
                                };
                                push @generated_btiles, $btile;
                            }
                        }
                    }
                }
            }
        }
    }
    return @generated_btiles;
}

# process all PNG Btile files
foreach my $png_file ( @btile_files ) {

    # load the PNG and convert it to the ZX Spectrum color palette
    my $png = load_png_file( $png_file ) or
        die "** Error: could not load PNG file $png_file\n";
    map_png_colors_to_zx_colors( $png );

    my $prefix = '';

    # get all the tiledefs for the file
    my $tiledefs = btile_read_png_tiledefs( $png_file );

    # process the PNG's cells and extract the btiles
    my $tile_count = 0;
    foreach my $btile ( generate_btiles( $png, $tiledefs, $png_file, $prefix ) ) {
        my $current_btile_index = scalar( @all_btiles );	# pos of new list element
        push @all_btiles, $btile;
        push @{ $btile_index{ $btile->{'cell_data'}[0][0]{'hexdump'} } }, $current_btile_index;
        $tile_count++;
    }
    printf "-- File %s: read %d BTILEs\n", $png_file, $tile_count;
}

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
    my @sorted = sort {
        btile_cell_size( $all_btiles[ $b ]{'cell_data'} )
        <=>
        btile_cell_size( $all_btiles[ $a ]{'cell_data'} ) 
    } @{ $btile_index{ $hash } };
    $btile_index{ $hash } = \@sorted;
}

# At this point, we have a global list of BTILEs ( @all_btiles ) and a index
# of hashes for the top-left cell of each one of them ( %btile_index ), so
# that we can quickly search for all the tiles that have that cell

###########################################################################
###########################################################################
##
## 3. Process the main map image to get cell data
##
###########################################################################
###########################################################################

print "Processing Main Map...\n";

# Steps:
#   - Get the full list of cell data for it
#   - Process the MAPDEF file if it exists and get the screen metadata

# load the PNG and convert it to the ZX Spectrum color palette
my $main_map_png = load_png_file( $map_png_file ) or
    die "** Error: could not load PNG file $map_png_file\n";

map_png_colors_to_zx_colors( $main_map_png );

# Make sure the map PNG has valid dimensions
my $map_height = scalar( @$main_map_png );
my $map_width = scalar( @{ $main_map_png->[0] } );
if ( ( $map_width % 8 ) or ( $map_height % 8 ) ) {
    die "** Error: dimensions of PNG map file $map_png_file (${map_width}x${map_height} pixels) are not a multiple of 8\n";
}

# Make sure that an integer number of screens can fit in the PNG map file
my $map_rows = $map_height / 8;
if ( ( $map_rows % $screen_rows ) ) {
    die "** Error: cell rows of PNG map file $map_png_file ($map_rows) must be a multiple of screen height ($screen_rows rows)\n";
}

my $map_cols = $map_width / 8;
if ( ( $map_cols % $screen_cols ) ) {
    die "** Error: cell columns of PNG map file $map_png_file ($map_cols) must be a multiple of screen width ($screen_cols columns)\n";
}

printf "-- Loaded Main Map: %dx%d pixels, %d rows x %d columns (8x8 cells)\n",
    $map_width, $map_height, $map_rows, $map_cols;

# precalculate the size of the map, in vertical and horizontal screens
my $map_screen_rows = $map_rows / $screen_rows;
my $map_screen_cols = $map_cols / $screen_cols;

printf "-- Main Map has %d rows of %d screens each\n",
    $map_screen_rows, $map_screen_cols;

# load cell data from PNG
my $main_map_cell_data = png_get_all_cell_data( $main_map_png );

# this variable holds the screen metadata from the MAPDEF file. Initially undef for all screens.
my $screen_metadata;
push @$screen_metadata, [ (undef) x $map_screen_cols ]
    for ( 0 .. ( $map_screen_rows - 1 ) );

# load screen metadata from MAPDEF file if it exists
my $mapdef_file = dirname( $map_png_file ) . '/' . basename( $map_png_file, '.png', '.PNG' ) . '.mapdef';
if ( -e $mapdef_file ) {
    open MAPDEF, $mapdef_file or
        die "** Error: could not open MAPDEF file $mapdef_file for reading\n";

    while ( my $line = <MAPDEF> ) {
        chomp( $line );
        $line =~ s/#.*$//g;		# remove comments
        next if ( $line =~ /^$/ );	# skip blank lines

        # The first two fields are the screen row and column numbers in the
        # main map.  The metadata is the rest of the fields, which are in
        # the form key=value, space separated
        my ( $map_screen_row, $map_screen_col, @rest ) = split( /\s+/, $line );

        # bound checking
        if ( $map_screen_row >= $map_screen_rows ) {
            die sprintf( "** Error: screen(%d,%d): row %d is outside of the map (max allowed: %d)\n", 
                $map_screen_row, $map_screen_col, $map_screen_row, $map_screen_rows - 1 );
        }
        if ( $map_screen_col >= $map_screen_cols ) {
            die sprintf( "** Error: screen(%d,%d): column %d is outside of the map (max allowed: %d)\n", 
                $map_screen_row, $map_screen_col, $map_screen_col, $map_screen_cols - 1 );
        }

        # process and save screen metadata at the proper position
        foreach my $meta ( @rest ) {
            my ( $key, $value ) = split( /=/, $meta );	# split into key=value
            $key = lc( $key );				# canonicalize key

            $value =~ s/_/ /g
                if ( $key eq 'title' );			# replace _ with ' ' in titles

            # add the metadata
            # account for hero.startup_xpos type keys
            if ( $key =~ /^(.+)\.(.+)$/ ) {
                $screen_metadata->[ $map_screen_row ][ $map_screen_col ]{ $1 }{ $2 } = $value;
            } else {
                $screen_metadata->[ $map_screen_row ][ $map_screen_col ]{ $key } = $value;
            }
        }
    }

    close MAPDEF;
}

print "-- Screen metadata loaded from MAPDEF file\n";

# At this point we also have the cell data and optional screen metadata for
# the main map.  Now we only need to walk the main map cells trying to match
# them with the BTILEs we know

###########################################################################
###########################################################################
##
## 4. Identify BTILEs on all screens
##
###########################################################################
###########################################################################

# Steps:
#
# Walk the main map cells (MxN size) for each map screen (RxC size):
#
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

# This var will hold the checked and matched cells.  We do not want to
# re-check the cells corresponding to an already matched btile.  At the end
# of matching, this bidimensional array should have the same size as the
# main map (in cells), and all values should be defined and == 1
my $checked_cells;
my $matched_cells;

# this list will hold the matched btiles, with all associated metadata
my @matched_btiles;

# returns true if a given btile matches the cells in the map at position
# (row,col), restricted to a given screen.  Btile must be completely inside
# the screen, if it is partially outside, it will return false
sub match_btile_in_map {
    my ( $map, $screen_top, $screen_left, $screen_bottom, $screen_right, $btile_data, $pos_row, $pos_col ) = @_;

    # return undef if out of the screen
    return undef if ( $pos_row < $screen_top );
    return undef if ( $pos_col < $screen_left );

    foreach my $btile_row ( 0 .. ( scalar( @$btile_data ) - 1 ) ) {
        foreach my $btile_col ( 0 .. ( scalar( @{ $btile_data->[0] } ) - 1 ) ) {

            my $screen_row = $pos_row + $btile_row;
            my $screen_col = $pos_col + $btile_col;

            # return undef if out of the screen
            return undef if ( $screen_row > $screen_bottom );
            return undef if ( $screen_col > $screen_right );

            # return undef if the cell has already been matched by a
            # previous btile
            return undef if $matched_cells->[ $screen_row ][ $screen_col ];

            # return undef as soon as there is a cell mismatch
            return undef if ( $map->[ $screen_row ][ $screen_col ]{'hexdump'} ne
                $btile_data->[ $btile_row ][ $btile_col ]{'hexdump'} );
        }
    }

    # all btile cells matched the cells on the map, so return true
    return 1;
}

print "Identifying BTILEs in Main Map...\n";

# walk the screen array
foreach my $screen_row ( 0 .. ( $map_screen_rows - 1 ) ) {
    foreach my $screen_col ( 0 .. ( $map_screen_cols - 1 ) ) {

        # temporary values
        my $global_screen_top = $screen_row * $screen_rows;
        my $global_screen_left = $screen_col * $screen_cols;
        my $global_screen_bottom = $global_screen_top + $screen_rows - 1;
        my $global_screen_right = $global_screen_left + $screen_cols - 1;

        my $btile_count = 0;

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
                my $top_left_cell_hash = $main_map_cell_data->[ $global_cell_row ][ $global_cell_col ]{'hexdump'};

                # skip if it is a background tile
                next if ( $top_left_cell_hash eq '000000000000000000' );

                # if there are one or more btiles with that cell hash as its
                # top-left, try to match all btiles from the list.
                if ( defined( $btile_index{ $top_left_cell_hash } ) ) {

                    #  The list is ordered from bigger to smaller btile, so
                    # the biggest btile will be matched first.  First match
                    # wins
                    foreach my $btile_index ( @{ $btile_index{ $top_left_cell_hash } } ) {
                        my $btile_data = $all_btiles[ $btile_index ]{'cell_data'};
                        my $btile_rows = scalar( @$btile_data );
                        my $btile_cols = scalar( @{ $btile_data->[0] } );
                        if ( match_btile_in_map( $main_map_cell_data,
                            $global_screen_top, $global_screen_left, $global_screen_bottom, $global_screen_right,
                            $btile_data,
                            $global_cell_row, $global_cell_col ) ) {

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

                            # mark it as used in the global BTILE list
                            $all_btiles[ $btile_index ]{'used_in_screen'}++;

                            # we also mark all of its cells as checked and matched
                            foreach my $r ( 0 .. ( $btile_rows - 1 ) ) {
                                foreach my $c ( 0 .. ( $btile_cols - 1 ) ) {
                                    $checked_cells->[ $global_cell_row + $r ][ $global_cell_col + $c ]++;
                                    $matched_cells->[ $global_cell_row + $r ][ $global_cell_col + $c ]++;
                                }
                            } # end of mark-as-checked-and-matched

                            # take note if the detected btile is a crumb
                            if ( $all_btiles[ $btile_index ]{'default_type'} eq 'crumb' ) {
                                $map_crumb_types{ $all_btiles[ $btile_index ]{'metadata'}{'type'} } = {
                                    btile_name	=> $all_btiles[ $btile_index ]{'name'},
                                };
                            }

                            # whenever we find a match, skip the rest of btiles
                            $btile_count++;
                            last;
                        }

                    } # end of btile-list-walk-for-matches

                } # end of some-matches-found
 
            }
        } # end of cell-walk inside a screen
        printf "-- Screen (%d,%d): matched %d BTILEs\n",
            $screen_row, $screen_col, $btile_count;
    }
} # end of screen-walk

# At this point, we have:
#   - A list of matched BTILEs, with its associated metadata:  screen
#     [row,col in the screen map], position of btile inside/relative to the
#     screen [row,col], global position [row,col] inside the main map, and
#     the BTILE index inside the @all_btiles global list
#   - A bidimensional array of cell status, with the same dimensions as the
#     cell data for the main map

# Check thet all cells in the status map are in state "checked".  This means
# that the whole map has been compiled successfully
my @non_checked_cells;
foreach my $r ( 0 .. ( $map_rows - 1 ) ) {
    foreach my $c ( 0 .. ( $map_cols - 1 ) ) {
        if ( not $checked_cells->[ $r ][ $c ] ) {
            push @non_checked_cells, "  Cell ($r,$c) was not checked";
        }
    }
}
if ( scalar( @non_checked_cells ) ) {
    die "** Error: The following main map cells were not checked for BTILEs:" .
        join( "\n", @non_checked_cells ) . "\n";
}

###########################################################################
###########################################################################
##
## 5. Identify HOTZONEs in the main map PNG file
##
###########################################################################
###########################################################################

# Requirements:
#
# - A predefined color is selected as the HOTZONE marker with a command line
#   argument (RRGGBB format, default 00FF00)
#
# - HOTZONEs are marked on the main map as solid rectangles of the
#   predefined color
#
# - They must have minimum dimensions (8x8 pixels)
#
# - They must not be greater than maximum dimensions (1 screen wide/high)
#
# - If a HOTZONE is completely contained inside a given screen, it is
#   defined as is and no Flow rules are generated, they should be manually
#   written
#
# - If a HOTZONE overlaps two adjacent screens, it is split into two
#   different HOTZONEs, one for each screen, and Flow rules are generated
#   for automatic screen switching

# Minimum and maximum dimensions for HOTZONEs
my $hotzone_min_height = 4;
my $hotzone_max_height = $screen_rows * 8;	# screen height, in pixels
my $hotzone_min_width = 4;
my $hotzone_max_width = $screen_cols * 8;	# screen width, in pixels

# match_rectangle_in_map (auxiliary function): tries to match a solid
# rectangle of a given color in a PNG map, starting from a specific origin.
# Additional image limits are passed to ensure that the matched rectangle
# fits inside a given zone of the image
#
# match_origin can be 0 (top-left), 1 (top-right), 2 (bottom-left), or 3
# (bottom-right)
sub match_rectangle_in_map {
    my ( $map, $match_color, $match_origin, $pos_x, $pos_y, $min_x, $min_y, $max_x, $max_y ) = @_;

    # extra-fast return for the general case of non-matching pixel
    return undef
        if ( $map->[ $pos_y ][ $pos_x ] ne $match_color );

    # if the first pixel matches, then take the slow path and start matching
    
    # setup proper increments for the generic algorithm according to the origin
    my ( $dx, $dy );
    if ( $match_origin == 0 ) {
        ( $dx, $dy ) = ( 1, 1 );
    } elsif ( $match_origin == 1 ) {
        ( $dx, $dy ) = ( -1, 1 );
    } elsif ( $match_origin == 2 ) {
        ( $dx, $dy ) = ( 1, -1 );
    } elsif ( $match_origin == 3 ) {
        ( $dx, $dy ) = ( -1, -1 );
    } else {
        die "** Error: match_origin: invalid value\n";
    }

    # loop variables
    my ( $new_pos_x, $new_pos_y );

    # external loop (y): matches vertically stacked horizontal lines
    $new_pos_y = $pos_y;
    my $matched_height = 0;
    my $matched_width = 0;
    while ( ( $new_pos_y >= $min_y ) and ( $new_pos_y <= $max_y ) and
            ( $matched_height < $hotzone_max_height ) ) {

        # internal loop (x): matches pixels horizontally for a line
        $new_pos_x = $pos_x;
        my $matched_x = 0;
        while ( ( $new_pos_x >= $min_x ) and ( $new_pos_x <= $max_x ) and 
                ( $matched_x < $hotzone_max_width ) and
                ( $map->[ $new_pos_y ][ $new_pos_x ] eq $match_color ) ) {
            $new_pos_x += $dx;
            $matched_x++;
        }

        # if we did not match a full line, stop matching lines
        last if ( ( $matched_height > 0 ) and not $matched_x );

        # if a match was found but was not wide enough, stop matching lines
        last if ( $matched_x < $hotzone_min_width );

        # if the matched width is less than the previous lines that have
        # already been matched, we can use the new smaller width
        if ( $matched_width and ( $matched_x < $matched_width ) ) {
            $matched_width = $matched_x;
        }

        # save first matched width
        if ( not $matched_width ) {
            $matched_width = $matched_x;
        }

        $new_pos_y += $dy;
        $matched_height++;
    }
    # finished matching lines

    # get final coords
    my $max_pos_x = $pos_x + $dx * ( $matched_width - 1 );
    my $max_pos_y = $pos_y + $dy * ( $matched_height - 1 );

    # match not high enough, return undef
    return undef
        if ( $matched_height < $hotzone_min_height );

    # at this point we have indentified a rectangle with the specified color
    # sort min and max x and y values and return
    return {
        x_min	=> ( $max_pos_x > $pos_x ? $pos_x     : $max_pos_x ),
        x_max	=> ( $max_pos_x > $pos_x ? $max_pos_x : $pos_x     ),
        y_min	=> ( $max_pos_y > $pos_y ? $pos_y     : $max_pos_y ),
        y_max	=> ( $max_pos_y > $pos_y ? $max_pos_y : $pos_y     ),
        width	=> $matched_width,
        height	=> $matched_height,
    };
}

# This var will hold the checked pixels.  We do not want to re-check the
# pixels corresponding to an already matched hotzone.  At the end of
# matching, this bidimensional array should have the same size as the main
# map (in pixels), and all values should be defined and == 1
my $checked_pixels;

# this will contain the list of matched hotzones
my @matched_hotzones;

# Try to automatically create HOTZONEs if requested
# (The regular ones will be matched later)
if ( $auto_hotzones ) {

    # Requirements:
    #
    # - A background color can be specified with a command line argument
    #   (RRGGBB format, default 000000 - black)
    #
    # - A width for the hotzones can be specified with a command line argument
    #   (integer, default 8 pixels)
    #
    # Steps:
    #
    # - Walk the screen list checking vertical right borders:
    #
    #   - Match rectangles of background color starting at
    #     x=right_border-auto_hotzone_width, y=top_border+auto_hotzone_width,
    #     origin top-left (match to the right-down)
    #
    #   - Match rectangles in the same way, starting at
    #     x=right_border+auto_hotzone_width, same y as before, origin top-right
    #     (match to the left-down)
    #
    # - Walk the screen list checking horizontal bottom borders:
    #
    #   - Match rectangles of background color starting at x=left_border+auto_hotzone_width,
    #     y=bottom_border-auto_hotzone_width, origin top-left (match to the right-down)
    #
    #   - Match rectangles in the same way, starting at same x as before,
    #     y=bottom_border+auto_hotzone_width, origin bottom-left (match to the
    #     right-up)


    print "Adding automatic HOTZONEs...\n";

    # walk the list of screens - TESTS PENDING!
    foreach my $map_screen_row ( 0 .. ( $map_screen_rows - 1 ) ) {
        foreach my $map_screen_col ( 0 .. ( $map_screen_cols - 1 ) ) {

            # if we are not on the last column of screens in the map, locate
            # vertical hotzones on the right border

            # scan vertical border
            if ( $map_screen_col < ( $map_screen_cols - 1 ) ) {
                # scan left-to-right
                my $x_min = $map_screen_col * $screen_cols * 8 + $screen_width - $auto_hotzone_width;
                my $x_max = $x_min + 2 * $auto_hotzone_width - 1;
                my $y_min = $map_screen_row * $screen_rows * 8 + $auto_hotzone_width;
                my $y_max = $map_screen_row * $screen_rows * 8 + $screen_height - $auto_hotzone_width - 1;
                foreach my $pos_y ( $y_min .. $y_max ) {

                    #########################
                    # match left-to-right
                    #########################
                    
                    # skip pixel if already checked by a previously matched hotzone
                    if ( not $checked_pixels->[ $x_min ][ $pos_y ] ) {

                        # mark pixel as checked
                        $checked_pixels->[ $x_min ][ $pos_y ]++;

                        # try to match a rectangle
                        my $match = match_rectangle_in_map( $main_map_png, $auto_hotzone_bgcolor,
                            0,		# match-origin: top-left
                            $x_min, $pos_y,
                            $x_min, $y_min, $x_max, $y_max
                        );

                        # quickly return if no match
                        next if not defined $match;

                        # additionally, the minimum width or height for an auto
                        # hotzone is 2 * auto_hotzone_width - it must overlap 2
                        # screens, and we start matching at (border -
                        # auto_hotzone_width)
                        next if ( ( $match->{'x_max'} - $match->{'x_min'} + 1 < 2 * $auto_hotzone_width ) or
                                ( $match->{'y_max'} - $match->{'y_min'} + 1 < 2 * $auto_hotzone_width ) );

                        # a valid match was found, mark its pixels as checked
                        foreach my $x ( $match->{'x_min'} .. $match->{'x_max'} ) {
                            foreach my $y ( $match->{'y_min'} .. $match->{'y_max'} ) {
                                $checked_pixels->[ $x ][ $y ]++;
                            }
                        }

                        # ...then save the matched hotzone
                        push @matched_hotzones, $match;
                    }

                    #########################
                    # match right-to-left
                    #########################
                    
                    # skip pixel if already checked by a previously matched hotzone
                    if ( not $checked_pixels->[ $x_max ][ $pos_y ] ) {

                        # mark pixel as checked
                        $checked_pixels->[ $x_max ][ $pos_y ]++;

                        # try to match a rectangle
                        my $match = match_rectangle_in_map( $main_map_png, $auto_hotzone_bgcolor,
                            1,		# match-origin: top-right
                            $x_max, $pos_y,
                            $x_min, $y_min, $x_max, $y_max
                        );

                        # quickly return if no match
                        next if not defined $match;

                        # additionally, the minimum width or height for an auto
                        # hotzone is 2 * auto_hotzone_width - it must overlap 2
                        # screens, and we start matching at (border -
                        # auto_hotzone_width)
                        next if ( ( $match->{'x_max'} - $match->{'x_min'} + 1 < 2 * $auto_hotzone_width ) or
                                ( $match->{'y_max'} - $match->{'y_min'} + 1 < 2 * $auto_hotzone_width ) );

                        # a valid match was found, mark its pixels as checked
                        foreach my $x ( $match->{'x_min'} .. $match->{'x_max'} ) {
                            foreach my $y ( $match->{'y_min'} .. $match->{'y_max'} ) {
                                $checked_pixels->[ $x ][ $y ]++;
                            }
                        }

                        # ...then save the matched hotzone
                        push @matched_hotzones, $match;
                    }
                }
            }

            # if we are not on the last row of screens in the map, locate
            # horizontal hotzones on the bottom border

            # same reasoning as above applies
            if ( $map_screen_row < ( $map_screen_rows - 1 ) ) {
                my $x_min = $map_screen_col * $screen_cols * 8 + $auto_hotzone_width;
                my $x_max = $map_screen_col * $screen_cols * 8 + $screen_width - $auto_hotzone_width - 1;
                my $y_min = $map_screen_row * $screen_rows * 8 + $screen_height - $auto_hotzone_width;
                my $y_max = $y_min + 2 * $auto_hotzone_width - 1;
                foreach my $pos_x ( $x_min .. $x_max ) {

                    #########################
                    # match top-to-bottom
                    #########################

                    # skip pixel if already checked by a previously matched hotzone
                    if ( not $checked_pixels->[ $pos_x ][ $y_min ] ) {

                        # mark pixel as checked
                        $checked_pixels->[ $pos_x ][ $y_min ]++;

                        # try to match a rectangle
                        my $match = match_rectangle_in_map( $main_map_png, $auto_hotzone_bgcolor,
                            0,	# match origin: top-left
                            $pos_x, $y_min,
                            $x_min, $y_min, $x_max, $y_max
                        );

                        # quickly return if no match
                        next if not defined $match;

                        # additionally, the minimum width or height for an auto
                        # hotzone is 2 * auto_hotzone_width - it must overlap 2
                        # screens, and we start matching at (border -
                        # auto_hotzone_width)
                        next if ( ( $match->{'x_max'} - $match->{'x_min'} + 1 < 2 * $auto_hotzone_width ) or
                                ( $match->{'y_max'} - $match->{'y_min'} + 1 < 2 * $auto_hotzone_width ) );

                        # a valid match was found, mark its pixels as checked
                        foreach my $x ( $match->{'x_min'} .. $match->{'x_max'} ) {
                            foreach my $y ( $match->{'y_min'} .. $match->{'y_max'} ) {
                                $checked_pixels->[ $x ][ $y ]++;
                            }
                        }

                        # ...then save the matched hotzone
                        push @matched_hotzones, $match;
                    }

                    #########################
                    # match bottom-to-top
                    #########################

                    # skip pixel if already checked by a previously matched hotzone
                    if ( not $checked_pixels->[ $pos_x ][ $y_max ] ) {

                        # mark pixel as checked
                        $checked_pixels->[ $pos_x ][ $y_max ]++;

                        # try to match a rectangle
                        my $match = match_rectangle_in_map( $main_map_png, $auto_hotzone_bgcolor,
                            2,	# match origin: bottom-left
                            $pos_x, $y_max,
                            $x_min, $y_min, $x_max, $y_max
                        );

                        # quickly return if no match
                        next if not defined $match;

                        # additionally, the minimum width or height for an auto
                        # hotzone is 2 * auto_hotzone_width - it must overlap 2
                        # screens, and we start matching at (border -
                        # auto_hotzone_width)
                        next if ( ( $match->{'x_max'} - $match->{'x_min'} + 1 < 2 * $auto_hotzone_width ) or
                                ( $match->{'y_max'} - $match->{'y_min'} + 1 < 2 * $auto_hotzone_width ) );

                        # a valid match was found, mark its pixels as checked
                        foreach my $x ( $match->{'x_min'} .. $match->{'x_max'} ) {
                            foreach my $y ( $match->{'y_min'} .. $match->{'y_max'} ) {
                                $checked_pixels->[ $x ][ $y ]++;
                            }
                        }

                        # ...then save the matched hotzone
                        push @matched_hotzones, $match;
                    }
                }
            }
        }
    }
}

# Now match the user-defined HOTZONEs
#
# Requirements:
#
# - A hotzone marker color can be specified with a command line argument
#   (RRGGBB format, default 00FF00 - green)
#
# Steps:
#
# - Walk the pixel data for all the map:
#
#   - Identify a pixel of the marker color
#
#   - Walk right until a pixel of different color is found, and mark each pixel as checked
#
#   - Ensure minimum width and note the found width
#
#   - Walk down matching full lines of pixels with the marker color and the
#     same width, until a line is found with different color
#
#   - Ensure minimum height
#
#   - If the above procedure has found a new HOTZONE, then:
#
#     - If the hotzone is fully contained in a single screen, then save the
#       HOTZONE, mark the pixels as matched and checked, and continue
#       matching
#
#     - If the hotzone overlaps two screens, split into two hotzones which
#       are each contained in single screens, associate each hotzone with
#       the other one, mark the pixels as matched and checked, and continue
#       matching

print "Scanning HOTZONEs...\n";

# reset the $checked_pixels variable, it may have been used before by the
# auto-hotzone code
undef $checked_pixels;

# first, sweep all the image identifying hotzones globally
foreach my $pos_x ( 0 .. ( $map_width - 1 ) ) {
    foreach my $pos_y ( 0 .. ( $map_height - 1 ) ) {

        # skip pixel if already checked by a previously matched hotzone
        next if $checked_pixels->[ $pos_x ][ $pos_y ];

        # mark pixel as checked
        $checked_pixels->[ $pos_x ][ $pos_y ]++;

        # try to match a rectangle
        my $match = match_rectangle_in_map( $main_map_png, $hotzone_color,
            0,	# match origin: top-left
            $pos_x, $pos_y,
            0, 0, ( $map_width - 1 ), ( $map_height - 1 )
        );

        # quickly return if no match
        next if not defined $match;

        # a match was found, mark its pixels as checked
        foreach my $x ( $match->{'x_min'} .. $match->{'x_max'} ) {
            foreach my $y ( $match->{'y_min'} .. $match->{'y_max'} ) {
                $checked_pixels->[ $x ][ $y ]++;
            }
        }

        # ...then save the matched hotzone
        push @matched_hotzones, $match;
    }
}

printf "-- Identified %d global HOTZONEs\n", scalar( @matched_hotzones );

###########################################################################
###########################################################################
##
## 6. Process HOTZONEs and split if necessary
##
###########################################################################
###########################################################################

# Process hotzones: associate the screen where they are, splitting the
# hotzones that overlap two screens if necessary and converting global
# coordinates (map) to local ones (screen).  Error if a hotzone overlaps
# more than 2 screens, they are not supported.  Remember that dimensions
# are in pixels, but the screen position is (row,col)

# this will contain the final list of processed hotzones, with additional
# metadata
my @all_hotzones;

# walk the previous list of raw hotzones
my $split_hotzone_count = 0;
foreach my $hotzone ( @matched_hotzones ) {

    # calculate all the screens that are covered by this hotzone
    # we just see where the four corners lay on the map
    my %covered_screens = map {
            # map screen row: y / screen_height
            # map screen col: x / screen_width
            my $screen_row = int( $_->[1] / $screen_height );
            my $screen_col = int( $_->[0] / $screen_width );
            ( 
                sprintf( "%03d_%03d", $screen_row, $screen_col ),
                { row => $screen_row, col => $screen_col }
            ) 
        } ( 
        [ $hotzone->{'x_min'}, $hotzone->{'y_min'} ],	# process the four corners
        [ $hotzone->{'x_max'}, $hotzone->{'y_min'} ],
        [ $hotzone->{'x_min'}, $hotzone->{'y_max'} ],
        [ $hotzone->{'x_max'}, $hotzone->{'y_max'} ],
        );

    if ( scalar( keys %covered_screens ) == 1 ) {
        # if only one screen is covered, just save the hotzone to the final list
        my ( $screen ) = map { $covered_screens{ $_ } } keys %covered_screens;
        my $index = scalar( @all_hotzones );
        push @all_hotzones, {
            index		=> $index,
            screen_row		=> $screen->{'row'},
            screen_col		=> $screen->{'col'},
            global_x_min	=> $hotzone->{'x_min'},
            global_x_max	=> $hotzone->{'x_max'},
            global_y_min	=> $hotzone->{'y_min'},
            global_y_max	=> $hotzone->{'y_max'},
            local_x_min		=> $hotzone->{'x_min'} % $screen_width,
            local_x_max		=> $hotzone->{'x_max'} % $screen_width,
            local_y_min		=> $hotzone->{'y_min'} % $screen_height,
            local_y_max		=> $hotzone->{'y_max'} % $screen_height,
            pix_width		=> $hotzone->{'x_max'} - $hotzone->{'x_min'} + 1,
            pix_height		=> $hotzone->{'y_max'} - $hotzone->{'y_min'} + 1,
        };
    } elsif ( scalar( keys %covered_screens ) == 2 ) {

        $split_hotzone_count++;

        # if two screens are covered, split the hotzone in two and link them
        my ( $screen_a, $screen_b ) = map { $covered_screens{ $_ } } sort keys %covered_screens;

        # save the indexes that they will have, for future reference
        my $index_a = scalar( @all_hotzones );
        my $index_b = $index_a + 1;

        # now with the hotzone split...
        my $hotzone_a;
        my $hotzone_b;

        # check if we need to split horizontally or vertically
        if ( $screen_a->{'row'} eq $screen_b->{'row'} ) {
            # screens on the same map row => vertical split
            # global y_min and y_max coords are the same in both
            # screen A: left - screen B: right
            my $x_min_a = $hotzone->{'x_min'};
            my $x_max_a = $screen_b->{'col'} * $screen_width - 1;	# screen A, right border
            my $x_min_b = $screen_b->{'col'} * $screen_width;		# screen B, left border
            my $x_max_b = $hotzone->{'x_max'};
            $hotzone_a = {
                index		=> $index_a,
                screen_row	=> $screen_a->{'row'},
                screen_col	=> $screen_a->{'col'},
                global_x_min	=> $x_min_a,
                global_x_max	=> $x_max_a,
                global_y_min	=> $hotzone->{'y_min'},
                global_y_max	=> $hotzone->{'y_max'},
                local_x_min	=> $x_min_a % $screen_width,
                local_x_max	=> $x_max_a % $screen_width,
                local_y_min	=> $hotzone->{'y_min'} % $screen_height,
                local_y_max	=> $hotzone->{'y_max'} % $screen_height,
                linked_hotzone	=> $index_b,
                link_type	=> 'right',
                pix_width	=> $x_max_a - $x_min_a + 1,
                pix_height	=> $hotzone->{'y_max'} - $hotzone->{'y_min'} + 1,
            };
            $hotzone_b = {
                index		=> $index_b,
                screen_row	=> $screen_b->{'row'},
                screen_col	=> $screen_b->{'col'},
                global_x_min	=> $x_min_b,
                global_x_max	=> $x_max_b,
                global_y_min	=> $hotzone->{'y_min'},
                global_y_max	=> $hotzone->{'y_max'},
                local_x_min	=> $x_min_b % $screen_width,
                local_x_max	=> $x_max_b % $screen_width,
                local_y_min	=> $hotzone->{'y_min'} % $screen_height,
                local_y_max	=> $hotzone->{'y_max'} % $screen_height,
                linked_hotzone	=> $index_a,
                link_type	=> 'left',
                pix_width	=> $x_max_b - $x_min_b + 1,
                pix_height	=> $hotzone->{'y_max'} - $hotzone->{'y_min'} + 1,
            };
        } else {
            # screens on the same map column => horizontal split
            # global x_min and x_max coords are the same in both
            # screen A: top - screen B: bottom
            my $y_min_a = $hotzone->{'y_min'};
            my $y_max_a = $screen_b->{'row'} * $screen_height - 1;	# screen A, bottom border
            my $y_min_b = $screen_b->{'row'} * $screen_height;		# screen B, top border
            my $y_max_b = $hotzone->{'y_max'};
            $hotzone_a = {
                index		=> $index_a,
                screen_row	=> $screen_a->{'row'},
                screen_col	=> $screen_a->{'col'},
                global_x_min	=> $hotzone->{'x_min'},
                global_x_max	=> $hotzone->{'x_max'},
                global_y_min	=> $y_min_a,
                global_y_max	=> $y_max_a,
                local_x_min	=> $hotzone->{'x_min'} % $screen_width,
                local_x_max	=> $hotzone->{'x_max'} % $screen_width,
                local_y_min	=> $y_min_a % $screen_height,
                local_y_max	=> $y_max_a % $screen_height,
                linked_hotzone	=> $index_b,
                link_type	=> 'down',
                pix_width	=> $hotzone->{'x_max'} - $hotzone->{'x_min'} + 1,
                pix_height	=> $y_max_a - $y_min_a + 1,
            };
            $hotzone_b = {
                index		=> $index_b,
                screen_row	=> $screen_b->{'row'},
                screen_col	=> $screen_b->{'col'},
                global_x_min	=> $hotzone->{'x_min'},
                global_x_max	=> $hotzone->{'x_max'},
                global_y_min	=> $y_min_b,
                global_y_max	=> $y_max_b,
                local_x_min	=> $hotzone->{'x_min'} % $screen_width,
                local_x_max	=> $hotzone->{'x_max'} % $screen_width,
                local_y_min	=> $y_min_b % $screen_height,
                local_y_max	=> $y_max_b % $screen_height,
                linked_hotzone	=> $index_a,
                link_type	=> 'up',
                pix_width	=> $hotzone->{'x_max'} - $hotzone->{'x_min'} + 1,
                pix_height	=> $y_max_b - $y_min_b + 1,
            };
        }

        # save hotzones in order: screen A, then screen B
        push @all_hotzones, $hotzone_a, $hotzone_b;

    } else {
        # if more than two screens are covered, error
        die sprintf( "** Error: Hotzone (%d,%d)-(%d,%d) covers more than 2 screens\n",
            map { $hotzone->{ $_ } } qw( x_min y_min x_max y_max )
        );
    }
}

printf "-- %d HOTZONEs were split between screens\n", $split_hotzone_count;

# At this point we have a list of the HOTZONEs found in the main map, with
# all their own metadata (x_min,y_min), (x_max,y_max) in local and global
# coords, and the index of the linked one, when applicable

printf "-- %d HOTZONEs were identified\n", scalar( @all_hotzones );

###########################################################################
###########################################################################
##
## 7. Generate check PNG image if needed
##
###########################################################################
###########################################################################

if ( $generate_check_map ) {

    print "Generating Check-Map file...\n";

    # create the output directory if it does not exist
    mkdir( $game_data_dir )
        if ( not -d $game_data_dir );

    # create the check directory if it does not exist
    mkdir( "$game_data_dir/check" )
        if ( not -d "$game_data_dir/check" );

    my $img = GD::Image->new( $map_width, $map_height );
    my $black = $img->colorAllocate( 0, 0, 0 );
    my $red = $img->colorAllocate( 255, 0, 0 );
    my $green = $img->colorAllocate( 0, 255, 0 );
    my $blue = $img->colorAllocate( 0, 0, 255 );
    my $white = $img->colorAllocate( 255, 255, 255 );
    my $yellow = $img->colorAllocate( 255, 255, 0 );

    # set black background
    $img->fill( 0, 0, $black );

    # draw screen borders
    foreach my $i ( 0 .. ( $screen_rows - 1 ) ) {
        foreach my $j ( 0 .. ( $screen_cols - 1 ) ) {
            $img->rectangle(
                $j * $screen_width, $i * $screen_height,				# xmin, ymin
                ( $j + 1 ) * $screen_width - 1, ( $i + 1 ) * $screen_height - 1,	# xmax, ymax
                $white
            );
        }
    }

    # draw tile and item outlines
    foreach my $btile ( @matched_btiles ) {
        my $btile_height = scalar( @{ $all_btiles[ $btile->{'btile_index'} ]{'cell_data'} } ) * 8;
        my $btile_width = scalar( @{ $all_btiles[ $btile->{'btile_index'} ]{'cell_data'}[0] } ) * 8;

        # set color according to type (btile, item, crumb...)
        my $type = $all_btiles[ $btile->{'btile_index'} ]{'default_type'};
        my $color;
        if ( $type eq 'item' ) {
            $color = $blue;
        } elsif ( $type eq 'crumb' ){
            $color = $yellow;
        } else {
            $color = $red;
        }

        $img->rectangle(
            $btile->{'global_cell_col'} * 8,	# xmin
            $btile->{'global_cell_row'} * 8,	# ymin
            $btile->{'global_cell_col'} * 8 + $btile_width - 1,		# xmax
            $btile->{'global_cell_row'} * 8 + $btile_height - 1,	# ymax
            $color
        );
    }

    # draw hotzone outlines
    foreach my $hotzone ( @all_hotzones ) {
        $img->rectangle( 
            ( map { $hotzone->{ $_ } } qw( global_x_min global_y_min global_x_max global_y_max) ), 
            $green
        );
    }

    # all has been drawn, output the check-map PNG file on the working directory
    my $check_png_file = "$game_data_dir/check/" .
        basename( $map_png_file, '.png', '.PNG' ) . '-check-map.png';
    open CHECK_PNG,">$check_png_file" or
        die "** Error: could not open $check_png_file for writing\n";
    binmode CHECK_PNG;
    print CHECK_PNG $img->png;
    close CHECK_PNG;

    print "-- Check-Map file $check_png_file was created\n";
}

###########################################################################
###########################################################################
##
## 9. Gather information for each screen and put it together
##
###########################################################################
###########################################################################

# First we create a hash with the matches for each screen, so that only
# screens with matched btiles generate output
my %screen_data;

foreach my $match ( @matched_btiles ) {
    my $screen_name = $screen_metadata->[ $match->{'screen_row'} ][ $match->{'screen_col'} ]{'name'} ||
        sprintf( "AutoScreen_%03d_%03d", $match->{'screen_row'}, $match->{'screen_col'} );
    push @{ $screen_data{ $screen_name }{'btiles'} }, $match;
    $screen_data{ $screen_name }{'screen_row'} = $match->{'screen_row'};
    $screen_data{ $screen_name }{'screen_col'} = $match->{'screen_col'};
}

# Then we add the hotzones to each screen
foreach my $hotzone ( @all_hotzones ) {
    my $screen_name = $screen_metadata->[ $hotzone->{'screen_row'} ][ $hotzone->{'screen_col'} ]{'name'} ||
        sprintf( "AutoScreen_%03d_%03d", $hotzone->{'screen_row'}, $hotzone->{'screen_col'} );

    # save the screen name, we'll need it later
    $hotzone->{'screen_name'} = $screen_name;

    push @{ $screen_data{ $screen_name }{'hotzones'} }, $hotzone;
    $screen_data{ $screen_name }{'screen_row'} = $hotzone->{'screen_row'};
    $screen_data{ $screen_name }{'screen_col'} = $hotzone->{'screen_col'};
}

# Hash %screen data has been populated by the previous steps.  Now we merge
# the remaining metadata for each screen
foreach my $screen_name ( keys %screen_data ) {
    my $screen_row = $screen_data{ $screen_name }{'screen_row'};
    my $screen_col = $screen_data{ $screen_name }{'screen_col'};
    if ( defined( $screen_metadata->[ $screen_row ][ $screen_col ] ) ) {
        $screen_data{ $screen_name }{'metadata'} = $screen_metadata->[ $screen_row ][ $screen_col ];
    }
}

###########################################################################
###########################################################################
##
## 9. Generate GDATA files for each map screen
##
###########################################################################
###########################################################################

print "Generating Screen GDATA files...\n";

# create the output directory if it does not exist
mkdir( $game_data_dir )
    if ( not -d $game_data_dir );

# Walk the screen list and create the associated GDATA file for that screen
# with all its associated data:
#   - BTILE definitions
#   - HOTZONE definitions
#   - ITEM definitions

# create the map directory if it does not exist
mkdir( "$game_data_dir/map" )
    if ( not -d "$game_data_dir/map" );

foreach my $screen_name ( sort keys %screen_data ) {
    my $screen_data = $screen_data{ $screen_name };
    my $output_file = sprintf( "%s/map/%s.gdata", $game_data_dir, $screen_name );
    open GDATA,">$output_file" or
        die "** Error: could not open file $output_file for writing\n";

    print GDATA <<EOF_MAP_GDATA_HEADER
BEGIN_SCREEN
EOF_MAP_GDATA_HEADER
;

    # we like the name as the first directive :-)
    printf GDATA "\tNAME\t%s\n", $screen_name;

    # output screen metadata first
    foreach my $key ( sort keys %{ $screen_data->{'metadata'} } ) {

        # skip if it's the name, we have already output it before :-)
        next if ( $key eq 'name' );

        # special metadata value processing
        my $value = $screen_data->{'metadata'}{ $key };

        # it it's the title, enclose in quotes
        if ( $key eq 'title' ) {
            $value = sprintf( '"%s"', $value);
        }

        # if it's a multivalue, generate proper new value
        if ( ref( $value ) eq 'HASH' ) {
            my $new_value = join( " ", map {
                    sprintf( "%s=%s", uc( $_ ), $value->{ $_ } )
                } sort keys %{ $value }
            );
            $value = $new_value;
        }

        # output
        printf GDATA "\t%s\t%s\n", uc( $key ), $value;
    }

    # Output btiles, items and crumbs.  Items and Crumbs are just different
    # types of BTILEs.  If the BTILE is of type ITEM, then we assume it can
    # be found only once on the same screen, and then use the BTILE name as
    # the name instead of the generated one

    my $btile_counter = 0;
    foreach my $btile ( @{ $screen_data->{'btiles'} } ) {
        my $btile_instance_name = sprintf( 'GeneratedBTile_%d', $btile_counter++ );
        my $btile_data = $all_btiles[ $btile->{'btile_index'} ];
        if ( $btile_data->{'default_type'} eq 'crumb' ) {
            # crumbs are a special case
            printf GDATA "\tCRUMB\tNAME=%s\tTYPE=%s ROW=%d COL=%d\n",
                $btile_instance_name,
                $btile_data->{'metadata'}{'type'},
                $btile->{'cell_row'} + $game_area_top,
                $btile->{'cell_col'} + $game_area_left,
            ;
        } else {
            printf GDATA "\t%s\tNAME=%s\tBTILE=%s\tROW=%d COL=%d ACTIVE=1 CAN_CHANGE_STATE=0\n",
                uc( $btile_data->{'default_type'} ),
                ( $btile_data->{'default_type'} eq 'item' ? $btile_data->{'name'} : $btile_instance_name ),
                $btile_data->{'name'},
                $btile->{'cell_row'} + $game_area_top,
                $btile->{'cell_col'} + $game_area_left,
            ;
        }
    }

    # hotzones are output separately
    my $hotzone_counter = 0;
    foreach my $hotzone ( @{ $screen_data->{'hotzones'} } ) {
        my $hotzone_name = sprintf( 'GeneratedHotzone_%d', $hotzone_counter++ );

        # save the generated hotzone name, we'll need it later
        $hotzone->{'name'} = $hotzone_name;

        # hotzone coordinates must be offset by the game area top,left coords!
        printf GDATA "\tHOTZONE\tNAME=%s\tX=%d Y=%d PIX_WIDTH=%d PIX_HEIGHT=%d ACTIVE=1\n",
            $hotzone_name,
            $hotzone->{ 'local_x_min' } + $game_area_left * 8,
            $hotzone->{ 'local_y_min' } + $game_area_top * 8,
            $hotzone->{ 'pix_width' },
            $hotzone->{ 'pix_height'},
        ;
    }



    # print the closing command and close the GDATA file
    print GDATA <<EOF_MAP_GDATA_END
END_SCREEN
EOF_MAP_GDATA_END
;

    close GDATA;

    printf "-- File %s for screen '%s' was created\n", $output_file, $screen_name;
}

###########################################################################
###########################################################################
##
## 9.1. Generate GDATA files with BTILE definitions
##
###########################################################################
###########################################################################

# This is run in all cases.  If autogenerated BTILEs were created, they will be included in the
# generation.  If only the TILEDEF definitions are used, only those tiles will be output.  This
# replaces functionality previously in btilegen.pl script

print "Generating BTile GDATA files...\n";

my $btile_format = <<"END_FORMAT";
// tiledef line: '%s %d %d %d %d %s'
BEGIN_BTILE
        NAME    %s
        ROWS    %d
        COLS    %d

        PNG_DATA        FILE=%s XPOS=%d YPOS=%d WIDTH=%d HEIGHT=%d
END_BTILE

END_FORMAT

# create the btiles directory if it does not exist
mkdir( "$game_data_dir/btiles" )
    if ( not -d "$game_data_dir/btiles" );

foreach my $btile_data ( grep { $_->{'used_in_screen'} } @all_btiles ) {
    my $output_file = sprintf( "%s/btiles/auto_%s.gdata", $game_data_dir, $btile_data->{'name'} );
    open GDATA,">$output_file" or
        die "** Error: could not open file $output_file for writing\n";

    printf GDATA $btile_format,
        ( map { $btile_data->{$_} } qw( name cell_row cell_col cell_width cell_height default_type ) ),
        ( map { $btile_data->{$_} } qw( name cell_height cell_width png_file ) ),
        ( map { $btile_data->{$_} * 8 } qw( cell_col cell_row cell_width cell_height ) );

    close GDATA;

    printf "-- File %s for BTILE '%s' was created\n", $output_file, $btile_data->{'name'};
}

###########################################################################
###########################################################################
##
## 10. Generate GDATA files with FLOWGEN rules for screen switching
##
###########################################################################
###########################################################################

print "Generating Flow GDATA files...\n";

# Walk the HOTZONE list and generate the GDATA files with FLOWGEN rules
# associated to the HOTZONEs

# create the flow directory if it does not exist
mkdir( "$game_data_dir/flow" )
    if ( not -d "$game_data_dir/flow" );

foreach my $screen_name ( sort keys %screen_data ) {
    my $screen_data = $screen_data{ $screen_name };
    my $output_file = sprintf( "%s/flow/%s.gdata", $game_data_dir, $screen_name );
    open GDATA,">$output_file" or
        die "** Error: could not open file $output_file for writing\n";

    # output hotzone rules
    foreach my $hotzone ( @{ $screen_data->{'hotzones'} } ) {

        # no rules nust be generated for hotzones not linked to others
        if ( not defined( $hotzone->{'linked_hotzone'} ) ) {
            printf GDATA "// Hotzone '%s' has no links, its rules must be defined manually\n\n", $hotzone->{'name'};
            next;
        }

        printf GDATA "// Hotzone '%s' screen-warp rule\n", $hotzone->{'name'};
        print  GDATA "BEGIN_RULE\n";
        printf GDATA "\tSCREEN\t%s\n", $screen_name;
        print  GDATA "\tWHEN\tGAME_LOOP\n";
        printf GDATA "\tCHECK\tHERO_OVER_HOTZONE %s\n", $hotzone->{'name'};

        # calculate the hero destination config based on the link_type
        my $hero_dest_cfg;
        if ( $hotzone->{'link_type'} eq 'left' ) {
            $hero_dest_cfg = sprintf( 'DEST_HERO_X=%d',
                $game_area_left * 8
                + $screen_width
                - $all_hotzones[ $hotzone->{'linked_hotzone'} ]{'pix_width'}
                - $hero_sprite_width
            );
        } elsif ($hotzone->{'link_type'} eq 'right' ) {
            $hero_dest_cfg = sprintf( 'DEST_HERO_X=%d',
                $game_area_left * 8
                + 0
                + $all_hotzones[ $hotzone->{'linked_hotzone'} ]{'pix_width'}
                - 0
            );
        } elsif ($hotzone->{'link_type'} eq 'up' ) {
            $hero_dest_cfg = sprintf( 'DEST_HERO_Y=%d',
                $game_area_top * 8
                + $screen_height
                - $all_hotzones[ $hotzone->{'linked_hotzone'} ]{'pix_height'}
                - $hero_sprite_height
            );
        } elsif ($hotzone->{'link_type'} eq 'down' ) {
            $hero_dest_cfg = sprintf( 'DEST_HERO_Y=%d',
                $game_area_top * 8
                + 0
                + $all_hotzones[ $hotzone->{'linked_hotzone'} ]{'pix_height'}
                - 0
            );
        } else {
            die sprintf "** Error: Screen '%s', Hotzone '%s': unexpected link type '%s'\n",
                $screen_name,
                $hotzone->{'name'},
                $hotzone->{'link_type'};
        }

        printf GDATA "\tDO\tWARP_TO_SCREEN DEST_SCREEN=%s %s\n",
            $all_hotzones[ $hotzone->{'linked_hotzone'} ]{'screen_name'},
            $hero_dest_cfg;
        print GDATA "END_RULE\n\n";
    }

    close GDATA;
    printf "-- File %s: for screen '%s' was created\n", $output_file, $screen_name;
}

####################################################################################
####################################################################################
###
### 11. Check that GAME_CONFIG section has the needed definitions and warn if not
###
####################################################################################
####################################################################################

my @config_lines_needed;
if ( scalar( keys %map_crumb_types ) ) {

    # if we detected CRUMBs in the map, do some additional checks
    print "CRUMBs were detected on the map, checking GAME_CONFIG definitions...\n";

    # load the GAME_CONFIG section from the game_data directory and load the
    # CRUMB_TYPE directives if they exist
    my $game_config_file = "$game_data_dir/game_config/Game.gdata";
    my %config_crumb_types;
    if ( open GAME_CONFIG, $game_config_file ) {
        while ( my $line = <GAME_CONFIG> ) {
            chomp $line;
            $line =~ s#//.*$##g;	# remove comments to EOL
            $line =~ s/^\s*//g;	# remove leading whitespace
            next if $line =~ /^$/;	# skip empty lines
            if ( $line =~ /^CRUMB_TYPE\s+(\w.*)$/ ) {
                # ARG1=val1 ARG2=va2 ARG3=val3...
                my $args = $1;
                my $item = {
                    map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                    split( /\s+/, $args )
                };
                if ( not defined( $item->{'name'} ) ) {
                    warn "** Syntax error in $game_config_file, will not check CRUMB_TYPE definitions!\n";
                    warn "** Error line -> $line\n";
                    last;
                }
                $item->{'source_line'} = $line;
                $config_crumb_types{ $item->{'name'} } = $item;
            }
        }
        close GAME_CONFIG;
    } else {
        warn "** Could not open $game_config_file, will not check CRUMB_TYPE definitions!\n";
    }

    # try to match the crumbs found on the map with definitions in the
    # config file
    foreach my $map_crumb ( keys %map_crumb_types ) {
        if ( not defined( $config_crumb_types{ $map_crumb } ) or
            not defined( $config_crumb_types{ $map_crumb }{'btile'} ) or
            ( $config_crumb_types{ $map_crumb }{'btile'} ne $map_crumb_types{ $map_crumb }{'btile_name'} ) ) {
            push @config_lines_needed, sprintf "\tCRUMB_TYPE\tNAME=%s BTILE=%s\n",
                $map_crumb,
                $map_crumb_types{ $map_crumb }{'btile_name'},
                ;
        }
    }

    # if some warnings are needed, issue them
    if ( scalar( @config_lines_needed ) ) {
        print <<EOF_CRUMBS_DETECTED

-- ATTENTION!  Some CRUMB_TYPE configuration is missing.  Make sure
-- appropriate CRUMB_TYPE lines appear inside the GAME_CONFIG section
-- (normally in game_data/game_config/Game.config file).  The needed
-- configuration lines follow:

EOF_CRUMBS_DETECTED
;
        print join( "\n\t", @config_lines_needed ), "\n\n";
    } else {
        print "-- All needed CRUMB_TYPE definitions are present in GAME_CONFIG\n";
    }

}

print "MAPGEN Execution successful!\n";

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
use Getopt::Long;

# arguments: 2 or more PNG files, plus some required switches (screen
# dimensions, output directory, etc.)

my ( $screen_cols, $screen_rows, $screen_output_dir );
my ( $flow_output_dir, $game_area_top, $game_area_left );
my ( $hero_sprite_width, $hero_sprite_height );
my ( $auto_hotzones );

(
    GetOptions(
        "screen-cols=i"		=> \$screen_cols,
        "screen-rows=i"		=> \$screen_rows,
        "screen-output-dir=s"	=> \$screen_output_dir,
        "flow-output-dir=s"		=> \$flow_output_dir,
        "game-area-top=i"		=> \$game_area_top,
        "game-area-left=i"		=> \$game_area_left,
        "hero-sprite-width=i"	=> \$hero_sprite_width,
        "hero-sprite-height=i"	=> \$hero_sprite_height,
        "auto-hotzones"		=> \$auto_hotzones,
    )
    and ( scalar( @ARGV ) >= 2 )
    and defined( $screen_cols )
    and defined( $screen_rows )
    and defined( $screen_output_dir )
#    and defined( $flow_output_dir )
#    and defined( $game_area_top )
#    and defined( $game_area_left )
#    and defined( $hero_sprite_width )
#    and defined( $hero_sprite_height )
) or die "usage: " . basename( $0 ) . " <options> <map_png> <btile_png> [<btile_png>]...\n" . <<EOF_HELP

Where <options> can be the following:

Required:

    --screen-cols <cols>		Width of each screen, in 8x8 cells
    --screen-rows <rows>		Height of each screen, in 8x8 cells
    --screen-output-dir <dir>		Output directory for Screen GDATA files
    --flow-output-dir <dir>		Output directory for Flow rules GDATA files
    --game-area-top <row>		Top row of the Game Area
    --game-area-left <col>		Left column of the Game Area
    --hero-sprite-width <width>		Width of the Hero sprite, in pixels
    --hero-sprite-height <height>	Height of the Hero sprite, in pixels

Optional:

    --auto-hotzones			Autodetects HOTZONEs between adjacent screens

EOF_HELP
;

my @png_files = @ARGV;	# remaining args after option processing

# Stages:

# 1.  Process the list of PNG files and classify them as BTILE or MAP
# images.
#
# PNGs for which a corresponding TILEDEF file exists will be considered as
# containing BTILES.  A PNG that does not have a matching TILEDEF file will
# be considered the main map.  There can be only one PNG without TILEDEF
# file.  The map file can have an optional MAPDEF file with screen metadata.

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
        push @all_btiles, {
            cell_data		=> $btile_data,
            name		=> $tiledef->{'name'},
            default_type	=> $tiledef->{'default_type'},
        };

        # ...and update the index
        push @{ $btile_index{ $btile_data->[0][0]{'hexdump'} } }, $current_btile_index;
    }
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

# 3. Process the main map image:
#   - Get the full list of cell data for it
#   - Process the MAPDEF file if it exists and get the screen metadata

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

# precalculate the size of the map, in vertical and horizontal screens
my $map_screen_rows = $map_rows / $screen_rows;
my $map_screen_cols = $map_cols / $screen_cols;

# load cell data from PNG
my $main_map_cell_data = png_get_all_cell_data( $png );


# this variable holds the screen metadata from the MAPDEF file. Initially undef for all screens.
my $screen_metadata;
push @$screen_metadata, [ (undef) x $map_screen_cols ] for ( 0 .. ( $map_screen_rows - 1 ) );

# load screen metadata from MAPDEF file if it exists
my $mapdef_file = dirname( $map_png_file ) . '/' . basename( $map_png_file, '.png', '.PNG' ) . '.mapdef';
if ( -e $mapdef_file ) {
    open MAPDEF, $mapdef_file or
        die "Could not open MAPDEF file $mapdef_file for reading\n";

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
            die sprintf( "Screen(%d,%d): row %d is outside of the map (max allowed: %d)\n", 
                $map_screen_row, $map_screen_col, $map_screen_row, $map_screen_rows - 1 );
        }
        if ( $map_screen_col >= $map_screen_cols ) {
            die sprintf( "Screen(%d,%d): column %d is outside of the map (max allowed: %d)\n", 
                $map_screen_row, $map_screen_col, $map_screen_col, $map_screen_cols - 1 );
        }

        # process and save screen metadata at the proper position
        $screen_metadata->[ $map_screen_row ][ $map_screen_col ] = {
            map {
                my ($k,$v) = split( /=/, $_ );		# split into key=value
                $k = lc($k);				# canonicalize key
                $v =~ s/_/ /g if ( $k eq 'title' );	# replace _ with ' ' in titles
                ( $k, $v ) 				# return the pair for the hash
            } @rest
        };
    }

    close MAPDEF;
}

# At this point we also have the cell data and optional screen metadata for
# the main map.  Now we only need to walk the main map cells trying to match
# them with the BTILEs we know

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

    foreach my $r ( 0 .. ( scalar( @$btile_data ) - 1 ) ) {
        foreach my $c ( 0 .. ( scalar( @{ $btile_data->[0] } ) - 1 ) ) {

            # return undef if out of the screen
            return undef if ( ( $pos_row + $r ) > $screen_bottom );
            return undef if ( ( $pos_col + $c ) > $screen_right );

            # return undef if the cell has already been matched by a
            # previous btile
            return undef if $matched_cells->[ $pos_row + $r ][ $pos_col + $c ];

            # return undef as soon as there is a cell mismatch
            return undef if ( $map->[ $pos_row + $r ][ $pos_col + $c ]{'hexdump'} ne
                $btile_data->[ $r ][ $c ]{'hexdump'} );
        }
    }

    # all btile cells matched the cells on the map, so return true
    return 1;
}

# walk the screen array
foreach my $screen_row ( 0 .. ( $map_screen_rows - 1 ) ) {
    foreach my $screen_col ( 0 .. ( $map_screen_cols - 1 ) ) {

        # temporary values
        my $global_screen_top = $screen_row * $screen_rows;
        my $global_screen_left = $screen_col * $screen_cols;
        my $global_screen_bottom = $global_screen_top + $screen_rows - 1;
        my $global_screen_right = $global_screen_left + $screen_cols - 1;

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
#                            printf "** MATCH: screen:(%2d,%2d) - pos:(%2d,%2d) - global_pos:(%2d,%2d) - btile:%3d (%s)\n",
#                                $screen_row,$screen_col,$cell_row,$cell_col,$global_cell_row,$global_cell_col,
#                                $btile_index, $all_btiles[ $btile_index ]{'name'};

                            # we also mark all of its cells as checked and matched
                            foreach my $r ( 0 .. ( $btile_rows - 1 ) ) {
                                foreach my $c ( 0 .. ( $btile_cols - 1 ) ) {
                                    $checked_cells->[ $global_cell_row + $r ][ $global_cell_col + $c ]++;
                                    $matched_cells->[ $global_cell_row + $r ][ $global_cell_col + $c ]++;
                                }
                            } # end of mark-as-checked-and-matched

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

#print Dumper( $checked_cells );
#print Dumper( \@matched_btiles );

# 5.  Check thet all cells in the status map are in state "checked".  This
# means that the whole map has been compiled successfully

my @non_checked_cells;
foreach my $r ( 0 .. ( $map_rows - 1 ) ) {
    foreach my $c ( 0 .. ( $map_cols - 1 ) ) {
        if ( not $checked_cells->[ $r ][ $c ] ) {
            push @non_checked_cells, "  Cell ($r,$c) was not checked";
        }
    }
}
if ( scalar( @non_checked_cells ) ) {
    die "Error: The following main map cells were not checked for BTILEs:" .
        join( "\n", @non_checked_cells ) . "\n";
}

# 6. Identify HOTZONEs in the main map PNG file - TBD
#
# Requirements:
#
# - A predefined color is selected as the HOTZONE marker with a command line
#   argument (RRGGBB format)
#
# - HOTZONEs are marked on the map as solid rectangles of the predefined
#   color
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

# When auto-hotzones is NOT selected:
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

# At this point we have a list of the HOTZONEs found in the main map, with
# their associated data: screen A, screen B, screen A position and size, and
# screen B position and size

# 7.  Walk the screen list and create the associated GDATA file for tat
# screen with all its associated data:
#   - BTILE definitions
#   - HOTZONE definitions
#   - ITEM definitions

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

# now we merge the remaining metadata for each screen
foreach my $screen_name ( keys %screen_data ) {
    my $screen_row = $screen_data{ $screen_name }{'screen_row'};
    my $screen_col = $screen_data{ $screen_name }{'screen_col'};
    if ( defined( $screen_metadata->[ $screen_row ][ $screen_col ] ) ) {
        $screen_data{ $screen_name } = { 
            %{ $screen_data{ $screen_name } },				# old hash
            %{ $screen_metadata->[ $screen_row ][ $screen_col ] }	# new hash
        };
    }
}

# Now we can output GDATA files for each screen and all its contained
# elements
my $btile_counter = 0;

foreach my $screen_name ( sort keys %screen_data ) {
    my $screen_data = $screen_data{ $screen_name };
    my $output_file = sprintf( "%s/%s.gdata", $screen_output_dir, $screen_name );
    open GDATA,">$output_file" or
        die "Could not open file $output_file for writing\n";

    print GDATA <<EOF_GDATA_HEADER
BEGIN_SCREEN
EOF_GDATA_HEADER
;

    printf GDATA "\tNAME\t%s\n", $screen_name;

    printf GDATA "\tDATASET\t%d\n", $screen_data->{'dataset'} || 0;

    if ( defined( $screen_data->{'title'} ) ) {
        printf GDATA "\tTITLE\t\"%s\"\n", $screen_data->{'title'};
    }

    foreach my $btile ( @{ $screen_data->{'btiles'} } ) {
        my $btile_instance_name = sprintf( 'AutoBTile_%d', $btile_counter++ );
        my $btile_data = $all_btiles[ $btile->{'btile_index'} ];
        printf GDATA "\t%s\tNAME=%s\tBTILE=%s\tROW=%d COL=%d ACTIVE=1 CAN_CHANGE_STATE=0\n",
            $btile_data->{'default_type'},
            $btile_instance_name,
            $btile_data->{'name'},
            $btile->{'cell_row'},
            $btile->{'cell_col'},
        ;
    }

    print GDATA <<EOF_GDATA_END
END_SCREEN
EOF_GDATA_END
;

    close GDATA;
}

# 8.  Walk the HOTZONE list and generate the GDATA files with FLOWGEN rules
# associated to the HOTZONEs

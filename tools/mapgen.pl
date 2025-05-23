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
use List::Util qw( uniq );
use Digest::SHA1 qw( sha1_hex );

STDOUT->autoflush(1);
STDERR->autoflush(1);

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
my $generate_btile_report;
my $coalesce_tiny_btiles;
# after analysis, this is the correct value
my $minimum_coalesceable_tiny_btiles = 6;
my $use_tileset_cache;
my $update_tileset_cache;
my $tileset_cache_file = 'mapgen-tileset-cache.gz';

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
        "generate-btile-report:s"	=> \$generate_btile_report,	# optional
        "coalesce-tiny-btiles"		=> \$coalesce_tiny_btiles,	# optional
        "use-tileset-cache"		=> \$use_tileset_cache,		# optional
        "update-tileset-cache"		=> \$update_tileset_cache,	# optional
        "tileset-cache-file:s"		=> \$tileset_cache_file,	# optional
    )
    and ( scalar( @ARGV ) >= 2 )
    and defined( $screen_cols )
    and defined( $screen_rows )
    and defined( $game_data_dir )
    and defined( $game_area_top )
    and defined( $game_area_left )
    and defined( $hero_sprite_width )
    and defined( $hero_sprite_height )
) or die "Usage: " . basename( $0 ) . " <options> <map_png> <btile_png> [<btile_png>]...\n" . <<EOF_HELP

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
    --generate-btile-report <file>	Writes a report of BTILEs used on each screen to the file given as parameter
    --coalesce-tiny-btiles		Coalesces tiny 1x1 BTILEs into bigger synthetic rectangular ones
    --use-tileset-cache			Use a previously built tileset cache file if present
    --update-tileset-cache		Force an update of the tileset cache file after creating the BTILE lists
    --tileset-cache-file		Specify an alternate tileset cache (default: tileset.cache)

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

    my $sanitized_basename = basename( $png_file, '.png', '.PNG' );
    $sanitized_basename =~ s/[\-\.]/_/g;

    my $file_prefix = $sanitized_basename . '_' . $prefix;

    my @generated_btiles;

    my %cell_seen;

    # first generate btiles for the individual 8x8 cells, as a fallback
    foreach my $r ( 0 .. png_get_height_cells( $png ) - 1 ) {
        foreach my $c ( 0 .. png_get_width_cells( $png ) - 1 ) {
            # get all cell data for the btile
            my $btile_data = png_get_all_cell_data( $png, $r, $c, 1, 1 );

            next if ( $cell_seen{ $btile_data->[0][0]{'hexdump'} } || 0 );
            $cell_seen{ $btile_data->[0][0]{'hexdump'} }++;

            # prepare btile cell data struct
            my $btile = {
                name		=> $file_prefix . '_' . sprintf( "cell_r%03dc%03d",$r,$c ),
                default_type	=> 'obstacle',
                metadata	=> '',
                cell_row	=> $r,
                cell_col	=> $c,
                cell_width	=> 1,
                cell_height	=> 1,
                num_cells	=> 1,	# precalculated for later
                cell_data	=> $btile_data,
                png_file	=> $png_file,
            };

            # store the btile cell data into the main btile list and update the index
            push @generated_btiles, $btile;
        }
    }

    # then generate the btiles for the tiledef definitions
    foreach my $tiledef ( @$tiledefs ) {

        # We do not generate btiles that are smaller than 6 cells.  They
        # will be identified as 1x1 tiny btiles (generated in the previous
        # step) and try to be coalesced later
        next if ( $tiledef->{'cell_width'} * $tiledef->{'cell_height'} < $minimum_coalesceable_tiny_btiles );

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
            num_cells		=> $tiledef->{'cell_width'} * $tiledef->{'cell_height'},	# precalculated for later
            cell_data		=> $btile_data,
            png_file		=> $png_file,
        };

        # store the btile cell data into the main btile list and update the index
        push @generated_btiles, $btile;

        # if automatic generation of btiles in tilesets has been requested,
        # create the list of all possible subtiles of all sizes (up to the
        # current btile size), except those that are full background
        # again, we do not create btiles smaller than 6 cells
        if ( $auto_tileset_btiles ) {
            my $height = $tiledef->{'cell_height'};
            my $width = $tiledef->{'cell_width'};
            foreach my $cur_height ( 1 .. $height ) {
                foreach my $cur_width ( 1 .. $width ) {

                    next if ( $cur_width * $cur_height < $minimum_coalesceable_tiny_btiles );

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
                                    num_cells		=> $cur_width * $cur_height,	# precalculated for later
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

my @all_btiles;			# list of all found btiles
my %btile_index;		# map of cell->hexdump => btile index
my %all_btiles_seen;
my $tilesets_were_preloaded = 0;

# adds to @all_btiles and %btile_index
sub add_btile_to_all_btiles_list {
    my $btile = shift;
    my $btile_hash;
    foreach my $row ( @{ $btile->{'cell_data'} } ) {
        foreach my $cell ( @$row ) {
            $btile_hash .= $cell->{'hexdump'};
        }
    }

    # ignore if it has already been added previously
    return if $all_btiles_seen{ $btile_hash };
    $all_btiles_seen{ $btile_hash }++;

    my $current_btile_index = scalar( @all_btiles );	# pos of new list element
    push @all_btiles, $btile;
    push @{ $btile_index{ $btile->{'cell_data'}[0][0]{'hexdump'} } }, $current_btile_index;
}

# if we were asked to use the cache, try to use it. If there are errors, warn but continue without it
if ( $use_tileset_cache ) {

    print "-- Loading BTILE definitions from tileset cache file...\n";
    my $error = 0;
    if ( open CACHE, "gzip -dc $tileset_cache_file |" ) {
        my $line_count = 1;
        while ( not $error and my $line = <CACHE> ) {
            my $VAR1;
            if ( defined( $line ) and eval $line ) {
                add_btile_to_all_btiles_list( $VAR1 );
            } else {
                warn "** Warning: data format invalid in $tileset_cache_file line $line_count\n";
                $error++;
            }
            $line_count++;
        }
        close CACHE;
    } else {
        warn "** Warning: could not open $tileset_cache_file for reading\n";
        $error++;
    }

    # signal success if no errors and some btiles were read
    if ( not $error and scalar( @all_btiles ) ) {
        $tilesets_were_preloaded++;
    }
}

# if tilesets are not loaded, do it
if ( not $tilesets_were_preloaded ) {

    print "-- Generating BTILE data...\n";

    # process all PNG Btile files
    foreach my $png_file ( @btile_files ) {

        # load the PNG and convert it to the ZX Spectrum color palette
        my $png = load_png_file( $png_file ) or
            die "** Error: could not load PNG file $png_file\n";
        map_png_colors_to_zx_colors( $png );

        # get all the tiledefs for the file
        my $tiledefs = btile_read_png_tiledefs( $png_file );

        btile_validate_png_tiledefs( $png, $tiledefs ) or
            die sprintf( "** Error: errors found in TILEDEF file for %s\n", $png_file );

        # initialize tile counter
        my $tile_count = 0;

        # process the PNG's cells and extract the btiles in all posible positions.
        #
        # There are 8 possible combinations of rotation and mirror):
        #
        #   R0  : 0 deg rotation, no mirror (the PNG file as-is)
        #   R0MV: 0 deg rotation, vert mirror
        #   R1  : 90 deg rotation, no mirror
        #   R1MH: 90 deg rotation, horiz mirror
        #   R2  : 180 rotation, no mirror
        #   R2MV: 180 rotation, vert mirror
        #   R3  : 270 rotation, no mirror
        #   R3MH: 270 rotation, horiz mirror

        my $prefix;
        my $n_png;
        my $n_tiledefs;

        # config: r0
        $prefix = 'r0';
        foreach my $btile ( generate_btiles( $png, $tiledefs, $png_file, $prefix ) ) {
            add_btile_to_all_btiles_list( $btile );
            $tile_count++;
        }

        # config: r0mv
        $prefix = 'r0mv';
        $n_png = png_vmirror( $png );
        $n_tiledefs = btile_vmirror_tiledefs( $tiledefs, png_get_width_cells( $png ), png_get_height_cells( $png ) );
        foreach my $btile ( generate_btiles( $n_png, $n_tiledefs, $png_file, $prefix ) ) {
            $btile->{'png_vmirror'} = 1;
            add_btile_to_all_btiles_list( $btile );
            $tile_count++;
        }

        # config: r1
        $prefix = 'r1';
        $n_png = png_rotate( $png, 1 );
        $n_tiledefs = btile_rotate_tiledefs( $tiledefs, png_get_width_cells( $png ), png_get_height_cells( $png ), 1 );
        foreach my $btile ( generate_btiles( $n_png, $n_tiledefs, $png_file, $prefix ) ) {
            $btile->{'png_rotate'} = 1;
            add_btile_to_all_btiles_list( $btile );
            $tile_count++;
        }

        # config: r1mh
        $prefix = 'r1mh';
        $n_png = png_hmirror( png_rotate( $png, 1 ) );
        $n_tiledefs = btile_hmirror_tiledefs(
            btile_rotate_tiledefs( $tiledefs, png_get_width_cells( $png ), png_get_height_cells( $png ), 1 ),
            png_get_height_cells( $png ),	# width and height are swapped after rotation in R1 config
            png_get_width_cells( $png ),
        );
        foreach my $btile ( generate_btiles( $n_png, $n_tiledefs, $png_file, $prefix ) ) {
            $btile->{'png_rotate'} = 1;
            $btile->{'png_hmirror'} = 1;
            add_btile_to_all_btiles_list( $btile );
            $tile_count++;
        }

        # config: r2
        $prefix = 'r2';
        $n_png = png_rotate( $png, 2 );
        $n_tiledefs = btile_rotate_tiledefs( $tiledefs, png_get_width_cells( $png ), png_get_height_cells( $png ), 2 );
        foreach my $btile ( generate_btiles( $n_png, $n_tiledefs, $png_file, $prefix ) ) {
            $btile->{'png_rotate'} = 2;
            add_btile_to_all_btiles_list( $btile );
            $tile_count++;
        }

        # config: r2mv
        $prefix = 'r2mv';
        $n_png = png_vmirror( png_rotate( $png, 2 ) );
        $n_tiledefs = btile_vmirror_tiledefs(
            btile_rotate_tiledefs( $tiledefs, png_get_width_cells( $png ), png_get_height_cells( $png ), 2 ),
            png_get_width_cells( $png ),	# width and height are kept when in R2 rotation
            png_get_height_cells( $png ),
        );
        foreach my $btile ( generate_btiles( $n_png, $n_tiledefs, $png_file, $prefix ) ) {
            $btile->{'png_rotate'} = 2;
            $btile->{'png_vmirror'} = 1;
            add_btile_to_all_btiles_list( $btile );
            $tile_count++;
        }

        # config: r3
        $prefix = 'r3';
        $n_png = png_rotate( $png, 3 );
        $n_tiledefs = btile_rotate_tiledefs( $tiledefs, png_get_width_cells( $png ), png_get_height_cells( $png ), 3 );
        foreach my $btile ( generate_btiles( $n_png, $n_tiledefs, $png_file, $prefix ) ) {
            $btile->{'png_rotate'} = 3;
            add_btile_to_all_btiles_list( $btile );
            $tile_count++;
        }

        # config: r3mh
        $prefix = 'r3mh';
        $n_png = png_hmirror( png_rotate( $png, 3 ) );
        $n_tiledefs = btile_hmirror_tiledefs(
            btile_rotate_tiledefs( $tiledefs, png_get_width_cells( $png ), png_get_height_cells( $png ), 3 ),
            png_get_height_cells( $png ),	# width and height are swapped after rotation in R3 config
            png_get_width_cells( $png ),
        );
        foreach my $btile ( generate_btiles( $n_png, $n_tiledefs, $png_file, $prefix ) ) {
            $btile->{'png_rotate'} = 3;
            $btile->{'png_hmirror'} = 1;
            add_btile_to_all_btiles_list( $btile );
            $tile_count++;
        }

        # report
        printf "-- File %s: read %d BTILEs\n", $png_file, $tile_count;
    }

}

# if cache was asked to be rebuilt, do it but skip if it will be the same as the original
if ( $update_tileset_cache and not $tilesets_were_preloaded ) {
    print "-- Updating tileset cache file...\n";
    open CACHE, "| gzip > $tileset_cache_file" or
        die "** Error: could not open $tileset_cache_file for writing\n";
    foreach my $btile ( @all_btiles ) {
        my $btile_dump = Dumper( $btile );
        $btile_dump =~ s/\n/ /g;
        print CACHE $btile_dump, "\n";
    }
    close CACHE;
}

# Since there may be more than one BTILE with the same top-left cell, we now
# sort the lists associated to the cell hashes, in descending size order
# (number of cells).  We are interested in finding first the biggest BTILEs
# when searching.  Most of the time the lists will have only one element,
# but we need to account for all cases.

print "-- Sorting BTILEs...\n";
foreach my $hash ( keys %btile_index ) {
    my @sorted = sort {
        $all_btiles[ $b ]{'num_cells'} <=> $all_btiles[ $a ]{'num_cells'}
    } @{ $btile_index{ $hash } };
    $btile_index{ $hash } = \@sorted;
}
#foreach my $hash ( sort keys  %btile_index ) {
#    printf "%s: %s\n", $hash, join( ", ", map { sprintf "i:%d(n:%d)", $_, $all_btiles[ $_ ]{'num_cells'} } @{ $btile_index{ $hash } } );
#}
#exit;

# At this point, we have a global list of BTILEs ( @all_btiles ) and a index
# of hashes for the top-left cell of each one of them ( %btile_index ), so
# that we can quickly search for all the tiles that have that cell

printf "-- Total candidate BTILEs defined: %d\n", scalar( @all_btiles );
if ( scalar( keys %all_btiles_seen ) != scalar( @all_btiles ) ) {
    die sprintf( "** Error: not all BTILEs (%d) found in index (%d)\n", scalar( @all_btiles ), scalar( keys %all_btiles_seen ) );
}

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
#
#   - Calculate the hash for the map cell
#
#   - Search for the hash in the BTILE index (it should exist, error if
#     it doesn't)
#
#   - If there is only one match, it means that there is only one tile with
#     that cell, so verify that the remaining cells also match, and mark the
#     status for that cells as "matched" in the status array
#
#   - If there is more than one match, we should verify all the BTILEs,
#     starting by the bigger ones.  Hopefully one of them will match.  We
#     will stop the search and mark the relevant cell status as "matched" in
#     the status array
#
#   - When we have fully identified the BTILE, we save the name, position
#     and current screen number in the global BTILE instances list, but only
#     if the size of the identified BTILE is greater than 1x1.  1x1 cell
#     BTILEs will be handled in a separate step later on, and are saved in a
#     separate list.
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

# this lists will hold the matched btiles, with all associated metadata
my @matched_btiles;
my @matched_btiles_1x1;

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
my @btile_count_by_screen;
my @tiny_btile_count_by_screen;
foreach my $screen_row ( 0 .. ( $map_screen_rows - 1 ) ) {
    foreach my $screen_col ( 0 .. ( $map_screen_cols - 1 ) ) {

        # check
#        my $debug = ( $screen_row == 9 ) and ( $screen_col == 6 ) ? 1 : 0;

        # temporary values
        my $global_screen_top = $screen_row * $screen_rows;
        my $global_screen_left = $screen_col * $screen_cols;
        my $global_screen_bottom = $global_screen_top + $screen_rows - 1;
        my $global_screen_right = $global_screen_left + $screen_cols - 1;

        my $btile_count = 0;
        my $tiny_btile_count = 0;

        # walk the cell array on each screen
        foreach my $cell_row ( 0 .. ( $screen_rows - 1 ) ) {
            foreach my $cell_col ( 0 .. ( $screen_cols - 1 ) ) {

#                $debug and printf( "++ CELL_ROW:%d CELL_COL:%d\n", $cell_row, $cell_col );

                my $global_cell_row = $global_screen_top + $cell_row;
                my $global_cell_col = $global_screen_left + $cell_col;

                # skip if the cell is already owned by a previously matched
                # btile
#                $debug and printf( "++   MATCHED:%d\n", $matched_cells->[ $global_cell_row ][ $global_cell_col ] || 0 );
                next if $matched_cells->[ $global_cell_row ][ $global_cell_col ];

                # ...otherwise mark the cell as checked and continue
                $checked_cells->[ $global_cell_row ][ $global_cell_col ]++;

                # get the hash of the top-left cell
                my $top_left_cell_hash = $main_map_cell_data->[ $global_cell_row ][ $global_cell_col ]{'hexdump'};

                # skip if it is a background tile
#                $debug and printf( "++   TOP_LEFT_HASH:%s\n", $top_left_cell_hash );
                next if ( $top_left_cell_hash eq '000000000000000000' );

                # if there are one or more btiles with that cell hash as its
                # top-left, try to match all btiles from the list.
#                $debug and printf( "++   DEF(BTINDEX):%s\n", defined( $btile_index{ $top_left_cell_hash } )?1:0 );
                if ( defined( $btile_index{ $top_left_cell_hash } ) ) {

                    #  The list is ordered from bigger to smaller btile, so
                    # the biggest btile will be matched first.  First match
                    # wins
#                    $debug and printf( "++   LIST(BTINDEX):%d\n", scalar( @{ $btile_index{ $top_left_cell_hash } } ) );
                    foreach my $btile_index ( @{ $btile_index{ $top_left_cell_hash } } ) {
                        my $btile_data = $all_btiles[ $btile_index ]{'cell_data'};
                        my $btile_rows = scalar( @$btile_data );
                        my $btile_cols = scalar( @{ $btile_data->[0] } );

                        if ( match_btile_in_map( $main_map_cell_data,
                            $global_screen_top, $global_screen_left, $global_screen_bottom, $global_screen_right,
                            $btile_data,
                            $global_cell_row, $global_cell_col ) ) {

                            # if a match was found, add it to the proper list of matched btiles, but only if it is above the threshold
                            if ( $btile_rows * $btile_cols >= $minimum_coalesceable_tiny_btiles ) {
#                                $debug and printf( "++   MATCH! SCREEN_ROW:%d SCREEN_COL:%d CELL_ROW:%d CELL_COL:%d WIDTH:%d HEIGHT:%d\n",
#                                    $screen_row,$screen_col,$cell_row,$cell_col,$btile_cols, $btile_rows );
                                my $data = {
                                    screen_row	=> $screen_row,
                                    screen_col	=> $screen_col,
                                    cell_row	=> $cell_row,
                                    cell_col	=> $cell_col,
                                    global_cell_row	=> $global_cell_row,
                                    global_cell_col	=> $global_cell_col,
                                    btile_index	=> $btile_index,
                                };
                                if ( $coalesce_tiny_btiles ) {
                                    if ( ( $btile_rows == 1 ) and ( $btile_cols == 1 ) ) {
#                                        $debug and print "++   PUSHED TO \@matched_btiles_1x1\n";
                                        push @matched_btiles_1x1, $data;
                                    } else {
#                                        $debug and print "++   PUSHED TO \@matched_btiles\n";
                                        push @matched_btiles, $data;
                                        # mark it as used in the global BTILE list
                                        $all_btiles[ $btile_index ]{'used_in_screen'}++;
                                    }
                                } else {
#                                    $debug and print "++   PUSHED TO \@matched_btiles\n";
                                    push @matched_btiles, $data;
                                    # mark it as used in the global BTILE list
                                    $all_btiles[ $btile_index ]{'used_in_screen'}++;
                                }

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
                                if ( ( $btile_rows == 1 ) and ( $btile_cols == 1 ) ) {
                                    $tiny_btile_count++;
                                }
                                last;
                            } else {
                                # size is <= $minimum_coalesceable_tiny_btiles, so we skip it unless it is a 1x1 btile
                                if ( ( $btile_rows == 1 ) and ( $btile_cols == 1 ) ) {
                                    my $data = {
                                        screen_row	=> $screen_row,
                                        screen_col	=> $screen_col,
                                        cell_row	=> $cell_row,
                                        cell_col	=> $cell_col,
                                        global_cell_row	=> $global_cell_row,
                                        global_cell_col	=> $global_cell_col,
                                        btile_index	=> $btile_index,
                                    };
                                    if ( $coalesce_tiny_btiles ) {
#                                        $debug and print "++   PUSHED TO \@matched_btiles_1x1\n";
                                        push @matched_btiles_1x1, $data;
                                    } else {
#                                        $debug and print "++   PUSHED TO \@matched_btiles\n";
                                        push @matched_btiles, $data;
                                        # mark it as used in the global BTILE list
                                        $all_btiles[ $btile_index ]{'used_in_screen'}++;
                                    }

                                    # we also mark all of its cells as checked and matched
                                    $checked_cells->[ $global_cell_row ][ $global_cell_col ]++;
                                    $matched_cells->[ $global_cell_row ][ $global_cell_col ]++;

                                    # take note if the detected btile is a crumb
                                    if ( $all_btiles[ $btile_index ]{'default_type'} eq 'crumb' ) {
                                        $map_crumb_types{ $all_btiles[ $btile_index ]{'metadata'}{'type'} } = {
                                            btile_name	=> $all_btiles[ $btile_index ]{'name'},
                                        };
                                    }

                                    # whenever we find a match, skip the rest of btiles
                                    $tiny_btile_count++;
                                }
                            }
                        }

                    } # end of btile-list-walk-for-matches

                } # end of some-matches-found
 
            }
        } # end of cell-walk inside a screen

        # update btile counter for this screen
        $btile_count_by_screen[ $screen_row ][ $screen_col ] = $btile_count;
        $tiny_btile_count_by_screen[ $screen_row ][ $screen_col ] = $tiny_btile_count;

    }
} # end of screen-walk



###########################################################################
###########################################################################
##
## 4.1. Try to coalesce 1x1 BTILEs into bigger ones generated on the fly
##
###########################################################################
###########################################################################

# We will try to coalesce 1x1 tiles from @matched_btiles_1x1 in bigger
# rectangular tiles, and then add the coalesced tiles to the main btile list
# @matched_btiles, so that it can be processed later all together
#
# Steps:
#
# - Create an MxN array with all 1x1 matched btiles, with undef in positions
#   where no btile is found, and the btile index in @matched_btiles_1x1
#   where a btile is found
#
# - Create an MxN state array with all 0's
#
# - Walk the RxC screens one by one, and try to find rectangles of adjacent
#   1x1 cells
#
# - When a rectangle is found: 
#   - Create an ad-hoc btile definition and add it to the @all_btiles list
#   - Add the new btile definition and position to the @matched_btiles list
#   - Mark all the 1x1 btiles which have been coalesced {'coalesced'} = 1
#
# - Repeat until all the map has been walked
#
# - Walk all the @matched_btiles_1x1 list again, searching for 1x1 btiles
#   that have _not_ been coalesced.  For those that haven't, add them as 1x1
#   btiles to the main @matched_btiles list (these are the only 1x1 btiles
#   that will be finally output as such in the map definitions
#
# - Hopefully, lots of 1x1 btiles will be coalesced into bigger ones.  As
#   long as 6 or more 1x1 btiles are coalesced as a single, there will be
#   memory savings

if ( $coalesce_tiny_btiles ) {
    print "Coalescing tiny BTILEs...\n";

    # setup state array...
    my @map_cell;

    # reset state
    # { cell_id => <index in @matched_btiles_1x1>, checked => <state 0|1>, coalesced => <0|1> }
    foreach my $r ( 0 .. $map_rows - 1 ) {
        foreach my $c ( 0 .. $map_cols - 1 ) {
            $map_cell[ $r ][ $c ]{'cell_id'} = undef;
            $map_cell[ $r ][ $c ]{'checked'} = 0;
            $map_cell[ $r ][ $c ]{'coalesced'} = 0;
        }
    }

    # note all cells that have 1x1 btiles to coalesce
    foreach my $i ( 0 .. scalar( @matched_btiles_1x1 ) - 1 ) {
        my $btile = $matched_btiles_1x1[ $i ];
        $map_cell[ $btile->{'global_cell_row'} ][ $btile->{'global_cell_col'} ]{'cell_id'} = $i;
    }

    my $num_synthetic_btiles = 0;

    my $synthetic_btile_id = 1;		# initial

    # walk the whole map, screen by screen
    # for each screen, walk from left to right, top to bottom
    foreach my $map_row_index ( 0 .. $map_rows - 1 ) {
        foreach my $map_col_index ( 0 .. $map_cols - 1 ) {

            # skip this cell quickly if it has already been checked
            next if $map_cell[ $map_row_index ][ $map_col_index ]{'checked'};
            $map_cell[ $map_row_index ][ $map_col_index ]{'checked'}++;

            # skip if it does not have a coalesceable tile
            next if not defined( $map_cell[ $map_row_index ][ $map_col_index ]{'cell_id'} );

            # skip it if it has already been coalesced with some others
            next if $map_cell[ $map_row_index ][ $map_col_index ]{'coalesced'};

            # precalculate screen row and col
            my $current_screen_row = int( $map_row_index / $screen_rows );
            my $current_screen_col = int( $map_col_index / $screen_cols );

            # keep checking to the right while more btiles found until hole
            # (undef) found or screen width is reached
            # note the max width
            # start going down one row at at a time, doing the same up to the max width
            # repeat until on the start of the row we find a hole (undef)
            my $cell_check_row = $map_row_index;
            my $width = 0;
            while( ( $cell_check_row < ( $current_screen_row + 1 ) * $screen_rows ) and
                    not $map_cell[ $cell_check_row ][ $map_col_index ]{'coalesced'} and
                    defined( $map_cell[ $cell_check_row ][ $map_col_index ]{'cell_id'} ) ) {
                my $cell_check_col = $map_col_index;
                while ( ( $cell_check_col < ( $current_screen_col + 1 ) * $screen_cols ) and
                        not $map_cell[ $cell_check_row ][ $cell_check_col ]{'coalesced'} and
                        defined( $map_cell[ $cell_check_row ][ $cell_check_col ]{'cell_id'} ) ) {
                    $cell_check_col++;
                }
                # at the end of this loop $cell_check_col contains the first col that does NOT match
                # if this is the first row, use its width as the coalesced btile width
                my $current_width = $cell_check_col - $map_col_index;
                if ( $cell_check_row == $map_row_index ) {
                    $width = $current_width;
                } else {
                    last if ( $current_width < $width );
                }
                $cell_check_row++;
            }
            # at the end of this loop $cell_check_row contains the first row that does NOT match
            my $height = $cell_check_row - $map_row_index;

            # We have found a rectangle of 1x1 btiles, so define the big one and
            # send to main list.  At this point $width and $height have the
            # dimensions of the coalesced btile and $map_row_index and
            # $map_col_index have its position in the global map

            # WARNING!  After analysis I found that we only save memory if
            # we coalesce btiles with 6 or more cells, so if height x width
            # is less than that, do not create the coalesced btile.  The
            # tiny btiles other than the first will be checked later and try
            # again to be coalesced with others.  If in the end they are not
            # coalesced, they will be pushed with the remaining ones to the
            # general list as 1x1 btiles
            if ( $width * $height >= $minimum_coalesceable_tiny_btiles ) {

                # first we must create a new synthetic btile and add it to the general btile list
                # build the cell data array
                my $btile_data;
                foreach my $r ( 0 .. $height - 1 ) {
                    foreach my $c ( 0 .. $width - 1 ) {
                        # index in @matched_btiles_1x1
                        my $i1 = $map_cell[ $map_row_index + $r ][ $map_col_index + $c ]{'cell_id'};
                        # global index in @all_btiles
                        my $i2 = $matched_btiles_1x1[ $i1 ]{'btile_index'};
                        # btile_data of first and only cell (it's a 1x1 btile!)
                        $btile_data->[ $r ][ $c ] = $all_btiles[ $i2 ]{'cell_data'}[0][0];
                    }
                }
                # create a unique name
                my $unique_name = sprintf( "synth_%s_%05d", basename( $map_png_file, '.png', '.PNG' ), $synthetic_btile_id++ );
                my $synthetic_btile = {
                    name		=> $unique_name,
                    default_type	=> 'obstacle',
                    metadata		=> '',
                    cell_row		=> $map_row_index,	# ignored if no PNG
                    cell_col		=> $map_col_index,	# ignored ig no PNG
                    cell_width		=> $width,
                    cell_height		=> $height,
                    cell_data		=> $btile_data,
                    # no PNG file!
                    png_file		=> undef,
                    # mark it as used in the global BTILE list
                    used_in_screen	=> 1,
                };
                my $synthetic_btile_index = scalar( @all_btiles );
                push @all_btiles, $synthetic_btile;

                # then create the matched btile entry and push to @matched_btiles
                my $synthetic_btile_data = {
                    screen_row		=> int( $map_row_index / $screen_rows ),
                    screen_col		=> int( $map_col_index / $screen_cols ),
                    cell_row		=> $map_row_index % $screen_rows,
                    cell_col		=> $map_col_index % $screen_cols,
                    global_cell_row	=> $map_row_index,
                    global_cell_col	=> $map_col_index,
                    btile_index		=> $synthetic_btile_index,
                };
                push @matched_btiles, $synthetic_btile_data;

                # mark all its cells as checked in @map_cell array
                foreach my $r ( $map_row_index .. $map_row_index + $height - 1 ) {
                    foreach my $c ( $map_col_index .. $map_col_index + $width - 1 ) {
                        $map_cell[ $r ][ $c ]{'checked'}++;
                    }
                }

                # mark all its cells as {'coalesced'} = 1 in @matched_btiles_1x1 if height or width > 1
                if ( ( $width > 1 ) or ( $height > 1 ) ) {
                    foreach my $r ( $map_row_index .. $map_row_index + $height - 1 ) {
                        foreach my $c ( $map_col_index .. $map_col_index + $width - 1 ) {
                            $matched_btiles_1x1[ $map_cell[ $r ][ $c ]{'cell_id'} ]{'coalesced'}++;
                            $map_cell[ $r ][ $c ]{'coalesced'}++;
                        }
                    }
                }

                # update counters
                $btile_count_by_screen[ $current_screen_row ][ $current_screen_col ]++;
                $num_synthetic_btiles++;

                # continue and repeat until all the map has been walked
            }
        }
    }

    # end security check: all cells have been checked
    foreach my $r ( 0 .. $map_rows - 1 ) {
        foreach my $c ( 0 .. $map_cols - 1 ) {
            $map_cell[ $r ][ $c ]{'checked'} or
                die sprintf("** Error: security check (%d,%d) failed while coalescing 1x1 btiles!\n", $r, $c);
        }
    }

    # Walk all the @matched_btiles_1x1 list again, searching for 1x1 btiles that
    # have _not_ been coalesced.  For those that haven't, add them as 1x1 btiles
    # to the main @matched_btiles list (these are the only 1x1 btiles that will
    # be finally output as such in the map definitions)

    my $num_coalesced_btiles = 0;
    my $num_non_coalesced_btiles = 0;
    foreach my $b ( @matched_btiles_1x1 ) {
        if ( $b->{'coalesced'} ) {
            $num_coalesced_btiles++;
        } else {
            $num_non_coalesced_btiles++;
            push @matched_btiles, $b;
            $all_btiles[ $b->{'btile_index'} ]{'used_in_screen'}++;
        }
    }

    printf "-- %d tiny BTILEs coalesced into %d synthethic BTILEs\n", $num_coalesced_btiles, $num_synthetic_btiles;
    printf "-- %d tiny BTILEs not coalesced\n", $num_non_coalesced_btiles;

}	# end (if $coalesce_tiny_btiles)

# check btile count for all screens and report BTILE count for those with some identified
my $screens_with_too_many_btiles = 0;
foreach my $r ( 0 .. ( $map_screen_rows - 1 ) ) {
    foreach my $c ( 0 .. ( $map_screen_cols - 1 ) ) {
        my $btile_count = $btile_count_by_screen[ $r ][ $c ];
        my $tiny_btile_count = $tiny_btile_count_by_screen[ $r ][ $c ];
        if ( $btile_count ) {
            if ( $btile_count > 255 ) {
                warn sprintf( "** WARNING: Screen (%d,%d): matched %d BTILEs (more than 255)\n",
                    $r, $c, $btile_count );
                $screens_with_too_many_btiles++;
            } else {
                printf "-- Screen (%d,%d): matched %d BTILEs, %d tiny 1x1 BTILEs\n",
                    $r, $c, $btile_count, $tiny_btile_count;
            }
        }
    }
}

# die if errors found
if ( $screens_with_too_many_btiles ) {
    die "** Error: screens were found with more than 255 BTILEs\n";
}

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

# now count the number of btiles identified by screen, we will need it when
# identifying hotzones
my $btile_count_by_screen;
foreach my $bt ( @matched_btiles ) {
    $btile_count_by_screen->[ $bt->{'screen_row'} ][ $bt->{'screen_col'} ]++;
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
            if ( $map_screen_col < ( $map_screen_cols - 1 ) ) {
                my $x_min = $map_screen_col * $screen_cols * 8 + $screen_width - $auto_hotzone_width;
                my $x_max = $x_min + 2 * $auto_hotzone_width - 1;
                my $y_min = $map_screen_row * $screen_rows * 8 + $auto_hotzone_width;
                my $y_max = $map_screen_row * $screen_rows * 8 + $screen_height - $auto_hotzone_width - 1;
                push @matched_hotzones, {
                    x_min	=> $x_min,
                    x_max	=> $x_max,
                    y_min	=> $y_min,
                    y_max	=> $y_max,
                    width	=> $x_max - $x_min + 1,
                    height	=> $y_max - $y_min + 1,
                };
            }

            # if we are not on the last row of screens in the map, locate
            # horizontal hotzones on the bottom border
            if ( $map_screen_row < ( $map_screen_rows - 1 ) ) {
                my $x_min = $map_screen_col * $screen_cols * 8 + $auto_hotzone_width;
                my $x_max = $map_screen_col * $screen_cols * 8 + $screen_width - $auto_hotzone_width - 1;
                my $y_min = $map_screen_row * $screen_rows * 8 + $screen_height - $auto_hotzone_width;
                my $y_max = $y_min + 2 * $auto_hotzone_width - 1;
                push @matched_hotzones, {
                    x_min	=> $x_min,
                    x_max	=> $x_max,
                    y_min	=> $y_min,
                    y_max	=> $y_max,
                    width	=> $x_max - $x_min + 1,
                    height	=> $y_max - $y_min + 1,
                };
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

        # only add the hotzone if the screen contains btiles, not if it's empty
        next if ( not $btile_count_by_screen->[ $screen->{'row'} ][ $screen->{'col'} ] );

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

        # if two screens are covered, split the hotzone in two and link them
        my ( $screen_a, $screen_b ) = map { $covered_screens{ $_ } } sort keys %covered_screens;

        # only add the hotzone if both screens contain btiles, not if any of them is empty
        next if ( ( not $btile_count_by_screen->[ $screen_a->{'row'} ][ $screen_a->{'col'} ] ) or
            ( not $btile_count_by_screen->[ $screen_b->{'row'} ][ $screen_b->{'col'} ] ) );

        $split_hotzone_count++;

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

# converts an 8-bit value into "##..####.." representation (BTILEs)
sub byte_to_pixels {
    my $value = shift;
    ( $value <= 255 ) or
        die "** Error: byte_to_pixels called with value > 255!\n";
    my $bin = sprintf( "%08b", $value );
    $bin =~ s/1/##/g;
    $bin =~ s/0/../g;
    return $bin;
}

print "Generating BTile GDATA files...\n";

my $btile_format = <<END_FORMAT
// tiledef line: '%s %d %d %d %d %s'
BEGIN_BTILE
        NAME    %s
        ROWS    %d
        COLS    %d

END_FORMAT
;

# create the btiles directory if it does not exist
mkdir( "$game_data_dir/btiles" )
    if ( not -d "$game_data_dir/btiles" );

foreach my $btile_data ( grep { $_->{'used_in_screen'} } @all_btiles ) {
    my $output_file = sprintf( "%s/btiles/auto_%s.gdata", $game_data_dir, $btile_data->{'name'} );
    open GDATA,">$output_file" or
        die "** Error: could not open file $output_file for writing\n";

    # print header
    printf GDATA $btile_format,
        ( map { $btile_data->{$_} } qw( name cell_row cell_col cell_width cell_height default_type ) ),
        ( map { $btile_data->{$_} } qw( name cell_height cell_width ) )
    ;

    # print pixel and attr data
    if ( defined( $btile_data->{'png_file'} ) ) {
        # it may come from a PNG file
        printf GDATA "\tPNG_DATA\tFILE=%s XPOS=%d YPOS=%d WIDTH=%d HEIGHT=%d %s %s %s\n",
            $btile_data->{'png_file'},
            ( map { $btile_data->{$_} * 8 } qw( cell_col cell_row cell_width cell_height ) ),
            ( defined( $btile_data->{'png_rotate'} ) ? sprintf('PNG_ROTATE=%d',$btile_data->{'png_rotate'}) : '' ),
            ( defined( $btile_data->{'png_hmirror'} ) ? sprintf('PNG_HMIRROR=%d',$btile_data->{'png_hmirror'}) : '' ),
            ( defined( $btile_data->{'png_vmirror'} ) ? sprintf('PNG_VMIRROR=%d',$btile_data->{'png_vmirror'}) : '' ),
        ;
    } else {
        # or be a synthetic btile
        # print pixel data
        foreach my $r ( 0 .. $btile_data->{'cell_height'} - 1 ) {
            foreach my $l ( 0 .. 7 ) {
                my $pixel_line;
                foreach my $c ( 0 .. $btile_data->{'cell_width'} - 1 ) {
                    $pixel_line .= byte_to_pixels( $btile_data->{'cell_data'}[ $r ][ $c ]{'bytes'}[ $l ] );
                }
                printf GDATA "\tPIXELS\t%s\n", $pixel_line;
            }
        }
        # print attr data
        foreach my $r ( 0 .. $btile_data->{'cell_height'} - 1 ) {
            foreach my $c ( 0 .. $btile_data->{'cell_width'} - 1 ) {
                printf GDATA "\tATTR\t%s\n", $btile_data->{'cell_data'}[ $r ][ $c ]{'attr'};
            }
        }
    }

    print GDATA "END_BTILE\n";
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

if ( $generate_btile_report ) {
    # gather info
    my %screen_report;
    foreach my $screen_name ( sort keys %screen_data ) {
        foreach my $btile ( @{ $screen_data{ $screen_name }{'btiles'} } ) {
            $screen_report{ $screen_name }{'btile_count'}{ $all_btiles[ $btile->{'btile_index'} ]{'name'} }++;
            $screen_report{ $screen_name }{'mapgen_dataset'} = $screen_data{ $screen_name }{'metadata'}{'dataset'};
        }
    }
    # write report in Data::Dumper format
    open REPORT, ">$generate_btile_report" or
        die "** Could not open file $generate_btile_report for writing\n";
    print REPORT Dumper( \%screen_report );
    close REPORT;
    print "-- Screen BTILE report written to file $generate_btile_report\n";
}

print "MAPGEN Execution successful!\n";

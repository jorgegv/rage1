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

use Carp;
use Data::Dumper;
use List::MoreUtils qw( frequency );

# standard ZX Spectrum color palette
my %zx_colors = (
    '000000' => 'BLACK',
    '0000C0' => 'BLUE',
    '00C000' => 'GREEN',
    '00C0C0' => 'CYAN',
    'C00000' => 'RED',
    'C000C0' => 'MAGENTA',
    'C0C000' => 'YELLOW',
    'C0C0C0' => 'WHITE',
    '0000FF' => 'BLUE',
    '00FF00' => 'GREEN',
    '00FFFF' => 'CYAN',
    'FF0000' => 'RED',
    'FF00FF' => 'MAGENTA',
    'FFFF00' => 'YELLOW',
    'FFFFFF' => 'WHITE',
);

# Loads a PNG file
# Returns a ref to a list of refs to lists of pixels
# i.e. each pixel can addressed as $png->[y][x]
# Each pixel is represented as RRGGBB, with the components in hex format, e.g. FFCB00
my $png_file_cache;

sub load_png_file {
    my $file = shift;

    # if data exists in cache for the file, just return it
    if ( exists( $png_file_cache->{ $file } ) ) {
        return $png_file_cache->{ $file };
    }

    # ..else, build it...
    my $command = sprintf( "pngtopam '%s' | pamtable", $file );
    my @pixel_lines = `$command`;
    chomp @pixel_lines;

    # ensure the PNG is in RGB format (pixels separated by '|') and is not indexed
    if ( not grep { /\|/ } @pixel_lines ) {
        warn "** Warning: PNG File $file is not in RGB(A) format\n";
        return undef;
    }

    my @pixels = map {			# for each line...
        s/(\d+)/sprintf("%02X",$1)/ge;	# replace decimals by upper hex equivalent
        s/ //g;				# remove spaces
       [ split /\|/ ];			# split each pixel data by '|' and return listref of pixels
    } @pixel_lines;

    # ...store in cache for later use...
    $png_file_cache->{ $file } = \@pixels;

    # ..and return it
    return \@pixels;
}

# get PNG dimensions in pixels and cells
sub png_get_width_pixels {
    my $png = shift;
    return scalar( @{ $png->[0] } );
}

sub png_get_height_pixels {
    my $png = shift;
    return scalar( @{ $png } );
}

sub png_get_width_cells {
    my $png = shift;
    return png_get_width_pixels( $png ) / 8;
}

sub png_get_height_cells {
    my $png = shift;
    return png_get_height_pixels( $png ) / 8;
}

# extracts pixel data in GDATA format from a PNG structure, by foreground color
# example: ##..####....##.. (for 10110010 - ##: pixel on; ..: pixel off)
# returns: listref - [ line1_data, line2_data, ... ]

# note: we NEED to pick by exact color (hex_fgcolor), since this function is
# used to get tile and sprite pixel data (normally white or similar), but
# also sprite _mask_ data (normally red).  So this function can't pick
# "anything but background", but a specific color

sub pick_pixel_data_by_color_from_png {
    my ( $png, $xpos, $ypos, $width, $height, $hex_fgcolor, $hmirror, $vmirror ) = @_;
    my @pixels = map {
        join( "",
            map {
                $_ eq $hex_fgcolor ? "##" : "..";		# filter color
                } @$_[ $xpos .. ( $xpos + $width - 1 ) ]	# select cols
        )
    } @$png[ $ypos .. ( $ypos + $height - 1 ) ];		# select rows
    if ( $hmirror ) {
        my @tmp = map { scalar reverse } @pixels;
        @pixels = @tmp;
    }
    if ( $vmirror ) {
        my @tmp = reverse @pixels;
        @pixels = @tmp;
    }
    return \@pixels;
}

# extracts pixel data in GDATA format from a PNG structure, by background color

sub pick_pixel_data_by_background_from_png {
    my ( $png, $xpos, $ypos, $width, $height, $hex_bgcolor, $hmirror, $vmirror ) = @_;
    my @pixels = map {
        join( "",
            map {
                $_ eq $hex_bgcolor ? ".." : "##";		# filter color
                } @$_[ $xpos .. ( $xpos + $width - 1 ) ]	# select cols
        )
    } @$png[ $ypos .. ( $ypos + $height - 1 ) ];		# select rows
    if ( $hmirror ) {
        my @tmp = map { scalar reverse } @pixels;
        @pixels = @tmp;
    }
    if ( $vmirror ) {
        my @tmp = reverse @pixels;
        @pixels = @tmp;
    }
    return \@pixels;
}

# extracts fg and bg color for a given 8x8 cell
# returns: hashref - { fg => <fg_color>, bg => <bg_color> }
# note: prefers '000000' as bg color if present
sub extract_colors_from_cell {
    my ( $png, $xpos, $ypos ) = @_;

    ( $xpos < png_get_width_pixels( $png ) ) or do {
        confess( sprintf( "Invalid xpos %d, should be less than %d\n", $xpos, png_get_width_pixels( $png ) ) );
    };
    ( $ypos < png_get_height_pixels( $png ) ) or do {
        confess( sprintf( "Invalid ypos %d, should be less than %d\n", $ypos, png_get_height_pixels( $png ) ) );
    };

    my %histogram = frequency map { @$_[ $xpos .. ($xpos + 7) ] } @$png[ $ypos .. ($ypos + 7) ];

    # get list of colors sorted by frequency
    my @l = sort { $histogram{ $a } > $histogram{ $b } } keys %histogram;

    # if more than 2 colors detected, warn the user
    if ( scalar( @l ) > 2 ) {
        foreach my $e ( 2 .. $#l ) {
            warn sprintf( "Warning: color #%s (%s)  detected but ignored\n",
                $l[$e], $zx_colors{ $l[$e] } );
        }
    }

    my $bg = $l[0];
    my $fg = $l[1] || $l[0];	# just in case there is only 1 color

    # if one of them is black, it is preferred as bg color, swap them if needed
    if ( $fg eq '000000' ) {
        $fg = $bg;
        $bg = '000000';
    }

    return { 'bg' => $bg, 'fg' => $fg };
}

# extracts attribute value for a 8x8 cell out of PNG data, in text form
# returns: attribute text representation - 'INK_xxx | PAPER_yyy | BRIGHT'
sub extract_attr_from_cell {
    my ( $png, $xpos, $ypos ) = @_;
    my $colors = extract_colors_from_cell( $png, $xpos, $ypos );
    my ( $bg, $fg ) = map { $colors->{$_} } qw( bg fg );
    my $attr = sprintf "INK_%s | PAPER_%s", $zx_colors{ $fg }, $zx_colors{ $bg };
    if ( ( $fg =~ /FF/ ) or ( $bg =~ /FF/ ) ) { $attr .= " | BRIGHT"; }
    return $attr;
}

# extracts attribute data in text form from a PNG - window pos and size and
# h/v mirror flags are accepted.
# returns: listref - [ 'INK_xxx | PAPER_yyy | BRIGHT', ... ]
sub attr_data_from_png {
    my ( $png, $xpos, $ypos, $width, $height, $hmirror, $vmirror ) = @_;
    my @attrs;
    # extract attr from cells left-right, top-bottom order
    my $y = $ypos;
    while ( $y < ( $ypos + $height ) ) {
        my $x = $xpos;
        while ( $x < ( $xpos + $width ) ) {
            push @attrs, extract_attr_from_cell( $png, $x, $y );
            $x += 8;
        }
        $y += 8;
    }
    my $c_width = $width / 8;
    my $c_height = $height / 8;
    if ( $hmirror ) {
        my @tmp;
        foreach my $c ( ( $c_width - 1 ) .. 0 ) {	# columns: reverse order
            foreach my $r ( 0 .. ( $c_height - 1 ) ) {	# rows: direct order
                push @tmp, $attrs[ $r * $c_width + $c ];
            }
        }
        @attrs = @tmp;
    }
    if ( $vmirror ) {
        my @tmp;
        foreach my $c ( 0 .. ( $c_width - 1 ) ) {	# columns: direct order
            foreach my $r ( ( $c_height - 1 ) .. 0 ) {	# rows: reverse order
                push @tmp, $attrs[ $r * $c_width + $c ];
            }
        }
        @attrs = @tmp;
    }
    return \@attrs;
}

# processes a PNG and returns two lists with pixel data in GDATA format and
# attributes in text form, as needed for GDATA files.
# returns: hashref - { pixels => [ [ ... ], [ ... ], ...], attrs => [ ... ] }
sub png_to_pixels_and_attrs {
    my ( $png, $xpos, $ypos, $width, $height ) = @_;

    # extract color and pixel data from cells left-right, top-bottom order
    my @colors;
    my @pixels;
    my $y = $ypos;
    while ( $y < ( $ypos + $height ) ) {
        my $x = $xpos;
        while ( $x < ( $xpos + $width ) ) {
            my $c = extract_colors_from_cell( $png, $x, $y );
            push @colors, $c;
            push @pixels, pick_pixel_data_by_background_from_png( $png, $x, $y, 8, 8, $c->{'bg'} );
            $x += 8;
        }
        $y += 8;
    }

    # we need to rearrange pixel data
    my @pixel_data_lines;
    my $nrows = $height / 8;
    my $ncols = $width / 8;
    foreach my $r ( 0 .. ( $nrows - 1 ) ) {
        foreach my $l ( 0 .. 7 ) {
            my $pixel_data_line;
            foreach my $c ( 0 .. ( $ncols - 1 ) ) {
                $pixel_data_line .= $pixels[ $r * $ncols + $c ][ $l ];
            }
            push @pixel_data_lines, $pixel_data_line;
        }
    }

    return {
            'pixels'	=> \@pixel_data_lines,
            'attrs'	=> attr_data_from_png( $png, $xpos, $ypos, $width, $height ),
    };
}

my %color_map_cache;

# for a given color, returns the nearest color from the standard ZX color palette
# returns: nearest color in RRGGBB format
sub zx_colors_best_fit {
    my $color = shift;

    # if the mapping has not been calculated before, calculate and put it
    # into the cache
    if ( not exists $color_map_cache{ $color } ) {
        $color =~ m/(\w\w)(\w\w)(\w\w)/;
        my ( $color_r, $color_g, $color_b ) = map { hex } ( $1, $2, $3 );
        my %distance = map {
            my $zxc = $_;
            $zxc =~ m/(\w\w)(\w\w)(\w\w)/;
            my ( $zx_r, $zx_g, $zx_b ) = map { hex } ( $1, $2, $3 );
            ( $zxc => ( ( $zx_r - $color_r )**2 + ( $zx_g - $color_g )**2 + ( $zx_b - $color_b )**2 ) );
        } keys %zx_colors;
        my @sorted = sort { $distance{ $a } <=> $distance{ $b } } keys %zx_colors;
        $color_map_cache{ $color } = $sorted[0];
    }

    # now it is positively in the cache, return it
    return $color_map_cache{ $color };
}

# processes a PNG replacing each pixel's color with the nearest ZX color
sub map_png_colors_to_zx_colors {
    my $png = shift;
    foreach my $r ( 0 .. $#{ $png } ) {
        foreach my $c ( 0 .. $#{ $png->[$r] } ) {
            $png->[$r][$c] = zx_colors_best_fit( $png->[$r][$c] );
        }
    }
}

# compiles a pixel line in GDATA format ( ##..##...etc) to the real bytes by
# grouping every 8 pixels.  The length of the pixel line must be a multiple
# of 16 (1 byte -> 16 GDATA characters)
# returns: list of byte values (0-255)
sub compile_pixel_line {
    my $pixels = shift;
    $pixels =~ s/\.{2}/0/g;
    $pixels =~ s/\#{2}/1/g;
    my @bytes = map { oct( '0b' . $_ ) } ( $pixels =~ /([01]{8})/g );
    return @bytes; 
}

# array for calculation of the numerical value of attributes in text form
my %attr_value = (
    'INK_BLACK'		=> 0,		# INK values (bits 0-2)
    'INK_BLUE'		=> 1,
    'INK_RED'		=> 2,
    'INK_MAGENTA'	=> 3,
    'INK_GREEN'		=> 4,
    'INK_CYAN'		=> 5,
    'INK_YELLOW'	=> 6,
    'INK_WHITE'		=> 7,
    'PAPER_BLACK'	=> 0 << 3,	# PAPER values (bits 3-5)
    'PAPER_BLUE'	=> 1 << 3,
    'PAPER_RED'		=> 2 << 3,
    'PAPER_MAGENTA'	=> 3 << 3,
    'PAPER_GREEN'	=> 4 << 3,
    'PAPER_CYAN'	=> 5 << 3,
    'PAPER_YELLOW'	=> 6 << 3,
    'PAPER_WHITE'	=> 7 << 3,
    'BRIGHT'		=> 1 << 6,	# BRIGHT value (bit 6)
);

# converts an attribute in text form into its numerical value
# returns: numeric attr value (0-255)
sub numeric_attr_value {
    my $attr = shift;
    my $value = 0;
    foreach my $v ( split( /\s*\|\s*/, $attr ) ) { $value += $attr_value{ $v } };
    return $value;
}

# gets pixel data and attribute from a PNG for a cell at ( $row, $col )
# returns: listref - { bytes => [ 8 bytes ], attr => numeric_attribute }
sub png_get_cell_data_at {
    my ( $png, $row, $col ) = @_;
    my $cell_data = png_to_pixels_and_attrs( $png, $col * 8, $row * 8, 8, 8 );
    my @bytes = map { ( compile_pixel_line( $_ ) )[0] } @{ $cell_data->{'pixels'} };
    my $attr = numeric_attr_value( $cell_data->{'attrs'}[0] );
    return {
        bytes => \@bytes,
        attr => $attr,
        hexdump => join( '', map { sprintf( "%02X", $_ ) } ( @bytes, $attr ) ),
    };
}

# breaks a PNG (or part of a PNG) into 8x8 cells and returns the 2-D array
# of cell data as returned by the previous function (a hashref: { bytes =>
# [], attr => value } ).  The data returned in accessible as
# $cells->[$row][$col].  Parameters $row, $col, $width, $height are
# optional.  If not specified, the full PNG will be processed
# returns: listref - [ [ cell_0_0_data, cell_0_1_data, ...], [ cell_1_0_data, cell_1_1_data, ...], ... ]
sub png_get_all_cell_data {
    my ( $png, $row, $col, $width, $height ) = @_;
    if ( not defined( $row ) or not defined( $col ) or not defined( $width ) or not defined( $height ) ) {
        $row = $col = 0;
        $width = png_get_width_cells( $png );
        $height = png_get_height_cells( $png );
    }
    my @rows;
    foreach my $r ( $row .. ( $row + $height - 1 ) ) {
        push @rows, [
            map {
                png_get_cell_data_at( $png, $r, $_ )
            } ( $col .. ( $col + $width - 1 ) )
        ];
    }
    return \@rows;
}

1;

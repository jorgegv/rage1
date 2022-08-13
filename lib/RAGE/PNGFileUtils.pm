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

# Loads a PNG file
# Returns a ref to a list of refs to lists of pixels
# i.e. each pixel can addressed as $png->[y][x]
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

# extracts pixel data in GDATA format from a PNG file
sub pick_pixel_data_by_color_from_png {
    my ( $file, $xpos, $ypos, $width, $height, $hex_fgcolor, $hmirror, $vmirror ) = @_;
    my $png = load_png_file( $file );
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

# calculates best attributes for a 8x8 cell out of PNG data
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

sub extract_colors_from_cell {
    my ( $png, $xpos, $ypos ) = @_;
    my %histogram;
    foreach my $x ( $xpos .. ( $xpos + 7 ) ) {
        foreach my $y ( $ypos .. ( $ypos + 7 ) ) {
            my $pixel_color = $png->[$y][$x];
            $histogram{$pixel_color}++;
        }
    }
    my @l = sort { $histogram{ $a } > $histogram{ $b } } keys %histogram;
    if (scalar( @l ) > 2 ) {
        foreach my $e ( 3 .. $#l ) {
            printf STDERR "Warning: color #%s (%s)  detected but ignored\n",
                $l[$e], $zx_colors{ $l[$e] };
        }
    }
    my $bg = $l[0];
    my $fg = $l[1] || $l[0];	# just in case there is only 1 color
    # if one of them is black, it is preferred as bg color, swap them if needed
    if ( $fg eq '000000' ) {
        my $tmp = $bg;
        $bg = $fg;
        $fg = $tmp;
    }
    return { 'bg' => $bg, 'fg' => $fg };
}

sub extract_attr_from_cell {
    my ( $png, $xpos, $ypos ) = @_;
    my $colors = extract_colors_from_cell( $png, $xpos, $ypos );
    my ( $bg, $fg ) = map { $colors->{$_} } qw( bg fg );
    my $attr = sprintf "INK_%s | PAPER_%s", $zx_colors{ $fg }, $zx_colors{ $bg };
    if ( ( $fg =~ /FF/ ) or ( $bg =~ /FF/ ) ) { $attr .= " | BRIGHT"; }
    return $attr;
}

sub attr_data_from_png {
    my ( $file, $xpos, $ypos, $width, $height, $hmirror, $vmirror ) = @_;
    my $png = load_png_file( $file );
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

sub png_to_pixels_and_attrs {
    my ( $file, $xpos, $ypos, $width, $height ) = @_;
    my $png = load_png_file( $file );

    # extract color and pixel data from cells left-right, top-bottom order
    my @colors;
    my @pixels;
    my $y = $ypos;
    while ( $y < ( $ypos + $height ) ) {
        my $x = $xpos;
        while ( $x < ( $xpos + $width ) ) {
            my $c = extract_colors_from_cell( $png, $x, $y );
            push @colors, $c;
            push @pixels, pick_pixel_data_by_color_from_png( $file, $x, $y, 8, 8, $c->{'fg'} );
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
            'attrs'	=> attr_data_from_png( $file, $xpos, $ypos, $width, $height ),
    };
}

1;

#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Data::Dumper;

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

# extracts pixel data from a PNG file
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

my %color_map_cache;

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

sub map_png_colors_to_zx_colors {
    my $png = shift;
    foreach my $r ( 0 .. $#{ $png } ) {
        foreach my $c ( 0 .. $#{ $png->[$r] } ) {
            $png->[$r][$c] = zx_colors_best_fit( $png->[$r][$c] );
        }
    }
}

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

    # map PNG colors to most accurate ZX colors
    map_png_colors_to_zx_colors( $png );

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

sub compile_pixel_line {
    my $pixels = shift;
    $pixels =~ s/\.{2}/0/g;
    $pixels =~ s/\#{2}/1/g;
    my @bytes = map { oct( '0b' . $_ ) } ( $pixels =~ /([01]{8})/g );
    return @bytes; 
}

my %attr_value = (
    'INK_BLACK'		=> 0,
    'INK_BLUE'		=> 1,
    'INK_RED'		=> 2,
    'INK_MAGENTA'	=> 3,
    'INK_GREEN'		=> 4,
    'INK_CYAN'		=> 5,
    'INK_YELLOW'	=> 6,
    'INK_WHITE'		=> 7,
    'PAPER_BLACK'	=> 0 << 3,
    'PAPER_BLUE'	=> 1 << 3,
    'PAPER_RED'		=> 2 << 3,
    'PAPER_MAGENTA'	=> 3 << 3,
    'PAPER_GREEN'	=> 4 << 3,
    'PAPER_CYAN'	=> 5 << 3,
    'PAPER_YELLOW'	=> 6 << 3,
    'PAPER_WHITE'	=> 7 << 3,
    'BRIGHT'		=> 1 << 6,
);

sub numeric_attr_value {
    my $attr = shift;
    my $value = 0;
    foreach my $v ( split( /\s*\|\s*/, $attr ) ) { $value += $attr_value{ $v } };
    return $value;
}

# mapping of lines in a screen third
# maps an order 0-63 (linear) to the Speccy one
my @zx_lines = (
    0, 8, 16, 24, 32, 40, 48, 56,	# 1st scan line of every char
    1, 9, 17, 25, 33, 41, 49, 57,	# 2nd scan line of every char
    2, 10, 18, 26, 34, 42, 50, 58,	# 3rd scan line of every char
    3, 11, 19, 27, 35, 43, 51, 59,	# 4th scan line of every char
    4, 12, 20, 28, 36, 44, 52, 60,	# 5th scan line of every char
    5, 13, 21, 29, 37, 45, 53, 61,	# 6th scan line of every char
    6, 14, 22, 30, 38, 46, 54, 62,	# 7th scan line of every char
    7, 15, 23, 31, 39, 47, 55, 63,	# 8th scan line of every char
);
sub compile_to_zx_data {
    my $img_data = shift;
    $img_data->{'zx_bytes'} = [
        # first third
        ( map { compile_pixel_line( $img_data->{'pixels'}[ $zx_lines[ $_ ] ] ) } ( 0 .. 63 ) ),
        # second third
        ( map { compile_pixel_line( $img_data->{'pixels'}[ 64 + $zx_lines[ $_ - 64 ] ] ) } ( 64 .. 127 ) ),
        # third third
        ( map { compile_pixel_line( $img_data->{'pixels'}[ 128 + $zx_lines[ $_ - 128 ] ] ) } ( 128 .. 191 ) ),
    ];
    $img_data->{'zx_attrs'} = [ map { numeric_attr_value( $_ ) } @{ $img_data->{'attrs'} } ];
}

sub output_scr_file {
    my ( $img, $output ) = @_;
    open( my $out, ">:raw", $output ) or
        die "Could not open $output for writing!\n";
    foreach my $b ( @{ $img->{'zx_bytes'} } ) {
        print $out pack( 'C', $b );
    }
    foreach my $b ( @{ $img->{'zx_attrs'} } ) {
        print $out pack( 'C', $b );
    }
    close $out;
}

##
## Main loop
##
my $file = $ARGV[0];
my $out_file = $ARGV[1];

my $png = load_png_file( $file );
( ( scalar( @$png ) == 192 ) and ( scalar( @{$png->[0]} ) == 256 ) ) or
    die "** Error: PNG image must be exactly 256x192 pixels\n";

my $img = png_to_pixels_and_attrs( $file, 0, 0, 256, 192 );
compile_to_zx_data( $img );
output_scr_file( $img, $out_file || "$file.scr" );
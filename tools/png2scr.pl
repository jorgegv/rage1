#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib";

require RAGE::PNGFileUtils;
require RAGE::FileUtils;

use Data::Dumper;

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

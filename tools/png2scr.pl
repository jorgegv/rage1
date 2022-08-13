#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib";

require RAGE::PNGFileUtils;
require RAGE::FileUtils;

use Data::Dumper;

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

sub compile_to_zx_screen_data {
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
compile_to_zx_screen_data( $img );
output_scr_file( $img, $out_file || "$file.scr" );

#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib/";
use RAGE::PNGFileUtils;
use Data::Dumper;

my $png_data = load_png_file( 'test.png' );

my $pixels = pick_pixel_data_by_color_from_png( $png_data,
    5 * 8, 8 * 8,	# xpos,ypos
    8,8,	# width, height
    '000000',	# bgcolor
    0,0,	# hmirror, vmirror
);

print Dumper( $pixels );

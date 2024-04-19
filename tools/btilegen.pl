#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib/";

require RAGE::BTileUtils;

use Getopt::Std;
use File::Basename;


my $btile_format = <<"END_FORMAT";
// tiledef line: '%s'
BEGIN_BTILE
        NAME    %s
        ROWS    %d
        COLS    %d

        PNG_DATA        FILE=%s XPOS=%d YPOS=%d WIDTH=%d HEIGHT=%d
END_BTILE

END_FORMAT

scalar( @ARGV ) or
    die "usage: btilegen.pl <png_file> [...]\n";

foreach my $png_file ( @ARGV ) {
    my $tiledefs = btile_read_png_tiledefs( $png_file );
    foreach my $td ( @$tiledefs ) {
        printf $btile_format, map { $td->{ $_ } }
            qw( tiledef_line name cell_height cell_width png_file pixel_pos_x pixel_pos_y pixel_width pixel_height );
    }
}

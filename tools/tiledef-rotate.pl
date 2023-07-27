#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Getopt::Std;

our ( $opt_l, $opt_r, $opt_w, $opt_h );
getopts('lrw:h:');

( ( defined( $opt_l ) or defined( $opt_r ) ) and defined( $opt_w ) and defined( $opt_h ) ) or
    die "usage: $0 <-l|-r> -w <width> -h <height>\n  -l: rotate tiledef counterclockwise\n  -r: rotate tiledef clockwise\n";

while (my $line = <>) {
    if ( $line =~ m/^([\w_]+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/ ) {
        my ( $id, $r, $c, $w, $h ) = ( $1, $2, $3, $4, $5 );
        if ( $opt_l ) {
            # for rotating left (counterclockwise), top-right corner will
            # become top-left, and we exchange width and height
            printf "%-30s%d %d %d %d\n", $id, $opt_w - $c - $w, $r, $h, $w;
        } else {
            # for rotating right (clockwise), bottom-left corner will become
            # top-left, and we exchange width and height
            printf "%-30s%d %d %d %d\n", $id, $c, $opt_h - $r - $h, $h, $w;
        }
    } else {
        print $line;
    }
}

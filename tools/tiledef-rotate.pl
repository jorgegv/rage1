#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Getopt::Std;

our ( $opt_l, $opt_r, $opt_W, $opt_H );
getopts('lrW:H:');

( ( defined( $opt_l ) or defined( $opt_r ) ) and defined( $opt_W ) and defined( $opt_H ) ) or
    die "usage: $0 <-l|-r> -W <width> -H <height>\n  -l: rotate tiledef counterclockwise\n  -r: rotate tiledef clockwise\n";

while (my $line = <>) {
    if ( $line =~ m/^([\w_]+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/ ) {
        my ( $id, $r, $c, $w, $h ) = ( $1, $2, $3, $4, $5 );
        if ( $opt_l ) {
            # for rotating left (counterclockwise), top-right corner will
            # become top-left, and we exchange width and height. Name is suffixed with _l_rot
            printf "%-40s %d %d %d %d\n", $id.'_l_rot', $opt_W - $c - $w, $r, $h, $w;
        } else {
            # for rotating right (clockwise), bottom-left corner will become
            # top-left, and we exchange width and height. Name is suffixed with _r_rot
            printf "%-40s %d %d %d %d\n", $id.'_r_rot', $c, $opt_H - $r - $h, $h, $w;
        }
    } else {
        print $line;
    }
}

#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Getopt::Std;

our ( $opt_h, $opt_v, $opt_W, $opt_H );
getopts('hvW:H:');

( ( defined( $opt_h ) or defined( $opt_v ) ) and defined( $opt_W ) and defined( $opt_H ) ) or
    die "usage: $0 <-h|-v> -W <width> -H <height>\n  -h: mirror tiledef horizontally\n  -v: mirror tiledef vertically\n";

while (my $line = <>) {
    if ( $line =~ m/^([\w_]+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/ ) {
        my ( $id, $r, $c, $w, $h ) = ( $1, $2, $3, $4, $5 );
        if ( $opt_h ) {
            # for horizontal mirror, top-right corner becomes top-left, and
            # (r,c) becomes (r,W-c).  Height and width are maintained. Names is suffixed with _h_mirror
            printf "%-40s %d %d %d %d\n", $id.'_h_mirror', $r, $opt_W - $c - $w, $w, $h;
        } else {
            # for vertical mirror, bottom-left corner becomes top-left, and
            # (r,c) becomes (H-r,c).  Height and width are maintained. Name is suffixed with _v_mirror
            printf "%-40s %d %d %d %d\n", $id.'_v_mirror', $opt_H - $r - $h, $c, $w, $h;
        }
    } else {
        print $line;
    }
}

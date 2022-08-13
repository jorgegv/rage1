#!/usr/bin/perl

use strict;
use warnings;
use utf8;

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
    my $basename = basename( $png_file, '.png', '.PNG' );
    my $dirname = dirname( $png_file );
    my $tiledef_file = $dirname . '/' . $basename . '.tiledef';

    open TILEDEF, $tiledef_file or
        die "Could not open $tiledef_file for reading\n";
    while ( my $line = <TILEDEF> ) {
        chomp $line;
        $line =~ s/#.*$//g;		# remove comments
        next if $line =~ m/^$/;		# skip line if empty
        $line =~ s/\s+/ /g;		# replace multiple spaces with one
        my ( $name, $row, $col, $width, $height ) = split( /\s+/, $line );
        printf $btile_format,
            $line,
            $name,
            $height,
            $width,
            $png_file, $col * 8, $row * 8, $width * 8, $height * 8;
    }
    close TILEDEF;
}

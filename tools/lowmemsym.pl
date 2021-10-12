#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Getopt::Std;

our ( $opt_m, $opt_v );
getopts("m:v");

my $map_file = $opt_m || 'main.map';
my @symbols = @ARGV;

open my $map, "<", $map_file or
    die "** Could not open $map_file for reading\n";

while ( my $line = <$map> ) {
    chomp $line;
    foreach my $sym ( @symbols ) {
        if ( $line =~ /^_\Q$sym\E\s+=\s+\$([A-Fa-f\d]+)\s+; addr/ ) {
            my $addr = hex( "0x$1" );
            if ( $addr >= 0xC000 ) {
                warn sprintf( "** Warning: symbol '%s' linked at address \$%X\n", $sym, $addr );
            } else {
                if ( defined( $opt_v ) ) {
                    printf( "Symbol '%s' linked at address \$%X [OK]\n", $sym, $addr );
                }
            }
        }
    }
}

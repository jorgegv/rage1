#!/usr/bin/env perl
################################################################################
##
## RAGE1 - Retro Adventure Game Engine, release 1
## (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
## 
## This code is published under a GNU GPL license version 3 or later.  See
## LICENSE file in the distribution for details.
## 
################################################################################

use strict;
use warnings;
use utf8;

use Getopt::Std;
use Data::Dumper;

our ( $opt_m );
getopts('m:');
defined( $opt_m ) or
    die "usage: $0 -m <map_file>\n";
my $map_file = $opt_m;

my $address;

# load symbols from map file
open my $map, "<", $map_file or
    die "** Error: could not open $map_file for reading\n";
while ( my $line = <$map> ) {
    chomp $line;
    next if not $line =~ /; addr, public/;
    if ( $line =~ /^([\w_]+)\s+=\s+\$([0-9a-fA-F]+)/ ) {
        $address->{ $1 } = $2;
    }
}
close $map;

# filter input replacing '{<symbol>}' sequences by their hex addresses
while ( my $line = <STDIN> ) {
    chomp $line;
    $line =~ s/#.*$//g;		# remove comments
    next if $line =~ /^$/;	# skip blank lines
    while ( $line =~ /\{([\w_]+)\}/ ) {
        my $sym = $1;
        my $addr = $address->{ $sym };
        $line =~ s/\{\Q$sym\E\}/\$\Q$addr\E/g;
    }
    print $line,"\n";
}

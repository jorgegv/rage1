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
        $address->{ $1 } = hex( '0x' . $2 );
    }
}
close $map;

# filter input replacing '{<symbol>}' sequences by their hex addresses
while ( my $line = <STDIN> ) {
    chomp $line;
    $line =~ s/#.*$//g;		# remove comments
    next if $line =~ /^$/;	# skip blank lines
    while ( $line =~ /\{([\w_\+\-\$xX]+)\}/ ) {
        my $expr = $1;

        my $sym;
        my $offset = 0;

        # handle {_symbol} case
        if ( $expr =~ /^([\w_]+)$/ ) {
            $sym = $1;
        # handle {_symbol+offset} case
        } elsif ( $expr =~ /^([\w_]+)([\+\-][\dA-Fa-fxX\$]+)$/ ) {
            $sym = $1;
            my $tmp_offset = $2;
            # handle {_symbol+0xNNNN} and {_symbol+$NNNN} cases (hex)
            if ( ( $tmp_offset =~ /^([\+\-])0[xX]([\dA-Fa-f]+)$/ ) or
                ( $tmp_offset =~ /^([\+\-])\$([\dA-Fa-f]+)$/ ) ) {
                $offset = ( $1 eq '-' ? -1 : 1 ) * hex( $2 );
            # handle {symbol+DDDD} case (decimal)
            } elsif ( $tmp_offset =~ /^([\+\-]\d+)$/ ) {
                $offset = $1;
            } else {
                die "** Invalid syntax: '$expr'\n";
            }
        } else {
            die "** Invalid syntax: '$expr'\n";
        }
        my $addr = $address->{ $sym } + $offset;
        my $hex_addr = sprintf( "%04x", $addr );
        $line =~ s/\{\Q$expr\E\}/\$\Q$hex_addr\E/g;
    }
    print $line,"\n";
}

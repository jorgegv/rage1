#!/usr/bin/perl -w

use strict;
use warnings;
use utf8;
use Data::Dumper;

# reads a .map file and outputs a C .h file with #defines for each addr
# symbol found

my %symbols;
while (my $line = <>) {
    chomp( $line );
    if ( $line =~ /^_(\w+)\s+=\s+\$([0-9A-Fa-f]+)\s;\saddr,/ ) {
        $symbols{ $1 } = hex( '0x' . $2 );
    }
}

foreach my $sym (sort keys %symbols ) {
    printf "#define MAIN_SYMBOL_%s	((void *) 0x%04X)\n", $sym, $symbols{ $sym };
}
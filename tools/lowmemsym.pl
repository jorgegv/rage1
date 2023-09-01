#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Getopt::Std;
use Data::Dumper;

our ( $opt_m, $opt_v );
getopts("m:v");

my $map_file = $opt_m || 'main.map';
my @symbols = @ARGV;

open my $map, "<", $map_file or
    die "** Could not open $map_file for reading\n";

# first parse the map file and get a symbol table
my %symbol_address;
while ( my $line = <$map> ) {
    chomp $line;
    if ( $line =~ /^(_?[\w]+)\s+=\s+\$([A-Fa-f\d]+)\s+; addr/ ) {
        $symbol_address{ $1 } = hex( $2 );
    }
}

# then match each symbol against the symbol table
print "Checking LOWMEM symbols...";

my $errors;
foreach my $sym ( @symbols ) {
    my $addr = 0;
    if ( defined( $symbol_address{ $sym } ) ) {
        $addr = $symbol_address{ $sym };
    }
    if ( defined( $symbol_address{ '_' . $sym } ) ) {
        $addr = $symbol_address{ '_' . $sym };
    }
    if ( $addr >= 0xC000 ) {
        $errors++;
        printf( "\n** Warning: symbol '%s' linked at address \$%X", $sym, $addr );
    } else {
        if ( defined( $opt_v ) ) {
            printf( "Symbol '%s' linked at address \$%X [OK]\n", $sym, $addr );
        }
    }
}

print ( $errors ? "\n" : "OK\n" );

#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Getopt::Long qw(:config no_ignore_case);
use Data::Dumper;

# B3-1: parameterise the lowmem threshold so non-ZX128 platforms with a
# different swap-window address can reuse this check. Default 0xC000
# preserves historical ZX 128 behaviour exactly (every symbol linked at
# or above this address is flagged as a lowmem violation).
my $map_file   = 'main.map';
my $verbose;
my $threshold_raw = '0xC000';

GetOptions(
    'm=s'         => \$map_file,
    'v'           => \$verbose,
    'threshold=s' => \$threshold_raw,
) or die "** Usage: $0 [-m <map_file>] [-v] [--threshold <addr>] <symbol> ...\n";

# Accept 0xNNNN or decimal forms.
my $threshold = ( $threshold_raw =~ /^0[xX]/ )
    ? oct( $threshold_raw )
    : $threshold_raw + 0;

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
    if ( $addr >= $threshold ) {
        $errors++;
        printf( "\n** Warning: symbol '%s' linked at address \$%X", $sym, $addr );
    } else {
        if ( $verbose ) {
            printf( "Symbol '%s' linked at address \$%X [OK]\n", $sym, $addr );
        }
    }
}

print ( $errors ? "\n" : "OK\n" );

#!/usr/bin/perl -w

use strict;
use warnings;
use utf8;
use v5.20;

use Data::Dumper;
use Getopt::Std;

# handle command options
our ( $opt_s, $opt_m, $opt_h );
getopts("smh");
if ( defined($opt_h) ) {
    say "usage: $0 [-s] [-m] [-h] <file.map> ...";
    say "  -s: section/symbol mode - dumps a table of the sections, symbols and their addresses";
    say "  -m: map mode - dumps a table of the section names, addresses and sizes";
    say "  -h: this help text";
    exit 1;
}

# set default mode to map-mode
if ( not defined( $opt_s ) and not defined( $opt_m ) ) {
    $opt_m++;
}

# slurp all data and create data struct
my $sections;
my $highest = 0;
while (<>) {
    chomp;
    my @f = split(/\s*;\s*/);
    if ( $f[1] =~ /addr,/ ) {
        # first part of the line (before ";")
        $f[0] =~ /^(\w+)\s+=\s+\$([A-Za-z0-9]+)/;
        my ( $symbol, $addr ) = ( $1, $2 );
        my $address = hex( "0x" . $addr );	# get symbol address
        # second part of the line (after ";")
        my @p2 = split( /, /, $f[1] );
        my $section = $p2[4];

        # if this is the first time we see this section, set initial top value
        if ( not exists $sections->{ $section } ) {
            $sections->{ $section }{'top'} = 0;
        }
        # store data into section
        push @{ $sections->{ $section }{'symbols'} }, {
            name	=> $symbol,
            address	=> $address,
        };
        # if this is the first symbol in this section, adjust base
        if ( scalar( @{ $sections->{ $section }{'symbols'} } ) == 1 ) {
            $sections->{ $section }{'base'} = $address;
        }
        # if this symbol is higher than the current top value, adjust top
        if ( $address > $sections->{ $section }{'top'} ) {
            $sections->{ $section }{'top'} = $address;
        }

        if ( $address > $highest ) {
            $highest = $address;
        }
    }
}

# fix the top values of all sections but the last
# ...TO DO

# about these predefined sections, see doc/MEMORY-MAP.doc
$sections->{'FREE'}	= { 'base' => $highest,	'top' => 0xcfff };
$sections->{'RESERVED'}	= { 'base' => 0xd000,	'top' => 0xffff };

# section/symbol mode
if ( defined( $opt_s ) ) {
    foreach my $sec ( sort { $sections->{ $a }{'base'} <=> $sections->{ $b }{'base'} } keys %$sections ) {
        foreach my $sym ( sort { $a->{'address'} <=> $b->{'address'} } @{ $sections->{ $sec }{'symbols'} } ) {
            printf "%-20s  %-60s  \$%04X\n", $sec, $sym->{'name'}, $sym->{'address'};
        }
    }
}

# map mode
if ( defined( $opt_m ) ) {
    my ( $code, $data, $bss, $free, $reserved ) = ( 0,0,0,0,0 );
    foreach my $sec ( sort { $sections->{ $a }{'base'} <=> $sections->{ $b }{'base'} } keys %$sections ) {
        my $size = $sections->{ $sec }{'top'} - $sections->{ $sec }{'base'};
        printf "%-20s  \$%04X (%-5d)  \$%04X (%-5d)  %d\n",
            $sec,
            $sections->{ $sec }{'base'}, $sections->{ $sec }{'base'},
            $sections->{ $sec }{'top'}, $sections->{ $sec }{'top'},
            $size;
        if ( $sec =~ m/^code/i ) {
            $code += $size;
        }
        if ( ( $sec =~ m/^rodata/i ) or ( $sec =~ m/^data/i ) ) {
            $data += $size;
        }
        if ( $sec =~ m/^bss/i ) {
            $bss += $size;
        }
        if ( $sec =~ m/^free/i ) {
            $free += $size;
        }
        if ( $sec =~ m/^reserved/i ) {
            $reserved += $size;
        }
    }
    say "";
    printf "TOTAL CODE: %d bytes\nTOTAL DATA: %d bytes\nTOTAL BSS : %d bytes\nTOTAL RESV: %d bytes\nTOTAL FREE: %d bytes\nTOTAL     : %d bytes\n",
        $code, $data, $bss, $reserved, $free,
        $code + $data + $bss + $reserved + $free,
        ;

}

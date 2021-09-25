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
            $sections->{ $section }{'base'} = 0xffff;
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

        # if this symbol is lower than the current base value, adjust base
        if ( $address < $sections->{ $section }{'base'} ) {
            $sections->{ $section }{'base'} = $address;
        }

        if ( $address > $highest ) {
            $highest = $address;
        }
    }
}

# about these predefined sections, see doc/MEMORY-MAP.doc
$sections->{'FREE'}		= { 'base' => $highest,	'top' => 0xd1ec, size => 0xd1ec - $highest + 1 };
$sections->{'RESERVED_SP1'}	= { 'base' => 0xd1ed,	'top' => 0xffff, size => 0xffff - 0xd1ed + 1 };

# fix the top values of all sections but the last
my @sections_in_order = sort { $sections->{ $a }{'base'} <=> $sections->{ $b }{'base'} } keys %$sections;
foreach my $i ( 0 .. $#sections_in_order ) {
    my $sec = $sections_in_order[ $i ];
    if ( ( $sec !~ '^RESERVED' ) and ( $sec ne 'FREE' ) ) {
        my $next_sec = $sections_in_order[ $i + 1 ];
        $sections->{ $sec }{'size'} = $sections->{ $sec }{'top'} - $sections->{ $sec }{'base'} + 1;
    }
}

# OK processing, now with the output...

# this sections will be ignored i reports and calculations
my @sections_to_ignore = (
    'data_threads', 'code_l', 'code_l_sdcc', 'code_math', 'code_stdlib',
    'code_temp_sp1', 'code_threads_mutex', 'code_z80',
);

# section/symbol mode
if ( defined( $opt_s ) ) {
    say '-'x90;
    printf "%-20s  %-60s  %-5s\n", "SECTION NAME", "SYMBOL NAME", "ADDR";
    say '-'x90;
    foreach my $sec ( @sections_in_order ) {
        next if ( scalar grep { $_ eq $sec } @sections_to_ignore );
        foreach my $sym ( sort { $a->{'address'} <=> $b->{'address'} } @{ $sections->{ $sec }{'symbols'} } ) {
            printf "%-20s  %-60s  \$%04X\n", $sec, $sym->{'name'}, $sym->{'address'};
        }
    }
    say '-'x90;
}

# map mode
if ( defined( $opt_m ) ) {
    my ( $code, $data, $bss, $free, $reserved ) = ( 0,0,0,0,0 );
    say '-'x70;
    printf "SECTION NAME          BASE           TOP            SIZE\n";
    say '-'x70;
    foreach my $sec ( @sections_in_order ) {
        next if ( scalar grep { $_ eq $sec } @sections_to_ignore );
        my $size = $sections->{ $sec }{'size'};
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
    say '-'x70;
    printf "TOTAL CODE     : %6d bytes\nTOTAL DATA     : %6d bytes\nTOTAL BSS      : %6d bytes\nTOTAL RESERVED : %6d bytes\nTOTAL FREE     : %6d bytes\n",
        $code, $data, $bss, $reserved, $free,
        ;
    say '-'x70;

}

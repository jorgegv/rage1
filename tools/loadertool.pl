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
use Data::Dumper;
use Getopt::Std;

my $basic_loader_name = 'loader.bas';

# auxiliary functions

# bank binaries are files under build/generated/ with names bank_N.bin
sub gather_bank_binaries {
    my ( $dir ) = @_;
    my %binaries;

    opendir BINDIR, $dir or
        die "** Error: could not open directory $dir for reading\n";
    foreach my $bin ( grep { /^bank_.*\.bin/ } readdir BINDIR ) {
        $bin =~ m/^bank_(.*)\.bin/;
        $binaries{ $1 } = {
                'name'	=> $bin,
                'size'	=> ( stat( "$dir/$bin" ) )[7],
                'dir'	=> $dir,
        };
    }
    close BINDIR;
    return \%binaries;
}

sub generate_basic_loader {
    my ( $layout, $outdir, $loading_screen ) = @_;
    my $bas_loader = $outdir . '/' . $basic_loader_name;

    # generate the lines first, we'll number them later
    my @lines;

    # Bank switch routine loads at address 0x8000, CLEAR to the byte before
    push @lines, sprintf( 'CLEAR VAL "%d"', 0x7FFF );

    # if we want an initial SCREEN$, generate loading code and disable output to screen
    if ( $loading_screen ) {
        push @lines, 'LOAD "" SCREEN$:POKE VAL "23739", VAL "111"';
    }

    # load bank switching code at 0x8000 (32768)
    # bank variable is at 0x8000, code switching entry point at 0x8001
    push @lines, 'LOAD "" CODE';

    # switch to each bank with the bank switching routine and load each bank content at 0xC000
    foreach my $bank ( sort keys %$layout ) {
        push @lines, sprintf( 'POKE VAL "%d", VAL "%d" : RANDOMIZE USR VAL "%d" : LOAD "" CODE', 0x8000, $bank, 0x8001 );
    }

    # switch back to bank 0
    push @lines, sprintf( 'POKE VAL "%d", VAL "%d" : RANDOMIZE USR VAL "%d"', 0x8000, 0, 0x8001 );

    # load main program code at 0x8184 and start execution
    my $main_code_start = 0x8184;
    push @lines, sprintf( 'LOAD "" CODE : RANDOMIZE USR VAL "%d"', $main_code_start );

    # that's it, output the BASIC program
    open my $bas_h, ">", $bas_loader
        or die "\n** Error: could not open $bas_loader for writing\n";
    my $line_number = 10;
    foreach my $line ( @lines ) {
        printf $bas_h "%3d %s\n", $line_number, $line;
        $line_number += 10;
    }
}

##
## Main
##

# parse command options
# -i and -o: input bin dir and output file
# -s: add instructions to load an initial SCREEN$ (optional)
our( $opt_i, $opt_o, $opt_s );
getopts("i:o:");
( defined( $opt_i ) and defined( $opt_o ) ) or
    die "usage: $0 -i <dataset_bin_dir> -o <output_dir> [-s]\n";

my $loading_screen = $opt_s;

# if $lowmem_output_dir is not specified, use same as $output_dir
my ( $input_dir, $output_dir ) = ( $opt_i, $opt_o );

my $bins = gather_bank_binaries( $input_dir );

generate_basic_loader( $bins, $output_dir, $loading_screen );

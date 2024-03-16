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

use FindBin;
use lib "$FindBin::Bin/../lib";

require RAGE::Config;

my $basic_loader_name = 'loader.bas';
my $asm_loader_name = 'asmloader.asm';

my $main_bin_filename = 'main_CODE.bin';

my $cfg = rage1_get_config();

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

sub get_main_bin_size {
    my @stat_results = stat( $main_bin_filename );
    return $stat_results[7];
}

# currently unused, I leave it here just in case
sub generate_basic_loader {
    my ( $layout, $outdir, $loading_screen ) = @_;
    my $bas_loader = $outdir . '/' . $basic_loader_name;

    # generate the lines first, we'll number them later
    my @lines;

    # Bank switch routine loads at address 0x8000, CLEAR to the byte before
    push @lines, sprintf( 'CLEAR VAL "%d"', 0x7FFF );

    # if we want an initial SCREEN$, generate loading code and disable output to screen
    if ( $loading_screen ) {
        push @lines, 'BORDER VAL "0": PAPER VAL "0": INK VAL "0": CLS';
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

    # load main program code at base code address and start execution
    my $main_code_start = ( $cfg->{'interrupts_128'}{'base_code_address'} =~ /^0x/ ?
        hex( $cfg->{'interrupts_128'}{'base_code_address'} ) :
        $cfg->{'interrupts_128'}{'base_code_address'}
    );
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

sub generate_assembler_loader {
    my ( $layout, $outdir ) = @_;
    my $asm_loader = $outdir . '/' . $asm_loader_name;

    my @lines;

    push @lines, <<EOF_HEADER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; This file has been generated automatically, do not edit!
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

EOF_HEADER
;

    push @lines, "\torg 0x8000";
    push @lines, "\tdefc LD_BYTES = 1366\t;; ROM routine";
    push @lines, "\textern bswitch";
    push @lines, "";
    push @lines, "\t;; do all loads with interrupts disabled so that bank 7 is not";
    push @lines, "\t;; corrupted by +3DOS at address 0xD200";
    push @lines, "\tdi";
    push @lines, "";

    # switch to each bank with the bank switching routine and load each bank content at 0xC000
    foreach my $bank ( sort keys %$layout ) {
        push @lines, "\tld a,$bank\t\t;; switch to bank $bank";
        push @lines, "\tcall bswitch";
        push @lines, "\tld a,0xff\t;; load data operation";
        push @lines, sprintf( "\tld de,%d\t;; number of bytes to load", $layout->{ $bank }{'size'} );
        push @lines, "\tld ix,0xc000\t;; destination address";
        push @lines, "\tscf";
        push @lines, "\tcall LD_BYTES\t;; load block";
        push @lines, "";
    }

    # switch back to bank 0
    push @lines, "\t;; switch to bank 0 and load main binary";
    push @lines, "\txor a";
    push @lines, "\tcall bswitch";
    push @lines, "";

    # load main program code at base code address and start execution
    my $main_code_start = ( $cfg->{'interrupts_128'}{'base_code_address'} =~ /^0x/ ?
        hex( $cfg->{'interrupts_128'}{'base_code_address'} ) :
        $cfg->{'interrupts_128'}{'base_code_address'}
    );
    push @lines, "\tld a,0xff";
    push @lines, sprintf( "\tld de,%d", get_main_bin_size );
    push @lines, "\tld ix,$main_code_start";
    push @lines, "\tscf";
    push @lines, "\tcall LD_BYTES";
    push @lines, "";

    push @lines, "\t;; Start execution";
    push @lines, "\tdi";
    push @lines, "\tjp $main_code_start";
    push @lines, "\t;; shouldn't return";

    push @lines, <<EOF_BSWITCH

bswitch:
        ;; register A contains the bank to switch to
        and     0x07            ; get 3 low bits only
        ld      b,a             ; save for later
        ld      a,(0x5b5c)      ; get last value from SYS.BANKM
        and     0xf8            ; save 5 top bits
        or      b               ; mix new value with old
        ld      bc,0x7ffd       ; set the port number
        ld      (0x5b5c),a      ; ...store the new value to SYS.BANKM
        out     (c),a           ; ...and select the new bank
        ret                     ; back to BASIC
EOF_BSWITCH
;

    # that's it, output the BASIC program
    open my $asm, ">", $asm_loader
        or die "\n** Error: could not open $asm_loader for writing\n";
    foreach my $line ( @lines ) {
        printf $asm "%s\n", $line;
    }
}

##
## Main
##

# parse command options
# -i and -o: input bin dir and output file
# -s: add instructions to load an initial SCREEN$ (optional)
our( $opt_i, $opt_o, $opt_s );
getopts("i:o:s");
( defined( $opt_i ) and defined( $opt_o ) ) or
    die "usage: $0 -i <dataset_bin_dir> -o <output_dir> [-s]\n";

my $loading_screen = $opt_s;

# if $lowmem_output_dir is not specified, use same as $output_dir
my ( $input_dir, $output_dir ) = ( $opt_i, $opt_o );

my $bins = gather_bank_binaries( $input_dir );

#generate_basic_loader( $bins, $output_dir, $loading_screen );
generate_assembler_loader( $bins, $output_dir );

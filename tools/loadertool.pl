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

# filenames are relative to the GENERATED dir, normally 'build/generated'

my $basic_loader_name	= 'loader.bas';
my $asm_loader_name	= 'asmloader.asm';
my $game_config_name	= 'build/game_data/game_config/Game.gdata';
my $main_bin_filename	= 'main_CODE.bin';

my $cfg = rage1_get_config();

my $loader_org_48	= 0x5E00;
my $loader_org_128	= 0x8000;

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

# sub binaries are files under build/generated/ with names sub_<name>.bin
sub gather_sub_binaries {
    my ( $dir ) = @_;
    my %binaries;

    opendir BINDIR, $dir or
        die "** Error: could not open directory $dir for reading\n";
    foreach my $bin ( grep { /^sub_.*\.bin$/ } readdir BINDIR ) {
        $bin =~ m/^sub_(.*)\.bin/;
        $binaries{ $1 }{'name'}	= $bin;
        $binaries{ $1 }{'size'}	= ( stat( "$dir/$bin" ) )[7];
        $binaries{ $1 }{'dir'}	= $dir;
    }
    close BINDIR;

    opendir BINDIR, $dir or
        die "** Error: could not open directory $dir for reading\n";
    foreach my $bin ( grep { /^sub_.*\.bin\.zx0$/ } readdir BINDIR ) {
        $bin =~ m/^sub_(.*)\.bin.zx0/;
        $binaries{ $1 }{'compressed_name'}	= $bin;
        $binaries{ $1 }{'compressed_size'}	= ( stat( "$dir/$bin" ) )[7];
        $binaries{ $1 }{'dir'} 			= $dir;
    }
    close BINDIR;

    my $order = 0;
    open GAME_CONFIG, $game_config_name or
        die "** Error: could not open $game_config_name for reading\n";
    while ( my $line = <GAME_CONFIG> ) {
        chomp( $line );
        $line =~ s/^\s*//g;         # remove leading blanks
        $line =~ s/\/\/.*$//g;      # remove comments (//...)
        $line =~ s/\s*$//g;         # remove trailing blanks
        next if $line eq '';                # ignore blank lines
        if ( $line =~ /^SINGLE_USE_BLOB\s+(\w.*)$/ ) {
            # ARG1=val1 ARG2=va2 ARG3=val3...
            my $args = $1;
            my $item = {
                map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                split( /\s+/, $args )
            };
            my $org_address = $item->{'org_address'} || $item->{'load_address'};
            my $run_address = $item->{'run_address'} || $org_address;
            $binaries{ $item->{'name'} }{'load_address'} = $item->{'load_address'};
            $binaries{ $item->{'name'} }{'org_address'} = $org_address;
            $binaries{ $item->{'name'} }{'run_address'} = $run_address;
            $binaries{ $item->{'name'} }{'order'} = $order;
            $binaries{ $item->{'name'} }{'compress'} = $item->{'compress'} || 0;
            $order++;
        }
    }

    return \%binaries;
}

sub get_zx_target {
    open GAME_CONFIG, $game_config_name or
        die "** Error: could not open $game_config_name for reading\n";
    while ( my $line = <GAME_CONFIG> ) {
        chomp( $line );
        $line =~ s/^\s*//g;         # remove leading blanks
        $line =~ s/\/\/.*$//g;      # remove comments (//...)
        $line =~ s/\s*$//g;         # remove trailing blanks
        next if $line eq '';                # ignore blank lines
        if ( $line =~ /^ZX_TARGET\s+(\w+)$/ ) {
            # ARG1=val1 ARG2=va2 ARG3=val3...
            return $1;
        }
    }
    return '48'; # default
}

# get the size of the main.bin file
sub get_main_bin_size {
    my @stat_results = stat( $main_bin_filename );
    return $stat_results[7];
}

sub generate_assembler_loader {
    my ( $bank_bins, $sub_bins, $outdir ) = @_;
    my $asm_loader = $outdir . '/' . $asm_loader_name;

    my @lines;

    my $loader_org = ( get_zx_target eq '48' ? $loader_org_48 : $loader_org_128 );

    push @lines, <<EOF_HEADER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; This file has been generated automatically, do not edit!
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    org $loader_org
    defc LD_BYTES = 1366	;; ROM routine at 0x0556

    ;; do all loads with interrupts disabled so that bank 7 is not
    ;; corrupted by +3DOS at address 0xD200
    di
EOF_HEADER
;

    if ( get_zx_target eq '128' ) {
        # switch to each bank with the bank switching routine and load each bank content at 0xC000
        foreach my $bank ( sort keys %$bank_bins ) {
            my $bank_size = $bank_bins->{ $bank }{'size'};
            push @lines, <<EOF_BANK1
    ld a,$bank		;; switch to bank $bank
    call bswitch
    ld a,0xff		;; load data operation
    ld de,$bank_size	;; number of bytes to load
    ld ix,0xc000	;; destination address
    scf
    call LD_BYTES	;; load block
    jp nc,to_basic
EOF_BANK1
;
        }

        # switch back to bank 0
        push @lines, <<EOF_BANK0
    ;; switch to bank 0 and load main binary
    xor a
    call bswitch
EOF_BANK0
;
    }

    # load main program code at base code address and start execution
    my $main_code_start;
    if ( get_zx_target eq '128' ) {
        $main_code_start = ( $cfg->{'interrupts_128'}{'base_code_address'} =~ /^0x/ ?
            hex( $cfg->{'interrupts_128'}{'base_code_address'} ) :
            $cfg->{'interrupts_128'}{'base_code_address'}
        );
    } else {
        $main_code_start = 0x5F00;
    }
    my $main_size = get_main_bin_size;
    push @lines, <<EOF_LOAD_MAIN
    ld a,0xff
    ld de,$main_size
    ld ix,$main_code_start
    scf
    call LD_BYTES
    jp nc,to_basic
EOF_LOAD_MAIN
;

    # load each sub at its LOAD_ADDRESS
    # this sort must be according to the order in which the SUBs were
    # defined in the GAME_CONFIG
    foreach my $sub ( sort {
            $sub_bins->{ $a }{'order'} <=> $sub_bins->{ $b }{'order'}
            }keys %$sub_bins ) {

        my $sub_size = ( $sub_bins->{ $sub }{'compress'} ?
            $sub_bins->{ $sub }{'compressed_size'} :
            $sub_bins->{ $sub }{'size'}
        );
        my $sub_load_addr = $sub_bins->{ $sub }{'load_address'};
        push @lines, <<EOF_LOAD_SUB
    ;; Load SUB '$sub'
    ld a,0xff	;; load data operation
    ld de,$sub_size	;; number of bytes to load
    ld ix,$sub_load_addr	;; destination address
    scf
    call LD_BYTES	;; load block
    jp nc,to_basic
EOF_LOAD_SUB
;
    }

    # run each SUB in order
    # this sort must be according to the order in which the SUBs were
    # defined in the GAME_CONFIG
    my $some_subs_are_compressed = 0;
    my $some_subs_are_swapped = 0;
    foreach my $sub ( sort { 
            $sub_bins->{ $a }{'order'} <=> $sub_bins->{ $b }{'order'}
            } keys %$sub_bins ) {
        my $sub_load_addr = $sub_bins->{ $sub }{'load_address'};
        my $sub_org_addr = $sub_bins->{ $sub }{'org_address'};
        my $sub_run_addr = $sub_bins->{ $sub }{'run_address'};
        my $sub_size = $sub_bins->{ $sub }{'size'};
        push @lines, <<EOF_RUN_SUB1
    ;; Run SUB '$sub' with ints disabled
    di
EOF_RUN_SUB1
;

        if ( $sub_bins->{ $sub }{'compress'} ) {
            $some_subs_are_compressed++;
            push @lines, <<EOF_UNCOMPRESS
    ld de,$sub_org_addr	;; set src and dest for decompression
    ld hl,$sub_load_addr
    call dzx0_standard

    call $sub_run_addr	;; run SUB
EOF_UNCOMPRESS
;
        } else {
            if ( $sub_load_addr ne $sub_org_addr ) {
                $some_subs_are_swapped++;
                push @lines, <<EOF_RUN_SUB2
    ld de,$sub_org_addr	;; swap from $sub_load_addr to $sub_org_addr
    ld hl,$sub_load_addr
    ld bc,$sub_size
    call memswap
EOF_RUN_SUB2
;
            }
            push @lines, <<EOF_RUN_SUB3
    call $sub_run_addr	;; run SUB
EOF_RUN_SUB3
;
            if ( $sub_load_addr ne $sub_org_addr ) {
                push @lines, <<EOF_RUN_SUB4
    ld de,$sub_org_addr	;; swap it back
    ld hl,$sub_load_addr
    ld bc,$sub_size
    call memswap
EOF_RUN_SUB4
;
            }
        }
    }

    # transfer control to main
    push @lines, <<EOF_JP_MAIN
    ;; Start execution
    di
    jp $main_code_start
EOF_JP_MAIN
;

    # output auxiliary functions for 128 mode
    if ( get_zx_target eq '128' ) {
        push @lines, <<EOF_BSWITCH
;; Switch memory bank at 0xC000
;;   A = bank to activate (0-7)
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
    ret
EOF_BSWITCH
;
    }

    # output memswap function if needed
    if ( $some_subs_are_swapped ) {
        push @lines, <<EOF_MEMSWAP
;; Swap memory blocks
;;   BC = size
;;   DE = dst
;;   HL = src
memswap:
memswap_loop:
    ld a,(de)
    ldi
    dec hl
    ld (hl),a
    inc hl
    jp PE,memswap_loop
    ret
EOF_MEMSWAP
;
    }

    # output decompress function if needed
    if ( $some_subs_are_compressed ) {
        push @lines, <<EOF_COMPRESS
; -----------------------------------------------------------------------------
; ZX0 decoder by Einar Saukas
; "Standard" version (69 bytes only)
; -----------------------------------------------------------------------------
; Parameters:
;   HL: source address (compressed data)
;   DE: destination address (decompressing)
; -----------------------------------------------------------------------------

dzx0_standard:
        ld      bc, 0xffff               ; preserve default offset 1
        push    bc
        inc     bc
        ld      a, 0x80
dzx0s_literals:
        call    dzx0s_elias             ; obtain length
        ldir                            ; copy literals
        add     a, a                    ; copy from last offset or new offset?
        jr      c, dzx0s_new_offset
        call    dzx0s_elias             ; obtain length
dzx0s_copy:
        ex      (sp), hl                ; preserve source, restore offset
        push    hl                      ; preserve offset
        add     hl, de                  ; calculate destination - offset
        ldir                            ; copy from offset
        pop     hl                      ; restore offset
        ex      (sp), hl                ; preserve offset, restore source
        add     a, a                    ; copy from literals or new offset?
        jr      nc, dzx0s_literals
dzx0s_new_offset:
        call    dzx0s_elias             ; obtain offset MSB
        ex      af, af'
        pop     af                      ; discard last offset
        xor     a                       ; adjust for negative offset
        sub     c
        ret     z                       ; check end marker
        ld      b, a
        ex      af, af'
        ld      c, (hl)                 ; obtain offset LSB
        inc     hl
        rr      b                       ; last offset bit becomes first length bit
        rr      c
        push    bc                      ; preserve new offset
        ld      bc, 1                   ; obtain length
        call    nc, dzx0s_elias_backtrack
        inc     bc
        jr      dzx0s_copy
dzx0s_elias:
        inc     c                       ; interlaced Elias gamma coding
dzx0s_elias_loop:
        add     a, a
        jr      nz, dzx0s_elias_skip
        ld      a, (hl)                 ; load another group of 8 bits
        inc     hl
        rla
dzx0s_elias_skip:
        ret     c
dzx0s_elias_backtrack:
        add     a, a
        rl      c
        rl      b
        jr      dzx0s_elias_loop
; -----------------------------------------------------------------------------
EOF_COMPRESS
;
    }

    # output auxiliary function for 128 mode
    push @lines, <<EOF_RETBAS
;; Return to BASIC
to_basic:
    ei
    ret
EOF_RETBAS
;

    # that's it, output the ASM program
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

my $bank_bins = gather_bank_binaries( $input_dir );
my $sub_bins = gather_sub_binaries( $input_dir );

generate_assembler_loader( $bank_bins, $sub_bins, $output_dir );

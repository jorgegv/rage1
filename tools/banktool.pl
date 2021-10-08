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

# list of valid banks and size for 128K Speccy
my @valid_banks = ( 1, 3, 4, 6, 7 );
my $max_bank_size = 16384;

# config vars
my $bank_binaries_name_format = 'bank_%d.bin';
my $bank_config_name = 'bank_bins.cfg';
my $dataset_info_name = 'dataset_info.asm';
my $codeset_info_name = 'codeset_info.asm';
my $basic_loader_name = 'loader.bas';

# auxiliary functions

sub gather_datasets {
    my ( $dir, $ext ) = @_;
    my %binaries;

    opendir BINDIR, $dir or
        die "** Error: could not open directory $dir for reading\n";
    foreach my $bin ( grep { /^dataset_.*\Q$ext\E/ } readdir BINDIR ) {
        $bin =~ m/dataset_(.*)\Q$ext\E/;
        $binaries{ $1 } = {
                'name'	=> $bin,
                'size'	=> ( stat( "$dir/$bin" ) )[7],
        };
    }
    close BINDIR;
    return \%binaries;
}

# FIXME: make this reall gather codesets
sub gather_codesets {
    my ( $dir, $ext ) = @_;
    my %binaries;

    opendir BINDIR, $dir or
        die "** Error: could not open directory $dir for reading\n";
    foreach my $bin ( grep { /^dataset_.*\Q$ext\E/ } readdir BINDIR ) {
        $bin =~ m/dataset_(.*)\Q$ext\E/;
        $binaries{ $1 } = {
                'name'	=> $bin,
                'size'	=> ( stat( "$dir/$bin" ) )[7],
        };
    }
    close BINDIR;
    return \%binaries;
}

sub layout_binaries {
    my $bins = shift;
    my $layout;

    # start with the first bank, place the binaries on the current bank
    # until it is full, then continue with the next until no more banks o no
    # more binaries left

    my $current_bank_index = 0;
    foreach my $bk ( sort keys %$bins ) {
        my $bin = $bins->{ $bk };
        # just error if any dataset is too big
        if ( $bin->{'size'} > $max_bank_size ) {
            die "** Error: dataset $bin->{name} is too big ($bin->{size}), it does not fit in a bank ($max_bank_size)\n";
        }

        # check if we need to spill to the next bank
        my $current_size = $layout->{ $valid_banks[ $current_bank_index ] }{'size'} || 0;
        if ( $current_size + $bin->{'size'} > $max_bank_size ) {
            $current_bank_index++;
            if ( $current_bank_index >= scalar( @valid_banks ) ) {
                die "** Error: no more banks to fill, datasets are too big\n";
            }
        }

        # add the bank and offset info to the dataset. Offset is the curent pos in the bank
        $bin->{'bank'} = $valid_banks[ $current_bank_index ];
        $bin->{'offset'} = $layout->{ $valid_banks[ $current_bank_index ] }{'size'} || 0;

        # then update the bank layout
        push @{ $layout->{ $valid_banks[ $current_bank_index ] }{'binaries'} }, $bin;
        $layout->{ $valid_banks[ $current_bank_index ] }{'size'} += $bin->{'size'};
    }

    return $layout;
}

sub generate_bank_binaries {
    my ( $layout, $indir, $outdir ) = @_;

    foreach my $bank ( sort keys %$layout ) {
        my $bank_binary = $outdir . '/' . sprintf( $bank_binaries_name_format, $bank );

        open my $bank_out, '>', $bank_binary or
            die "\n** Error: could not open $bank_binary for writing\n";
        binmode $bank_out;

        print "  Writing " . sprintf( $bank_binaries_name_format, $bank ) . "...";
        foreach my $bin ( @{ $layout->{ $bank }{'binaries'} } ) {
            my $in = "$indir/$bin->{'name'}";
            open my $bin_in, "<", $in or
                die "\n** Error: could not open $in for reading\n";
            binmode $bin_in;
            my $data;
            while ( read( $bin_in, $data, 1024 ) ) {
                print $bank_out $data;
            }
            close $bin_in;
        }
        close $bank_out;
        my $bytes = (stat( $bank_binary ))[7];
        print "OK [$bytes bytes]\n";
        $layout->{ $bank }{'binary'} = $bank_binary;
    }
}

sub generate_bank_config {
    my ( $layout, $outdir ) = @_;
    my $bankcfg = $outdir . '/' . $bank_config_name;

    print "  Generating $bank_config_name...";

    open my $bankcfg_h, ">", $bankcfg
        or die "\n** Error: could not open $bankcfg for writing\n";
    print $bankcfg_h join("\n", map { $layout->{ $_ }{'binary'} } sort keys %$layout );
    print $bankcfg_h "\n";
    close $bankcfg_h;
    print "OK\n";
}

sub generate_dataset_info_code_asm {
    my ( $layout, $datasets, $outdir ) = @_;
    my $dsmap = $outdir . '/' . $dataset_info_name;

    print "  Generating $dataset_info_name...";

    open my $dsmap_h, ">", $dsmap
        or die "\n** Error: could not open $dsmap for writing\n";
    my $num_datasets = scalar( keys %$datasets );
    print $dsmap_h <<EOF_DSMAP_3
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Dataset Map: for a given dataset ID, maps the memory bank where it is
;; stored, and the start address on that bank
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; struct dataset_info_s dataset_info[ $num_datasets ] = { ... }
;;

section         code_crt_common

public		_dataset_info

_dataset_info:
EOF_DSMAP_3
;

    print $dsmap_h join( "\n",
        map {
            sprintf( "\t\t;; dataset %d\n\t\tdb\t%d\t;; bank number\n\t\tdw\t%d\t;; size\n\t\tdw\t%d\t;; offset into bank\n",
                $_,
                $datasets->{ $_ }{'bank'},
                $datasets->{ $_ }{'size'},
                $datasets->{ $_ }{'offset'} );
        } sort keys %$datasets
    );

    close $dsmap_h;
    print "OK\n";
}

sub generate_codeset_info_code_asm {
    my ( $layout, $codesets, $outdir ) = @_;
    my $csmap = $outdir . '/' . $codeset_info_name;
    my $num_codesets = scalar( @$codesets );

    print "  Generating $codeset_info_name...";

    open my $csmap_h, ">", $csmap
        or die "\n** Error: could not open $csmap for writing\n";
    print $csmap_h <<EOF_CSMAP_3
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Codeset Map: for a given codeset ID, maps the memory bank where it is
;; stored
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; struct codeset_info_s codeset_info[ $num_codesets ] = { ... }
;;

section         code_crt_common

public		_codeset_info

_codeset_info:
EOF_CSMAP_3
;

#    print $dsmap_h join( "\n",
#        map {
#            sprintf( "\t\t;; dataset %d\n\t\tdb\t%d\t;; bank number\n\t\tdw\t%d\t;; size\n\t\tdw\t%d\t;; offset into bank\n",
#                $_,
#                $datasets->{ $_ }{'bank'},
#                $datasets->{ $_ }{'size'},
#                $datasets->{ $_ }{'offset'} );
#        } sort keys %$datasets
#    );

    close $csmap_h;
    print "OK\n";
}

sub generate_basic_loader {
    my ( $layout, $outdir ) = @_;
    my $bas_loader = $outdir . '/' . $basic_loader_name;

    print "  Generating custom BASIC loader...";

    # generate the lines first, we'll number them later
    my @lines;

    # Bank switch routine loads at address 0x8000, CLEAR to the byte before
    push @lines, sprintf( 'CLEAR VAL "%d"', 0x7FFF );

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
    print "OK\n";
}

##
## Main
##

# parse command options
our( $opt_i, $opt_o, $opt_b, $opt_s, $opt_l );
getopts("i:o:b:s:l:");
( defined( $opt_i ) and defined( $opt_o ) ) or
    die "usage: $0 -i <dataset_bin_dir> -o <output_dir> -s <bank_switcher_binary> [-b <.bin_ext>] [-l <lowmem_output_dir>]\n";

# if $lowmem_output_dir is not specified, use same as $output_dir
my ( $input_dir, $output_dir, $lowmem_output_dir ) = ( $opt_i, $opt_o, $opt_l || $opt_o );
my $bin_ext = $opt_b || '.bin';

my $bank_switcher_binary = $opt_s;

my $datasets = gather_datasets( $input_dir, $bin_ext );
if ( not scalar( keys %$datasets ) ) {
    die "** Error: no dataset binaries found in $input_dir\n";
}

my $codesets = gather_codesets( $input_dir, $bin_ext );
if ( not scalar( keys %$codesets ) ) {
    die "** Error: no codeset binaries found in $input_dir\n";
}

my $bank_layout = layout_binaries( $datasets );

generate_bank_binaries( $bank_layout, $input_dir, $output_dir );

generate_bank_config( $bank_layout, $output_dir );

generate_dataset_info_code_asm( $bank_layout, $datasets, $lowmem_output_dir );

generate_codeset_info_code_asm( $bank_layout, $codesets, $lowmem_output_dir );

generate_basic_loader( $bank_layout, $output_dir );

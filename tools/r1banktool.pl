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
my $bank_config_name = 'banks.cfg';
my $dataset_map_name = 'dataset_map.c';

# auxiliary functions

sub gather_datasets {
    my ( $dir, $ext ) = @_;
    my %binaries;

    opendir BINDIR, $dir or
        die "Could not open directory $dir for reading\n";
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
        my $current_size = $layout->{ $valid_banks[ $current_bank_index ] }{'size'} || 0;
        if ( $current_size + $bin->{'size'} > $max_bank_size ) {
            $current_bank_index++;
            if ( $current_bank_index > scalar( @valid_banks ) ) {
                die "** Error: no more banks to fill, datasets are too big\n";
            }
        }
        # add the bank and offset info to the dataset. Offset is the curent pos in the bank
        $bins->{ $bk }{'bank'} = $valid_banks[ $current_bank_index ];
        $bins->{ $bk }{'offset'} = $layout->{ $valid_banks[ $current_bank_index ] }{'size'} || 0;
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
            die "** Error: could not open $bank_binary for writing\n";
        binmode $bank_out;

        print "Writing " . sprintf( $bank_binaries_name_format, $bank ) . "...";
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
        print " OK [$bytes bytes]\n";
    }
}

sub generate_bank_config {
    my ( $layout, $outdir ) = @_;
    my $bankcfg = $outdir . '/' . $bank_config_name;
    open my $bankcfg_h, ">", $bankcfg
        or die "** Error: could not open $bankcfg for writing\n";
    print "Generating $bank_config_name...";
    print $bankcfg_h join("\n", sort keys %$layout );
    print $bankcfg_h "\n";
    close $bankcfg_h;
    print " OK\n";
}

sub generate_dataset_map_code {
    my ( $layout, $datasets, $outdir ) = @_;
    my $dsmap = $outdir . '/' . $dataset_map_name;
    open my $dsmap_h, ">", $dsmap
        or die "** Error: could not open $dsmap for writing\n";
    print "Generating $dataset_map_name...";

    my $num_datasets = scalar( keys %$datasets );
    print $dsmap_h <<EOF_DSMAP_1
#include "rage1/dataset.h"

//////////////////////////////////////////////////////////////////////////
// Dataset Map: for a given dataset ID, maps the memory bank where it is
// stored, and the start address on that bank
//////////////////////////////////////////////////////////////////////////

struct dataset_map_s dataset_map[ $num_datasets ] = {
EOF_DSMAP_1
;

    print $dsmap_h join( ",\n",
        map {
            sprintf( "\t{ .bank_num = %d, .offset = %d }",
                $datasets->{ $_ }{'bank'},
                $datasets->{ $_ }{'offset'} );
        } sort keys %$datasets
    );
    print $dsmap_h <<EOF_DSMAP_2

};

EOF_DSMAP_2
;
    close $dsmap_h;
    print " OK\n";
}

sub generate_basic_loader {
    my ( $layout, $outdir ) = @_;

    # BASIC pseudo code:
    # CLEAR something
    # load bank switching code snippet at 0x8000 - LOAD "" CODE 32768
    # foreach bank:
    #   POKE bank number into 0x8000
    #   RANDOMIZE USR 0x8001
    #   LOAD "" CODE 49152 (0xC000)
    # restore home bank
    # LOAD "" CODE for the main program
    # RANDOMIZE USR 0x81xx
}

##
## Main
##

# parse command options
our( $opt_i, $opt_o, $opt_b );
getopts("i:o:b:");
( defined( $opt_i ) and defined( $opt_o ) ) or
    die "usage: $0 -i <dataset_bin_dir> -o <output_dir> [-b <.bin_ext>]\n";

my ( $input_dir, $output_dir ) = ( $opt_i, $opt_o );
my $bin_ext = $opt_b || '.bin';

my $datasets = gather_datasets( $input_dir, $bin_ext );
if ( not scalar( keys %$datasets ) ) {
    die "** Error: no dataset binaries found in $input_dir\n";
}

my $bank_layout = layout_binaries( $datasets );
#print Dumper( $bank_layout );

generate_bank_binaries( $bank_layout, $input_dir, $output_dir );

generate_bank_config( $bank_layout, $output_dir );

generate_dataset_map_code( $bank_layout, $datasets, $output_dir );

generate_basic_loader( $bank_layout, $output_dir );

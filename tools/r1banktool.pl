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

# binaries layout
my $layout;

# auxiliary functions

sub gather_binaries {
    my ( $dir, $ext ) = @_;
    my @binaries;

    opendir BINDIR, $dir or
        die "Could not open directory $dir for reading\n";
    @binaries = map {
        {
            'name' => $_,
            'size' => ( stat( "$dir/$_" ) )[7],
        }
    } grep {
        /^dataset_.*\Q$ext\E/
    } readdir BINDIR;
    close BINDIR;
    return \@binaries;
}

sub layout_binaries {
    my $bins = shift;

    # start with the first bank, place the binaries on the current bank
    # until it is full, then continue with the next until no more banks o no
    # more binaries left

    my $current_bank_index = 0;
    foreach my $bin ( @$bins ) {
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
        push @{ $layout->{ $valid_banks[ $current_bank_index ] }{'binaries'} }, $bin;
        $layout->{ $valid_banks[ $current_bank_index ] }{'size'} += $bin->{'size'};
    }
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

my $bins = gather_binaries( $input_dir, $bin_ext );
if ( not scalar( @$bins ) ) {
    die "** Error: no dataset binaries found in $input_dir\n";
}

layout_binaries( $bins );
print Dumper( $layout );
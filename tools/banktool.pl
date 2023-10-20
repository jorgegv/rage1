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
my @dataset_valid_banks = ( 1, 3, 7 );	# contended banks reserved for data
# banks reserved for codesets. Bank 4 is reserved for engine code
my @codeset_valid_banks = ( 6, );       # non-contended

my $max_bank_size = 16384;

# config vars
my $bank_binaries_name_format = 'bank_%d.bin';
my $bank_config_name = 'bank_bins.cfg';
my $dataset_info_name = 'dataset_info.asm';
my $codeset_info_name = 'codeset_info.asm';
my $basic_loader_name = 'loader.bas';

# auxiliary functions

# datasets are files under build/generated/datasets/ with names dataset_N.bin
sub gather_datasets {
    my ( $dir, $ext ) = @_;
    my %binaries;

    opendir BINDIR, $dir or
        die "** Error: could not open directory $dir for reading\n";
    foreach my $bin ( grep { /^dataset_.*\Q$ext\E/ } readdir BINDIR ) {
        $bin =~ m/dataset_(.*)\Q$ext\E/;
        $binaries{ $1 } = {
                'dataset_num'	=> $1,
                'name'		=> $bin,
                'size'		=> ( stat( "$dir/$bin" ) )[7],
                'dir'		=> $dir,
        };
    }
    close BINDIR;
    return \%binaries;
}

# codesets are files under build/generated/codesets/ with names codeset_N.bin
sub gather_codesets {
    my ( $dir, $ext ) = @_;
    my %binaries;

    opendir BINDIR, $dir or
        die "** Error: could not open directory $dir for reading\n";
    foreach my $bin ( grep { /^codeset_.*\Q$ext\E/ } readdir BINDIR ) {
        $bin =~ m/codeset_(.*)\Q$ext\E/;
        $binaries{ $1 } = {
                'codeset_num'	=> $1,
                'name'		=> $bin,
                'size'		=> ( stat( "$dir/$bin" ) )[7],
                'dir'		=> $dir,
        };
    }
    close BINDIR;
    return \%binaries;
}

sub layout_dataset_binaries {
    my ( $layout, $bins ) = @_;


    # start with the first bank, place the binaries on the current bank
    # until it is full, then continue with the next until no more banks o no
    # more binaries left

    my $current_bank_index = 0;
    foreach my $bk ( sort { $a <=> $b } keys %$bins ) {
        my $bin = $bins->{ $bk };
        # just error if any dataset is too big
        if ( $bin->{'size'} > $max_bank_size ) {
            die "** Error: dataset $bin->{name} is too big ($bin->{size}), it does not fit in a bank ($max_bank_size)\n";
        }

        # check if we need to spill to the next bank
        my $current_size = $layout->{ $dataset_valid_banks[ $current_bank_index ] }{'size'} || 0;
        if ( $current_size + $bin->{'size'} > $max_bank_size ) {
            $current_bank_index++;
            if ( $current_bank_index >= scalar( @dataset_valid_banks ) ) {
                die "** Error: no more banks to fill, datasets are too big\n";
            }
        }

        # add the bank and offset info to the dataset. Offset is the curent pos in the bank
        $bin->{'bank'} = $dataset_valid_banks[ $current_bank_index ];
        $bin->{'offset'} = $layout->{ $dataset_valid_banks[ $current_bank_index ] }{'size'} || 0;

        # then update the bank layout
        push @{ $layout->{ $dataset_valid_banks[ $current_bank_index ] }{'binaries'} }, $bin;
        $layout->{ $dataset_valid_banks[ $current_bank_index ] }{'size'} += $bin->{'size'};
        $layout->{ $dataset_valid_banks[ $current_bank_index ] }{'type'} = 'dataset';
    }
}

sub layout_codeset_binaries {
    my ( $layout, $bins ) = @_;

    # a codeset is directly assigned to a bank
    my $current_bank_index = 0;
    foreach my $bk ( sort { $a <=> $b } keys %$bins ) {
        my $bin = $bins->{ $bk };

        # just error if any codeset is too big
        if ( $bin->{'size'} > $max_bank_size ) {
            die "** Error: codesetset $bin->{name} is too big ($bin->{size}), it does not fit in a bank ($max_bank_size)\n";
        }

        # check if there are banks left
        if ( $current_bank_index >= scalar( @codeset_valid_banks ) ) {
            die "** Error: no more banks to fill, too many codesets\n";
        }

        # add the bank info to the codeset and update the bank layout
        $bin->{'bank'} = $codeset_valid_banks[ $current_bank_index ];
        push @{ $layout->{ $codeset_valid_banks[ $current_bank_index ] }{'binaries'} }, $bin;
        $layout->{ $codeset_valid_banks[ $current_bank_index ] }{'size'} += $bin->{'size'};
        $layout->{ $codeset_valid_banks[ $current_bank_index ] }{'type'} = 'codeset';

        # update used bank index
        $current_bank_index++;
    }
}

sub generate_bank_binaries {
    my ( $layout, $outdir ) = @_;

    foreach my $bank ( sort { $a <=> $b } keys %$layout ) {
        my $bank_binary = $outdir . '/' . sprintf( $bank_binaries_name_format, $bank );

        open my $bank_out, '>', $bank_binary or
            die "\n** Error: could not open $bank_binary for writing\n";
        binmode $bank_out;

        print "  Writing " . sprintf( $bank_binaries_name_format, $bank ) . "...";
        foreach my $bin ( @{ $layout->{ $bank }{'binaries'} } ) {
            my $in = "$bin->{'dir'}/$bin->{'name'}";
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

    print $bankcfg_h "# <type> <bank_num> <path> <codesets/datasets>\n";

    foreach my $bank ( sort { $a <=> $b } keys %$layout ) {
        my $ids;
        if ( $layout->{ $bank }{'type'} eq 'dataset' ) {
            $ids = join( " ", map { $_->{'dataset_num' } } @{ $layout->{ $bank }{'binaries'} } );
        } elsif ( $layout->{ $bank }{'type'} eq 'codeset' ) {
            $ids = join( " ", map { $_->{'codeset_num' } } @{ $layout->{ $bank }{'binaries'} } );
        } else {
            die "BANK $bank: unknown type $layout->{ $bank }{'type'}\n";
        }
        printf $bankcfg_h "%s %d %s %s\n", $layout->{ $bank }{'type'}, $bank, $layout->{ $bank }{'binary'}, $ids;
    }
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
        } sort { $a <=> $b } keys %$datasets
    );

    close $dsmap_h;
    print "OK\n";
}

##
## Main
##

# parse command options
our( $opt_i, $opt_o, $opt_b, $opt_s, $opt_l, $opt_c );
getopts("i:o:s:l:c:");
( defined( $opt_i ) and defined( $opt_o ) and defined( $opt_c ) ) or
    die "usage: $0 -i <dataset_bin_dir> -c <codeset_bin_dir> -o <output_dir> -s <bank_switcher_binary> [-l <lowmem_output_dir>]\n";

# if $lowmem_output_dir is not specified, use same as $output_dir
my ( $input_dir_ds, $input_dir_cs, $output_dir, $lowmem_output_dir ) = ( $opt_i, $opt_c, $opt_o, $opt_l || $opt_o );

my $bank_switcher_binary = $opt_s;

my $datasets = gather_datasets( $input_dir_ds, '.zx0' );
if ( not scalar( keys %$datasets ) ) {
    die "** Error: no dataset binaries found in $input_dir_ds\n";
}

my $codesets = gather_codesets( $input_dir_cs, '.bin' );
# there may be _no_ codesets after all, so no error in that case

my $bank_layout = { };
layout_dataset_binaries( $bank_layout, $datasets );
layout_codeset_binaries( $bank_layout, $codesets );

generate_bank_binaries( $bank_layout, $output_dir );

generate_bank_config( $bank_layout, $output_dir );

generate_dataset_info_code_asm( $bank_layout, $datasets, $lowmem_output_dir );

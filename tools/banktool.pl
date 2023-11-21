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
use Algorithm::FastPermute qw( permute );

# The following two lists must have the same elements, and show the
# preference for storing elements in them.  Data/code is stored in each bank
# starting by the first one on the relevant list

# banks allowed for codesets. All allowed, but non-contended are listed first
my @codeset_valid_banks = ( 6, 1, 3, 7 );

# banks allowed for datasets. All allowed, but contended are listed first
my @dataset_valid_banks = ( 1, 3, 7, 6 );

my $num_available_banks = scalar( @codeset_valid_banks );	# @dataset_vbalid_banks should be valid also

my $max_bank_size = 16384;

# global var for the computed layout
my $layout;

# config vars
my $bank_binaries_name_format = 'bank_%d.bin';
my $bank_config_name = 'bank_bins.cfg';
my $dataset_info_name = 'dataset_info.asm';
my $codeset_info_name = 'codeset_info.asm';
my $basic_loader_name = 'loader.bas';

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

# gather datasets
# datasets are files under build/generated/datasets/ with names dataset_N.bin
my @all_datasets;
opendir BINDIR, $input_dir_ds or
    die "** Error: could not open directory $input_dir_ds for reading\n";
foreach my $bin ( grep { /^dataset_.*\.zx0$/ } readdir BINDIR ) {
    $bin =~ m/dataset_(.*)\.zx0$/;
    $all_datasets[ $1 ] = {
            'name'		=> $bin,
            'size'		=> ( stat( "$input_dir_ds/$bin" ) )[7],
            'dir'		=> $input_dir_ds,
    };
}
close BINDIR;

# gather codesets
# codesets are files under build/generated/codesets/ with names codeset_N.bin
my @all_codesets;
opendir BINDIR, $input_dir_cs or
    die "** Error: could not open directory $input_dir_cs for reading\n";
foreach my $bin ( grep { /^codeset_.*\.bin$/ } readdir BINDIR ) {
    $bin =~ m/codeset_(.*)\.bin$/;
    $all_codesets[ $1 ] = {
            'name'		=> $bin,
            'size'		=> ( stat( "$input_dir_cs/$bin" ) )[7],
            'dir'		=> $input_dir_cs,
    };
}
close BINDIR;

# setup the bank structure
my @banks;
foreach my $i ( 0 .. $num_available_banks - 1 ) {
    $banks[ $i ] = { 'binaries' => [], 'size' => 0 };
}

# layout codeset binaries
# a codeset is directly assigned to the start of a bank
my $current_bank_index = 0;
foreach my $bk ( 0 .. scalar( @all_codesets ) - 1 ) {
    my $bin = $all_codesets[ $bk ];

    # just error if any codeset is too big
    if ( $bin->{'size'} > $max_bank_size ) {
        die "** Error: codesetset $bin->{name} is too big ($bin->{size}), it does not fit in a bank ($max_bank_size)\n";
    }

    # check if there are banks left
    if ( $current_bank_index >= $num_available_banks ) {
        die "** Error: no more banks to fill, too many codesets\n";
    }

    # add the bank info to the codeset and update the bank layout
    $bin->{'bank'} = $current_bank_index;
    push @{ $banks[ $current_bank_index ]{'binaries'} }, $bin;
    $banks[ $current_bank_index ]{'size'} += $bin->{'size'};

    # update used bank index
    $current_bank_index++;
}

my @initial_bank_sizes = map { $_->{'size'} } @banks;
my @dataset_sizes = map { $_->{'size'} } @all_datasets;

# layout dataset binaries

# Since the number of datasets is normally small ( <= 10 ), we can explore
# the full list of permutations of datasets until we find one permutation
# that fills in the banks with the proper restrictions.  For 10 datasets,
# it's 3.6M permutations (10!).  It can take a bit to check, but it's
# definitely within the capabilities of current hosts.

# aux function: receives a listref to a permutation of the dataset indexes
# it returns ok if the permutation makes the dataset fit in the number of
# available banks
sub do_dataset_layout {
    my $list = shift;
    my @list = @{$list};

    # setup buckets
    my @buckets = map { { size => $_->{'size'} } } @banks;

    # setup first bank with codeset initial size
    my $current_bucket = 0;
    # now process all the datasets
    foreach my $ds ( @list ) {
        if ( $dataset_sizes[ $ds ] <= $max_bank_size - $buckets[ $current_bucket ]{'size'} ) {
            push @{ $buckets[ $current_bucket ]{'datasets'} }, $ds;
            $buckets[ $current_bucket ]{'size'} += $dataset_sizes[ $ds ];
        } else {
            $current_bucket++;
            push @{ $buckets[ $current_bucket ]{'datasets'} }, $ds;
            $buckets[ $current_bucket ]{'size'} = $dataset_sizes[ $ds ];
        }
    }

    # all processed, now check
    return \@buckets;
}

my @dataset_indexes;
my $dataset_layout;
my @indexes = ( 0 .. scalar( @all_datasets ) - 1 );
permute {
    if ( not scalar( @dataset_indexes ) ) {
        my $layout = do_dataset_layout( \@indexes );
        if ( scalar( @$layout ) <= $num_available_banks ) {
            @dataset_indexes = @indexes;	# found
            $dataset_layout = $layout;
        }
    }
} @indexes;

scalar( @dataset_indexes ) or
    die "There is no dataset layout possible within the available memory banks\n";

printf "Selected dataset permutation: [ %s ]\n", join( ', ', @dataset_indexes );
foreach my $i ( 0 .. scalar( @$dataset_layout ) - 1 ) {
    printf "Bank %d: ", $i;
    if ( $initial_bank_sizes[ $i ] ) {
        printf "CS-%d(%db), ", $i, $initial_bank_sizes[ $i ];
    }
    print join( ", ", map { sprintf( "DS-%s(%db)", $_, $all_datasets[ $_ ]{'size'} ) } @{ $dataset_layout->[ $i ]{'datasets'} } );
    printf " - FINAL SIZE: %db\n", $dataset_layout->[ $i ]{'size'};
}
exit;
__END__

my $current_bank_index = 0;

foreach my $bk ( sort { $bins->{ $a }{'size'} <=> $bins->{ $b }{'size'} } keys %$bins ) {
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
        # if the bank already has a 'type' field, it is a codeset bank, so set the type to 'mixed'
        if ( defined( $layout->{ $dataset_valid_banks[ $current_bank_index ] }{'type'} ) ) {
            $layout->{ $dataset_valid_banks[ $current_bank_index ] }{'type'} = 'mixed';
        }
    }

    # add the bank and offset info to the dataset.  Offset is the current
    # pos in the bank if this is the first dataset inserted into a
    # codeset bank ('mixed' type), 'size' will already be defined from
    # the codeset layout stage and can be used as usual
    $bin->{'bank'} = $dataset_valid_banks[ $current_bank_index ];
    $bin->{'offset'} = $layout->{ $dataset_valid_banks[ $current_bank_index ] }{'size'} || 0;

    # then update the bank layout
    push @{ $layout->{ $dataset_valid_banks[ $current_bank_index ] }{'binaries'} }, $bin;
    $layout->{ $dataset_valid_banks[ $current_bank_index ] }{'size'} += $bin->{'size'};
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
        my @ids;
        # report dataset mappings
        @ids = map { $_->{'dataset_num' } } grep { $_->{'type'} eq 'dataset' } @{ $layout->{ $bank }{'binaries'} };
        if ( scalar( @ids ) ) {
            printf $bankcfg_h "dataset %d %s %s\n", $bank, $layout->{ $bank }{'binary'}, join( ' ', @ids );
        }
        # report codeset mappings
        @ids = map { $_->{'codeset_num' } } grep { $_->{'type'} eq 'codeset' } @{ $layout->{ $bank }{'binaries'} };
        if ( scalar( @ids ) ) {
            printf $bankcfg_h "codeset %d %s %s\n", $bank, $layout->{ $bank }{'binary'}, join( ' ', @ids );
        }
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

my $datasets = gather_datasets( $input_dir_ds, '.zx0' );
if ( not scalar( keys %$datasets ) ) {
    die "** Error: no dataset binaries found in $input_dir_ds\n";
}

my $codesets = gather_codesets( $input_dir_cs, '.bin' );
# there may be _no_ codesets after all, so no error in that case

my $bank_layout = { };

# We must first layout the codesets, they always go at the beginning of a
# bank, if they exist.  Datasets are stored after codesets
layout_codeset_binaries( $bank_layout, $codesets );
layout_dataset_binaries( $bank_layout, $datasets );

generate_bank_binaries( $bank_layout, $output_dir );

generate_bank_config( $bank_layout, $output_dir );

generate_dataset_info_code_asm( $bank_layout, $datasets, $lowmem_output_dir );

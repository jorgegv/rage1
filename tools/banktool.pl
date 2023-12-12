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

# The following two lists show the preference for storing elements in them. 
# Data/code is stored in each bank starting by the first one on the relevant
# list

# banks allowed for codesets. All allowed, but non-contended are listed first
my @codeset_valid_banks = ( 6, 1, 3, 7 );

# banks allowed for datasets. All allowed, but contended are listed first
my @dataset_valid_banks = ( 1, 3, 7, 6, 4 );

my $num_available_banks = scalar( @dataset_valid_banks );

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
            'name'	=> $bin,
            'size'	=> ( stat( "$input_dir_ds/$bin" ) )[7],
            'dir'	=> $input_dir_ds,
            'type'	=> 'dataset',
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
            'name'	=> $bin,
            'size'	=> ( stat( "$input_dir_cs/$bin" ) )[7],
            'dir'	=> $input_dir_cs,
            'type'	=> 'codeset'
    };
}
close BINDIR;

# setup the initial bank layout structure
# Bank 4 is preconfigured, it is used for RAGE1 banked code
my $bank_layout = {
    1	=> {
                binaries => [],
                size => 0,
            },
    3	=> {
                binaries => [],
                size => 0,
            },
    4	=> {
                binaries => [ 
                    {
                        'name'	=> 'banked_code.bin',
                        'size'	=> ( stat( 'engine/banked_code/banked_code.bin' ) )[7],
                        'dir'	=> 'engine/banked_code',
                        'type'	=> 'reserved',
                        'bank'	=> 4,
                    },
                ],
                size => ( stat( 'engine/banked_code/banked_code.bin' ) )[7],
            },
    6	=> {
                binaries => [],
                size => 0,
            },
    7	=> {
                binaries => [],
                size => 0,
            },
};

# layout codeset binaries
# a codeset is directly assigned to the start of a bank
my $laid_out_codesets = 0;
foreach my $bk ( 0 .. scalar( @all_codesets ) - 1 ) {
    my $bin = $all_codesets[ $bk ];

    # just error if any codeset is too big
    if ( $bin->{'size'} > $max_bank_size ) {
        die "** Error: codeset $bin->{name} is too big ($bin->{size}), it does not fit in a bank ($max_bank_size)\n";
    }

    # try to put it in a bank
    foreach my $bank ( @codeset_valid_banks ) {
        # ignore the bank if there is already something at the start
        next if ( $bank_layout->{ $bank }{'size'} > 0 );
        # add the bank info to the codeset and update the bank layout
        $bin->{'bank'} = $bank;
        push @{ $bank_layout->{ $bank }{'binaries'} }, $bin;
        $bank_layout->{ $bank }{'size'} += $bin->{'size'};
        # update success counter
        $laid_out_codesets++;
        last;
    }
}

if ( $laid_out_codesets != scalar( @all_codesets ) ) {
    die "** Error: no more banks to fill, too many codesets\n";
}

#print Dumper( $bank_layout );

# precalculate some data
my @dataset_sizes = map { $_->{'size'} } @all_datasets;

# layout dataset binaries

# Since the number of datasets is normally small ( <= 10 ), we can explore
# the full list of permutations of datasets until we find one permutation
# that fills in the banks with the proper restrictions.  For 10 datasets,
# it's 3.6M permutations (10!).  It can take a bit to check, but it's
# definitely within the capabilities of current hosts.

my @sorted_banks = sort { $a <=> $b } keys %$bank_layout;
my %bucket_to_bank;
foreach my $i ( 0 .. scalar( @sorted_banks ) - 1 ) {
    $bucket_to_bank{ $i } = $sorted_banks[ $i ];
}

# aux function: receives a listref to a permutation of the dataset indexes
# it returns the bank layout for the permutation
sub do_dataset_layout {
    my $list = shift;
    my @list = @{$list};

    # setup buckets
    my @buckets = ( map { { size => $bank_layout->{ $_ }{'size'} } } @sorted_banks );

    # now process all the datasets
    my $current_bucket = 0;
    foreach my $ds ( @list ) {
        if ( $dataset_sizes[ $ds ] <= $max_bank_size - $buckets[ $current_bucket ]{'size'} ) {
            push @{ $buckets[ $current_bucket ]{'datasets'} }, $ds;
            push @{ $buckets[ $current_bucket ]{'offsets'} }, $buckets[ $current_bucket ]{'size'};
            $buckets[ $current_bucket ]{'size'} += $dataset_sizes[ $ds ];
        } else {
            $current_bucket++;
            push @{ $buckets[ $current_bucket ]{'datasets'} }, $ds;
            push @{ $buckets[ $current_bucket ]{'offsets'} }, 0;
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
        if ( scalar( @$layout ) <= scalar( keys %$bank_layout ) ) {
            @dataset_indexes = @indexes;	# found
            $dataset_layout = $layout;
        }
    }
} @indexes;

scalar( @dataset_indexes ) or
    die "There is no dataset layout possible with the available memory banks\n";

printf "Selected dataset layout: [ %s ]\n", join( ', ', @dataset_indexes );

#print Dumper( $dataset_layout );

foreach my $di ( 0 .. scalar( @$dataset_layout ) - 1 ) {
    if ( defined( $dataset_layout->[ $di ]{'datasets'} ) and scalar( @{ $dataset_layout->[ $di ]{'datasets'} } ) ) {
        $bank_layout->{ $bucket_to_bank{ $di } }{'datasets'} = $dataset_layout->[ $di ]{'datasets'};
        $bank_layout->{ $bucket_to_bank{ $di } }{'offsets'} = $dataset_layout->[ $di ]{'offsets'};
        $bank_layout->{ $bucket_to_bank{ $di } }{'size'} += $dataset_layout->[ $di ]{'size'};
    }
}

#print Dumper( $bank_layout );

## At this point we have all codesets and datasets assigned to banks.  Also,
## code binaries have already been laid out on those banks affected.  Only
## datasets remains to be laid out

# lay out the dataset binaries for all banks
foreach my $bank ( keys %$bank_layout ) {
    if ( defined( $bank_layout->{ $bank }{'datasets'} ) and scalar( @{ $bank_layout->{ $bank }{'datasets'} } ) ) {
        foreach my $dsi ( 0 .. scalar( @{ $bank_layout->{ $bank }{'datasets'} } ) - 1 ) {
            my $ds = $bank_layout->{ $bank }{'datasets'}[ $dsi ];
            push @{ $bank_layout->{ $bank }{'binaries'} }, $all_datasets[ $ds ];
            $all_datasets[ $ds ]{'bank'} = $bank;
            $all_datasets[ $ds ]{'offset'} = $bank_layout->{ $bank }{'offsets'}[ $dsi ];
        }
    }
}

## all is ready, report

print "Bank layout:\n";
foreach my $bank ( @sorted_banks ) {
    printf "  Bank %d: ", $bank;
    my $total = 0;
    if ( scalar( @{ $bank_layout->{ $bank }{'binaries'} } ) and $bank_layout->{ $bank }{'binaries'}[0]{'type'} eq 'reserved' ) {
        printf "RAGE1_RESERVED(%db) - ", $bank_layout->{ $bank }{'binaries'}[0]{'size'};
        $total += $bank_layout->{ $bank }{'binaries'}[0]{'size'};
    }
    if ( scalar( @{ $bank_layout->{ $bank }{'binaries'} } ) and $bank_layout->{ $bank }{'binaries'}[0]{'type'} eq 'codeset' ) {
        $bank_layout->{ $bank }{'binaries'}[0]{'name'} =~ m/^codeset_(.*)\.bin$/;
        my $csnum = $1;
        printf "CS-%d(%db) - ", $csnum,$bank_layout->{ $bank }{'binaries'}[0]{'size'};
        $total += $bank_layout->{ $bank }{'binaries'}[0]{'size'};
    }
    if ( defined( $bank_layout->{ $bank }{'datasets'} ) ) {
        print join( '', map { 
                $total += $all_datasets[ $_ ]{'size'};
                sprintf "DS-%d(%db) - ", $_, $all_datasets[ $_ ]{'size'}
            } @{ $bank_layout->{ $bank }{'datasets'} }
        );
    }
    printf "TOTAL: %d bytes\n", $total;
}

#print Dumper( $bank_layout );

# generate bank binaries
print "Generating bank binaries...\n";

foreach my $bank ( @sorted_banks ) {

    next if not ( $bank_layout->{ $bank }{'size'} );

    my $bank_binary = $output_dir . '/' . sprintf( $bank_binaries_name_format, $bank );

    open my $bank_out, '>', $bank_binary or
        die "\n** Error: could not open $bank_binary for writing\n";
    binmode $bank_out;

    print "  Writing " . sprintf( $bank_binaries_name_format, $bank ) . "...";
    foreach my $bin ( @{ $bank_layout->{ $bank }{'binaries'} } ) {
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
    $bank_layout->{ $bank }{'binary'} = $bank_binary;
}

#print Dumper( $bank_layout );

# generate bank config
print "Generating $bank_config_name...";

my $bankcfg = $output_dir . '/' . $bank_config_name;
open my $bankcfg_h, ">", $bankcfg
    or die "\n** Error: could not open $bankcfg for writing\n";
print $bankcfg_h "# <type> <bank_num> <path> <codesets/datasets>\n";
foreach my $bank ( keys %$bank_layout ) {
    # report codeset mappings
    my $codesets = $bank_layout->{ $bank }{'codesets'} || undef;
    if ( defined( $codesets ) and scalar( @$codesets ) ) {
        printf $bankcfg_h "codeset %d %s %s\n", $bank, $bank_layout->{ $bank }{'binary'},
            join( ' ', @$codesets );
    }
    # report dataset mappings
    my $datasets = $bank_layout->{ $bank }{'datasets'} || undef;
    if ( defined( $datasets ) and scalar( @$datasets ) ) {
        printf $bankcfg_h "dataset %d %s %s\n", $bank, $bank_layout->{ $bank }{'binary'},
            join( ' ', @$datasets );
    }
}
close $bankcfg_h;
print "OK\n";

#print Dumper( \@all_datasets );

# generate ASM stub with bank layout for datasets
print "Generating $dataset_info_name...";

my $dsmap = $output_dir . '/' . $dataset_info_name;
open my $dsmap_h, ">", $dsmap
    or die "\n** Error: could not open $dsmap for writing\n";
my $num_datasets = scalar( @all_datasets );
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

foreach my $ds ( 0 .. scalar( @all_datasets ) - 1 ) {
    printf $dsmap_h "\t\t;; dataset %d\n\t\tdb\t%d\t;; bank number\n\t\tdw\t%d\t;; size\n\t\tdw\t%d\t;; offset into bank\n",
                $ds,
                $all_datasets[ $ds ]{'bank'},
                $all_datasets[ $ds ]{'size'},
                $all_datasets[ $ds ]{'offset'};
}

close $dsmap_h;
print "OK\n";

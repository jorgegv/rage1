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
# it returns the bank layout for the permutation
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
my $bank_layout;
my @indexes = ( 0 .. scalar( @all_datasets ) - 1 );
#my $count = 0;
permute {
    if ( not scalar( @dataset_indexes ) ) {
        my $layout = do_dataset_layout( \@indexes );
        if ( scalar( @$layout ) <= $num_available_banks ) {
#        if ( ( scalar( @$layout ) <= $num_available_banks ) and ( $count++ == 1234 ) ) {
            @dataset_indexes = @indexes;	# found
            $bank_layout = $layout;
        }
    }
} @indexes;

scalar( @dataset_indexes ) or
    die "There is no dataset layout possible with the available memory banks\n";

printf "Selected dataset layout: [ %s ]\n", join( ', ', @dataset_indexes );
foreach my $i ( 0 .. scalar( @$bank_layout ) - 1 ) {
    if ( $initial_bank_sizes[ $i ] ) {
        push @{ $bank_layout->[ $i ]{'codesets'} }, $i;
    }
}

## at this point we have all codesets and datasets fitted in banks
## now we must assign a physical bank to each bank of the layout

my %used_banks;

# first we must assign the banks that have codesets, so that non-contended
# banks are assigned first
foreach my $b ( 
    grep { defined( $bank_layout->[ $_ ]{'codesets'} ) } 
    ( 0 .. scalar( @$bank_layout ) - 1 ) ) {
    my $next_phys_bank = shift @codeset_valid_banks;
    if ( $used_banks{ $next_phys_bank }++ ) {
        die "** Error: codeset bank $next_phys_bank was already used, should not happen!\n"
    }
    $bank_layout->[ $b ]{'physical_bank'} = $next_phys_bank;
#    printf "-- Physical bank %d assigned to logical bank %d\n", $next_phys_bank, $b;
}

# now we assign the banks that do not have codesets
foreach my $b ( 
    grep { not defined( $bank_layout->[ $_ ]{'codesets'} ) } 
    ( 0 .. scalar( @$bank_layout ) - 1 ) ) {
    my $next_phys_bank = shift @dataset_valid_banks;
    if ( $used_banks{ $next_phys_bank }++ ) {
        die "** Error: dataset bank $next_phys_bank was already used, should not happen!\n"
    }
    $bank_layout->[ $b ]{'physical_bank'} = $next_phys_bank;
#    printf "-- Physical bank %d assigned to logical bank %d\n", $next_phys_bank, $b;
}

# sanity checks
%used_banks = ();
foreach my $lbi ( 0 .. scalar( @$bank_layout ) - 1 ) {
    if ( not defined( $bank_layout->[ $lbi ]{'physical_bank'} ) ) {
        die "** Error: logical bank $lbi is not assigned to any physical bank\n";
    }
    if ( $used_banks{ $bank_layout->[ $lbi ]{'physical_bank'} }++ ) {
        die "** Error: physical bank $bank_layout->[$lbi]{'physical_bank'} is used more than once\n";
    }
}

# prepare the binaries for all the data in banks and report
foreach my $i ( 0 .. scalar( @$bank_layout ) - 1 ) {

    # first, push codesets, if any, and note the assigned bank in the codeset
    if ( defined( $bank_layout->[ $i ]{'codesets'} ) and scalar( @{ $bank_layout->[ $i ]{'codesets'} } ) ) {
        foreach my $cs ( @{ $bank_layout->[ $i ]{'codesets'} } ) {
            push @{ $bank_layout->[ $i ]{'binaries'} }, $all_codesets[ $cs ];
            $all_codesets[ $cs ]{'physical_bank'} = $bank_layout->[ $i ]{'physical_bank'};
            $all_codesets[ $cs ]{'bank'} = $i;
        }
    }

    # then push datasets
    if ( defined( $bank_layout->[ $i ]{'datasets'} ) and scalar( @{ $bank_layout->[ $i ]{'datasets'} } ) ) {
        foreach my $dsi ( 0 .. scalar( @{ $bank_layout->[ $i ]{'datasets'} } ) - 1 ) {
            my $ds = $bank_layout->[ $i ]{'datasets'}[ $dsi ];
            push @{ $bank_layout->[ $i ]{'binaries'} }, $all_datasets[ $ds ];
            $all_datasets[ $ds ]{'physical_bank'} = $bank_layout->[ $i ]{'physical_bank'};
            $all_datasets[ $ds ]{'bank'} = $i;
            $all_datasets[ $ds ]{'offset'} = $bank_layout->[ $i ]{'offsets'}[ $dsi ];
        }
    }

    # report
    printf "Logical Bank %d (physical:%d): ", $i, $bank_layout->[ $i ]{'physical_bank'};
    if ( defined( $bank_layout->[ $i ]{'codesets'} ) and scalar( @{ $bank_layout->[ $i ]{'codesets'} } ) ) {
        print join( ", ", map { sprintf( "CS-%s(%db)", $_, $all_codesets[ $_ ]{'size'} ) } @{ $bank_layout->[ $i ]{'codesets'} } );
        print ", ";
    }
    if ( defined( $bank_layout->[ $i ]{'datasets'} ) and scalar( @{ $bank_layout->[ $i ]{'datasets'} } ) ) {
        print join( ", ", map { sprintf( "DS-%s(%db)", $_, $all_datasets[ $_ ]{'size'} ) } @{ $bank_layout->[ $i ]{'datasets'} } );
    }
    printf " - Final size: %db\n", $bank_layout->[ $i ]{'size'};
}

# generate bank binaries
print "Generating bank binaries...\n";

foreach my $logical_bank ( 0 .. scalar( @$bank_layout ) - 1 ) {

    next if not ( $bank_layout->[ $logical_bank ]{'size'} );

    my $bank = $bank_layout->[ $logical_bank ]{'physical_bank'};
    my $bank_binary = $output_dir . '/' . sprintf( $bank_binaries_name_format, $bank );

    open my $bank_out, '>', $bank_binary or
        die "\n** Error: could not open $bank_binary for writing\n";
    binmode $bank_out;

    print "  Writing " . sprintf( $bank_binaries_name_format, $bank ) . "...";
    foreach my $bin ( @{ $bank_layout->[ $logical_bank ]{'binaries'} } ) {
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
    $bank_layout->[ $logical_bank ]{'binary'} = $bank_binary;
}

# generate bank config
print "Generating $bank_config_name...";

my $bankcfg = $output_dir . '/' . $bank_config_name;
open my $bankcfg_h, ">", $bankcfg
    or die "\n** Error: could not open $bankcfg for writing\n";
print $bankcfg_h "# <type> <bank_num> <path> <codesets/datasets>\n";
foreach my $logical_bank ( 0 .. scalar( @$bank_layout ) - 1 ) {
    my $bank = $bank_layout->[ $logical_bank ]{'physical_bank'};
    # report codeset mappings
    my $codesets = $bank_layout->[ $logical_bank ]{'codesets'} || undef;
    if ( defined( $codesets ) and scalar( @$codesets ) ) {
        printf $bankcfg_h "codeset %d %s %s\n", $bank, $bank_layout->[ $logical_bank ]{'binary'},
            join( ' ', @$codesets );
    }
    # report dataset mappings
    my $datasets = $bank_layout->[ $logical_bank ]{'datasets'} || undef;
    if ( defined( $datasets ) and scalar( @$datasets ) ) {
        printf $bankcfg_h "dataset %d %s %s\n", $bank, $bank_layout->[ $logical_bank ]{'binary'},
            join( ' ', @$datasets );
    }
}
close $bankcfg_h;
print "OK\n";

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
                $all_datasets[ $ds ]{'physical_bank'},
                $all_datasets[ $ds ]{'size'},
                $all_datasets[ $ds ]{'offset'};
}

close $dsmap_h;
print "OK\n";

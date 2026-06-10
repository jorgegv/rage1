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

use FindBin qw( $Bin );
use lib "$Bin/../lib";
require RAGE::Config;

# The following two lists show the preference for storing elements in them.
# Data/code is stored in each bank starting by the first one on the relevant
# list.
#
# As of B1-2 the values are sourced from etc/rage1-config.yml under
# banking.<platform>.{dataset_valid_banks,codeset_valid_banks}; the literal
# arrays below remain as a fallback (with a deprecation warning) for
# backwards compatibility if the YAML section is missing.

# fallback values (used if the YAML banking section is missing)
my @fallback_codeset_valid_banks = ( 6, 1, 3, 7 );
my @fallback_dataset_valid_banks = ( 1, 3, 7, 6, 4 );
my $fallback_engine_code_memory_bank = 4;

# the actual lists, populated from YAML in the main block below
my ( @codeset_valid_banks, @dataset_valid_banks );
my $engine_code_memory_bank;

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
our( $opt_i, $opt_o, $opt_b, $opt_s, $opt_l, $opt_c, $opt_p );
getopts("i:o:s:l:c:p:");
( defined( $opt_i ) and defined( $opt_o ) and defined( $opt_c ) ) or
    die "usage: $0 -i <dataset_bin_dir> -c <codeset_bin_dir> -o <output_dir> -s <bank_switcher_binary> [-l <lowmem_output_dir>] [-p <platform>]\n";

# if $lowmem_output_dir is not specified, use same as $output_dir
my ( $input_dir_ds, $input_dir_cs, $output_dir, $lowmem_output_dir ) = ( $opt_i, $opt_c, $opt_o, $opt_l || $opt_o );
my $bank_switcher_binary = $opt_s;

# platform defaults to zx128 (B1-2: only ZX 128 banking config exists today)
my $platform = $opt_p // 'zx128';

# B5-1: cpc-flat has no banking — all assets live in the flat 64K address
# space with no bank switching.  banktool.pl is a no-op for cpc-flat:
# no bank binaries, no dataset_info.asm, no bank_bins.cfg to emit.
# Exit immediately with a clear notice so the Makefile can call us
# unconditionally without special-casing cpc-flat.
if ( $platform eq 'cpc-flat' ) {
    print "banktool.pl: platform=$platform has no banking — nothing to do\n";
    exit 0;
}

# load banking config from etc/rage1-config.yml; fall back to legacy
# hard-coded values with a deprecation warning if the section is missing.
{
    my $cfg = rage1_get_config();
    my $bank_cfg = $cfg->{'banking'}{ $platform };
    if ( defined( $bank_cfg )
            and defined( $bank_cfg->{'dataset_valid_banks'} )
            and defined( $bank_cfg->{'codeset_valid_banks'} ) ) {
        @dataset_valid_banks = @{ $bank_cfg->{'dataset_valid_banks'} };
        @codeset_valid_banks = @{ $bank_cfg->{'codeset_valid_banks'} };
        # B7-1/T3-5: the reserved engine-code bank is per-platform too
        # (zx128 and cpc-banked both use bank 4 by hardware convention).
        $engine_code_memory_bank = $bank_cfg->{'engine_code_memory_bank'}
            // $fallback_engine_code_memory_bank;
    } else {
        warn "** banktool.pl: banking.$platform missing from rage1-config.yml; using deprecated hard-coded fallback (will be removed in a future release)\n";
        @dataset_valid_banks = @fallback_dataset_valid_banks;
        @codeset_valid_banks = @fallback_codeset_valid_banks;
        $engine_code_memory_bank = $fallback_engine_code_memory_bank;
    }
}

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
#
# B7-1/T3-5: the usable bank set is derived from the per-platform YAML
# valid-bank lists (banking.<platform>.{dataset,codeset}_valid_banks) plus the
# reserved engine-code bank (engine_code_memory_bank); previously this was
# hard-coded to the ZX 128 set { 1, 3, 4, 6, 7 } with bank 4 reserved.  The
# engine-code bank is preconfigured with the RAGE1 banked code binary.  For
# zx128 this reproduces the historical set { 1, 3, 4, 6, 7 } byte-identically
# (union of [1,3,7,6,4] + [6,1,3,7] + {4}); for cpc-banked it yields { 4, 5, 6, 7 }.
my $banked_code_bin = 'engine/banked_code/banked_code.bin';
my $banked_code_size = ( stat( $banked_code_bin ) )[7];

my $bank_layout = {};
my %seen_bank;
foreach my $bank ( @dataset_valid_banks, @codeset_valid_banks, $engine_code_memory_bank ) {
    next if $seen_bank{ $bank }++;
    $bank_layout->{ $bank } = {
        binaries => [],
        size => 0,
    };
}

# preconfigure the reserved engine-code bank with the banked code binary
$bank_layout->{ $engine_code_memory_bank } = {
    binaries => [
        {
            'name'	=> 'banked_code.bin',
            'size'	=> $banked_code_size,
            'dir'	=> 'engine/banked_code',
            'type'	=> 'reserved',
            'bank'	=> $engine_code_memory_bank,
        },
    ],
    size => $banked_code_size,
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
        push @{ $bank_layout->{ $bank }{'codesets'} }, $bk;
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

    # setup buckets with initial sizes
    #
    # cpc-banked: datasets must NOT share the reserved engine-code bank
    # (engine_code_memory_bank).  On ZX 128 that bank is full of real banked code
    # so datasets naturally avoid it, but on cpc-banked the smoke game has EMPTY
    # banked code, leaving the bank empty — and the numeric bank sort below would
    # then fill it with datasets first.  The engine pages this bank in to CALL
    # banked code, so dataset bytes there are fatal.  Mark its dataset bucket FULL
    # so datasets skip it (the reserved banked-code binary is laid out separately).
    my @buckets = ( map {
        { size => ( ( $platform eq 'cpc-banked' and $_ == $engine_code_memory_bank )
                        ? $max_bank_size
                        : $bank_layout->{ $_ }{'size'} ) }
    } @sorted_banks );

    # now process all the datasets
    my $current_bucket = 0;
    foreach my $ds ( @list ) {
        while ( defined( $buckets[ $current_bucket ]{'size'} ) and
                ( $buckets[ $current_bucket ]{'size'} + $dataset_sizes[ $ds ] > $max_bank_size ) ) {
            $current_bucket++;
        }
        push @{ $buckets[ $current_bucket ]{'datasets'} }, $ds;
        push @{ $buckets[ $current_bucket ]{'offsets'} }, $buckets[ $current_bucket ]{'size'};
        $buckets[ $current_bucket ]{'size'} += $dataset_sizes[ $ds ];
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

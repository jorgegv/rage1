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

# auxiliary functions

sub gather_binaries {
    my ( $dir, $ext ) = @_;
    my @binaries;

    opendir BINDIR, $dir or
        die "Could not open directory $dir for reading\n";
    @binaries = grep { /^dataset_.*\Q$ext\E/ } readdir BINDIR;
    close BINDIR;
    return \@binaries;
}

##
## Main
##

# parse command options
our( $opt_i, $opt_o, $opt_b );
getopts("i:o:b:");
( defined( $opt_i ) and defined( $opt_o ) ) or
    die "usage: $0 -i <dataset_bin_dir> -o <output_dir> [-b <.bin_ext>]\n";

my ( $in_dir, $out_dir ) = ( $opt_i, $opt_o );
my $bin_ext = $opt_b || '.bin';

my $bins = gather_binaries( $in_dir, $bin_ext );
if ( not scalar( @$bins ) ) {
    die "** Error: no dataset binaries found in $in_dir\n";
}

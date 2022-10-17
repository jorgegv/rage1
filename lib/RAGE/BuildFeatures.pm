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

my $features_h = "$FindBin::Bin/../build/generated/features.h";

my $features;

sub rage1_build_features_get_all {
    if ( not defined( $features ) ) {
        open BLD, $features_h or
            die "Could not open $features_h for reading\n";
        while ( my $line = <BLD> ) {
            chomp $line;
            if ( $line =~ /^#define\s+(BUILD_FEATURE_.*)\s*$/ ) {
                push @$features, $1;
            }
        }
        close BLD;
    }
    return @$features;
}

1;

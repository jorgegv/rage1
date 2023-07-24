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

use YAML qw( LoadFile );

# default config file name
my $rage1_config_file = "$FindBin::Bin/../etc/rage1-config.yml";

# holds cached value so that file is read only once per execution
my $rage1_config;

# returns a hash with all configuration
sub rage1_get_config {
    if ( not defined( $rage1_config ) ) {
        $rage1_config = LoadFile( $rage1_config_file );
    }
    return $rage1_config;
}

1;

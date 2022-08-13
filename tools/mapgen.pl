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

use FindBin;
use lib "$FindBin::Bin/../lib";

require RAGE::PNGFileUtils;

use Data::Dumper;

my $png_file = $ARGV[0];

defined( $png_file ) or
    die "usage: $0 <png_file>\n";

my $png = load_png_file( $png_file );
my $cells = png_get_all_cell_data( $png, 1, 1, 3, 2 );
print Dumper( $cells );

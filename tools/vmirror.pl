#!/usr/bin/perl -w

################################################################################
##
## RAGE1 - Retro Adventure Game Engine, release 1
## (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
## 
## This code is published under a GNU GPL license version 3 or later.  See
## LICENSE file in the distribution for details.
## 
################################################################################

while (my $line = <>) {
    chomp $line;
    if ( ( $line =~ /^(\s*PIXELS\s+)([\.#]+)$/ ) or ( $line =~ /^(\s*MASK\s+)([\.#]+)$/) ){
        my ( $l, $d ) = ( $1, $2 );
        printf "%s%s\n",$l,scalar reverse $d;
    } else {
        print $line,"\n";
    }
}

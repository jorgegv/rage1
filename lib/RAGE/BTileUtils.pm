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

use File::Basename;

sub btile_get_png_tiledef_filename {
    my $png_file = shift;
    return dirname( $png_file ) . '/' . basename( $png_file, '.png', '.PNG' ) . '.tiledef';
}

# reads the associated .tiledef file for a given PNG file and returns the
# list of btiles defined in the file
# returns: listref of hashrefs - { name =>, row =>, col =>, width =>, height => , file => , num_cells => ...}
sub btile_read_png_tiledefs {
    my $png_file = shift;
    my @tiledefs;

    my $tiledef_file = btile_get_png_tiledef_filename( $png_file );

    open TILEDEF, $tiledef_file or
        die "Could not open $tiledef_file for reading\n";
    while ( my $line = <TILEDEF> ) {
        chomp $line;
        $line =~ s/#.*$//g;		# remove comments
        next if $line =~ m/^$/;		# skip line if empty
        $line =~ s/\s+/ /g;		# replace multiple spaces with one
        my ( $name, $row, $col, $width, $height ) = split( /\s+/, $line );
        push @tiledefs, {
            name		=> $name,
            cell_row		=> $row,
            cell_col		=> $col,
            cell_width		=> $width,
            cell_height		=> $height,
            pixel_pos_x		=> $col * 8,
            pixel_pos_y		=> $row * 8,
            pixel_width		=> $width * 8,
            pixel_height	=> $height * 8,
            tiledef_line	=> $line,
            png_file		=> $png_file,
        };
    }
    close TILEDEF;
    return \@tiledefs;    
}

1;

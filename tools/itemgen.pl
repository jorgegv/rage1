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

# An Item is a part of the inventory, and is something that can be grabbed,
# and (optionally) dropped.  Every item has an associated btile.
#
# The item can be grabbed on a given screen (source screen) and position
# (row,col): if the hero walks over the item position, it will be added to
# the inventory (and the item will be removed from sceeen).
#
# Optionally, the item can be dropped at another point in the game map (dest
# screen, row, col), that is, removed automatically from the inventory.
#
# This tool reads item configuration form STDIN and outputs GDATA config
# with map patches.  These include, for each item, the item definition (name
# and BTILE), the source screen and the item position on it.  If an optional
# destination screen and position are defined in the config file for a given
# item, an additional HOTZONE and rules are defined as patches to the
# destination screen, so that when the hero walks over the hotzone, the item
# is removed from the inventory and the hotzone deactivated.
#
# Input syntax is one item per line, with the following fields (brackets
# indicate optional fields):
#
# <item_name> <btile_name> <src_screen> <src_row> <src_col> [ <dst_screen> <dst_row> <dst_col>  <hotzone_width> <hotzone_height> ]
#
# Comments can be added and start with // or # to the end of the line

use Modern::Perl;

my $line_num = 1;
while ( my $line = <STDIN> ) {
    chomp $line;
    $line =~ s/\/\/.*//g;
    $line =~ s/#.*//g;
    next if ( $line =~ /^$/ );

    my ( $item_name, $btile_name, $src_screen, $src_row, $src_col, $dst_screen, $dst_row, $dst_col, $hotzone_width, $hotzone_height ) = split( /\s+/, $line );

    ( defined( $item_name ) and defined( $btile_name ) and defined( $src_screen ) and defined( $src_row ) and defined( $src_col ) ) or
        die "** Line $line_num: item_name, btile_name, src_screen, src_row and src_col are mandatory\n";

    # create the item definition in the src screen
    printf "PATCH_SCREEN NAME=%s\n", $src_screen;
    printf "\tITEM\tNAME=%s BTILE=%s ROW=%d COL=%d\n", $item_name, $btile_name, $src_row, $src_col;
    print "END_SCREEN\n\n";

    # if a dst_screen is specified, create a dropoff hotzone in it for the item
    if ( defined( $dst_screen ) ) {
        ( defined( $dst_row ) and defined( $dst_col ) and defined( $hotzone_width ) and defined( $hotzone_height ) ) or
            die "** Line $line_num: if dst_screen is defined, dst_row, dst_col, hotzone_width and hotzone_height are mandatory\n";

        my $dropoff_hotzone_name = sprintf( "Dropoff_%s", $item_name );
        printf "PATCH_SCREEN NAME=%s\n", $dst_screen;
        printf "\tHOTZONE\tNAME=%s ROW=%d COL=%d WIDTH=%d HEIGHT=%d ACTIVE=1 CAN_CHANGE_STATE=1\n",
            $dropoff_hotzone_name, $dst_row, $dst_col, $hotzone_width, $hotzone_height;
        print "END_SCREEN\n";

        my $item_id = sprintf( 'INVENTORY_ITEM_%s', uc( $item_name ) );
        print  "BEGIN_RULE\n";
        printf "\tSCREEN\t%s\n", $dst_screen;
        print  "\tWHEN\tGAME_LOOP\n";
        printf "\tCHECK\tHERO_OVER_HOTZONE %s\n", $dropoff_hotzone_name;
        printf "\tCHECK\tITEM_IS_OWNED %s\n", $item_id;
        printf "\tDO\tREMOVE_FROM_INVENTORY %s\n", $item_id;
        printf "\tDO\tDISABLE_HOTZONE %s\n", $dropoff_hotzone_name;
        print  "\t// add here your own actions triggered when the item is dropped\n";
        print  "END_RULE\n\n";
    }

} continue {
    $line_num++;
}

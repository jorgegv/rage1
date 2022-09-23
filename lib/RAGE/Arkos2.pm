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

require RAGE::Config;

# arkos2_convert_song_to_asm: receives a file name (an song in AKS format)
# and a C symbol name which will be the name of the song during the game. 
# Returns a file name under /tmp which is the AKS song exported in ASM
# format.
sub arkos2_convert_song_to_asm {
    my ( $song_file, $song_symbol ) = @_;

    # for arkos tools location
    my $cfg = rage1_get_config();

    my $tmp_file = "/tmp/song-$$.asm";

    my @command = (
        $cfg->{'tools'}{'arkos'}{'dir'} ."/tools/SongToAkg",
        '-sppostlbl',
        ':',
        $song_file,
        $tmp_file,
    );
    if ( system( @command ) != 0 ) {
        die sprintf( "Error running command: %s\n", join( ' ', @command ) );
    }
    open TMPIN, $tmp_file or
        die "Could not open file $tmp_file for reading\n";

    my $asm_file = sprintf( "/tmp/song_%s.asm", $song_symbol );
    open ASMOUT, ">$asm_file" or
        die "Could not open file $asm_file for writing\n";

    print ASMOUT "section data_compiler\n";
    printf ASMOUT "public _%s\n", $song_symbol;
    printf ASMOUT "_%s:\n", $song_symbol;

    while (<TMPIN>) {
        chomp;
        s/\r//g;
        print ASMOUT $_,"\n";
    };

    close TMPIN;
    close ASMOUT;

    return $asm_file;
}

1;

package RAGE::Datagen::Util;

################################################################################
##
## RAGE1 - Retro Adventure Game Engine, release 1
## (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
##
## This code is published under a GNU GPL license version 3 or later.  See
## LICENSE file in the distribution for details.
##
################################################################################
##
## RAGE::Datagen::Util — pure helper functions for datagen.  Extracted verbatim
## from tools/datagen.pl (Task 6, Stage 2 leaf module): each is a pure value
## transform with no shared datagen state, so the emitted bytes are
## byte-identical to the in-line versions.
##
################################################################################

use strict;
use warnings;
use utf8;

use Exporter 'import';
our @EXPORT_OK = qw( optional_hex_decode pixels_to_byte integer_in_range );

# decode "0xNN" / "$NN" hex literals to a number; pass any other value through
# unchanged.
sub optional_hex_decode {
    my $value = shift;
    if ( $value =~ m/^0x[0-9a-f]+$/i ) {
        return hex( $value );
    }
    if ( $value =~ m/^\$([0-9a-f]+)$/i ) {
        return hex( $1 );
    }
    return $value;
}

# converts a 16-char long string of ## and .. into its 8 bit number
# MSB first
sub pixels_to_byte {
    my $pixels = shift;
    return -1 if ( length( $pixels ) != 16 );
    # yes 'oct' function in perl converts _binary_ strings to number
    return oct( '0b' . join( '', map { ( $_ eq '..' ? '0' : '1' ) } unpack("(A2)*", $pixels ) ) );
}

sub integer_in_range {
    my ( $value, $min, $max ) = @_;
    return ( ( $value >= $min ) and ( $value <= $max ) );
}

1;

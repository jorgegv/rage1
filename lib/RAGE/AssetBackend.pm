package RAGE::AssetBackend;

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
## RAGE::AssetBackend — registry/factory for datagen's per-platform asset
## generation backends (Task 5).  Each backend owns the platform-specific
## translation of sprite/tile graphics into the target's byte layout.  ZX is
## the first backend (byte-identical to the pre-refactor output); CPC mode 1 is
## the second.  Future CPC modes (0, 2) drop in as additional backends.
##
##   my $be = RAGE::AssetBackend->create( platform => 'cpc' );  # or 'zx'
##   my ( $data, $offsets ) = $be->sprite_frame_data( $sprite );
##
################################################################################

use strict;
use warnings;
use utf8;

use RAGE::AssetBackend::ZX;
use RAGE::AssetBackend::CPCMode1;

# create( platform => 'zx' | 'cpc' ) -> backend object.
# (CPC currently = mode 1; when more CPC modes land this dispatches on mode.)
sub create {
    my ( $class, %opt ) = @_;
    my $platform = $opt{'platform'} || 'zx';
    if ( $platform eq 'cpc' ) {
        return RAGE::AssetBackend::CPCMode1->new( %opt );
    }
    return RAGE::AssetBackend::ZX->new( %opt );
}

1;

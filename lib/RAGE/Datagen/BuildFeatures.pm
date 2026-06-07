package RAGE::Datagen::BuildFeatures;

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
## RAGE::Datagen::BuildFeatures — conditional build-feature bookkeeping for
## datagen (Task 6, Stage 2 extraction).  Moved verbatim from tools/datagen.pl;
## the shared %conditional_build_features and $game_config state lives in the
## RAGE::Datagen::Context object ($ctx), threaded in as the first positional
## arg of each non-pure sub and reached as $ctx->{conditional_build_features} /
## $ctx->{game_config}, so behaviour (and emitted features.h) is unchanged.
##
## NOTE: $ctx->{conditional_build_features} is shared mutable state — datagen.pl
## and the other modules read it and `delete` entries directly (it is the same
## hash), so add_build_feature() writes here are seen there and vice-versa.
##
################################################################################

use strict;
use warnings;
use utf8;

use Exporter 'import';
our @EXPORT_OK = qw(
    add_build_feature
    is_build_feature_enabled
    add_default_build_features
    input_backend_for_platform
    get_gfx_backend
);

# build features that always selected no matter what
# GFX_BACKEND_* / SPRITE_ENGINE_* are NOT here - they are added in
# generate_game_config based on game data
my @default_build_features = qw(
    BTILE_2BIT_TYPE_MAP
    GAME_TIME
);

sub add_build_feature {
    my $ctx = shift;
    my $f = shift;
    $ctx->{conditional_build_features}{ $f }++;
}

sub is_build_feature_enabled {
    my $ctx = shift;
    my $f = shift;
    return defined( $ctx->{conditional_build_features}{ $f } );
}

# IN5-3: the input backend is forced by PLATFORM (no user choice — see
# input.md §3.2). zx48/zx128 -> ZX backend; cpc464/cpc6128 -> CPC backend.
# cpc6128 is recognised here even though it is not yet an accepted PLATFORM
# value (Phase T3 enables it) so the mapping is ready ahead of time.
sub input_backend_for_platform {
    my $platform = shift;
    return ( $platform eq 'cpc464' or $platform eq 'cpc6128' )
        ? 'INPUT_BACKEND_CPC'
        : 'INPUT_BACKEND_ZX';
}

sub get_gfx_backend {
    my $ctx = shift;
    return ( defined( $ctx->{game_config} ) && defined( $ctx->{game_config}->{'gfx_backend'} ) )
        ? $ctx->{game_config}->{'gfx_backend'} : 'sp1';
}

sub add_default_build_features {
    my $ctx = shift;
    foreach my $f ( @default_build_features ) {
        add_build_feature( $ctx, $f );
    }
}

1;

package RAGE::Datagen::Dependencies;

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
## RAGE::Datagen::Dependencies — the dependency-derivation subs for datagen
## (Task 6, Stage 2 extraction).  Moved verbatim from tools/datagen.pl; the
## shared globals live in the RAGE::Datagen::Context object ($ctx), threaded in
## as the first positional arg of each sub and reached as $ctx->{all_screens},
## $ctx->{game_config}, $ctx->{dataset_dependency}, $ctx->{screen_name_to_index},
## $ctx->{btile_name_to_index}, $ctx->{sprite_name_to_index}, $ctx->{all_btiles},
## $ctx->{hero}, $ctx->{all_items}, $ctx->{all_crumb_types},
## $ctx->{game_events_rule_table} and $ctx->{conditional_build_features}.
##
## add_build_feature (RAGE::Datagen::BuildFeatures) is imported here.  zip
## (List::MoreUtils) is imported here.  derive_cpc_audio_backend_features lives
## in this same module and is called unqualified from fix_feature_dependencies
## (it is also exported because main() calls it directly on the screen-less CPC
## fast path).  Behaviour (and emitted bytes) is unchanged.
##
## Exported: create_dataset_dependencies, fix_feature_dependencies,
## derive_cpc_audio_backend_features.
##
################################################################################

use strict;
use warnings;
use utf8;

use List::MoreUtils qw( zip );

use RAGE::Datagen::BuildFeatures qw( add_build_feature );

use Exporter 'import';
our @EXPORT_OK = qw(
    create_dataset_dependencies fix_feature_dependencies
    derive_cpc_audio_backend_features
);

# calculates dataset_dependency structure:
# dataset_dependency: a hash dataset_id => {
#    btiles	=> [ ... ],	# index of btiles that must go in this dataset
#    sprites	=> [ ... ],	# ...ditto for sprites...
#    rules	=> [ ... ],	# ...rules...
#    screens	=> [ ... ],	# ...screens...
# }
#
# All values in the above listrefs are indexes into the global tables for
# each asset type (the all_<something> variables).

sub create_dataset_dependencies {
    my $ctx = shift;

    # first, we add all assets to the dataset lists
    foreach my $screen ( @{ $ctx->{all_screens} } ) {

        # get the screen dataset, override it and use 'home' if compiling for 48K target
        my $dataset = ( $ctx->{game_config}->{'zx_target'} eq '48' ? 'home' : $screen->{'dataset'} );

        # add screen to the dataset
        push @{ $ctx->{dataset_dependency}{ $dataset }{'screens'} },
            $ctx->{screen_name_to_index}{ $screen->{'name'} };

        # add btiles
        push @{ $ctx->{dataset_dependency}{ $dataset }{'btiles'} },
            map { $ctx->{btile_name_to_index}{ $_->{'btile'} } } @{ $screen->{'btiles'} };

        # the background btile is a special case, add it to the btile list
        if ( defined( $screen->{'background'} ) ) {
            push @{ $ctx->{dataset_dependency}{ $dataset }{'btiles'} },
                $ctx->{btile_name_to_index}{ $screen->{'background'}{'btile'} };
        }

        # add sprites
        push @{ $ctx->{dataset_dependency}{ $dataset }{'sprites'} },
            map { $ctx->{sprite_name_to_index}{ $_->{'sprite'} } } @{ $screen->{'enemies'} };

        # add rules
        push @{ $ctx->{dataset_dependency}{ $dataset }{'rules'} },
            map { @{ $screen->{'rules'}{ $_ } } } keys %{ $screen->{'rules'} };
    }

    # we then add the home dataset dependencies:
    # ...special btiles with a 'home' dataset
    foreach my $btile ( @{ $ctx->{all_btiles} } ) {
        # get the btile dataset, override it and use 'home' if compiling for 48K target
        my $dataset = ( $ctx->{game_config}->{'zx_target'} eq '48' ? 'home' : $btile->{'dataset'} );
        if ( defined( $btile->{'dataset'} ) ) {
            push @{ $ctx->{dataset_dependency}{ $dataset }{'btiles'} },
                $ctx->{btile_name_to_index}{ $btile->{'name'} };
        }
    }

    # ...hero sprite
    push @{ $ctx->{dataset_dependency}{'home'}{'sprites'} },
        $ctx->{sprite_name_to_index}{ $ctx->{hero}->{'sprite'} };

    # ...bullet sprite
    if ( defined( $ctx->{hero}->{'bullet'} ) ) {
        push @{ $ctx->{dataset_dependency}{'home'}{'sprites'} },
            $ctx->{sprite_name_to_index}{ $ctx->{hero}->{'bullet'}{'sprite'} };
    }

    # item btiles are always added to the home dataset, since the item table
    # is global
    foreach my $item ( @{ $ctx->{all_items} } ) {
        push @{ $ctx->{dataset_dependency}{'home'}{'btiles'} },
            $ctx->{btile_name_to_index}{ $item->{'btile'} };
    }

    # crumb btiles are always added to the home dataset, since the crumb type table
    # is global
    foreach my $crumb_type ( @{ $ctx->{all_crumb_types} } ) {
        push @{ $ctx->{dataset_dependency}{'home'}{'btiles'} },
            $ctx->{btile_name_to_index}{ $crumb_type->{'btile'} };
    }

    # the same for the Lives btile
    push @{ $ctx->{dataset_dependency}{'home'}{'btiles'} },
        $ctx->{btile_name_to_index}{ $ctx->{hero}->{'lives'}{'btile'} };

    # add rules in the game events rule table to the home dataset
    push @{ $ctx->{dataset_dependency}{ 'home' }{'rules'} },
        @{ $ctx->{game_events_rule_table} };

    # we must then remove duplicates from the lists
    # we take the oportunity to precalculate some tables
    foreach my $dataset ( keys %{ $ctx->{dataset_dependency} } ) {

        my %seen = ();
        $ctx->{dataset_dependency}{ $dataset }{'screens'} =
            [ sort { $a <=> $b } grep { !$seen{$_}++ } @{ $ctx->{dataset_dependency}{ $dataset }{'screens'} } ];

        %seen = ();	# reset
        $ctx->{dataset_dependency}{ $dataset }{'btiles'} =
            [ sort { $a <=> $b } grep { !$seen{$_}++ } @{ $ctx->{dataset_dependency}{ $dataset }{'btiles'} } ];

        %seen = ();	# reset
        $ctx->{dataset_dependency}{ $dataset }{'sprites'} =
            [ sort { $a <=> $b } grep { !$seen{$_}++ } @{ $ctx->{dataset_dependency}{ $dataset }{'sprites'} } ];

        %seen = ();	# reset
        $ctx->{dataset_dependency}{ $dataset }{'rules'} =
            [ sort { $a <=> $b } grep { !$seen{$_}++ } @{ $ctx->{dataset_dependency}{ $dataset }{'rules'} } ];

        # we now precalculate the global->local asset index tables for all asset types

        # generate the global->local index btile mapping table
        my @local_btile = ( 0 .. scalar( @{ $ctx->{dataset_dependency}{ $dataset }{'btiles'} } ) - 1 );
        my @global_btile = map { $ctx->{dataset_dependency}{ $dataset }{'btiles'}[ $_ ] } @local_btile;
        my %btile_global_to_dataset_index = ( zip @global_btile, @local_btile );
        $ctx->{dataset_dependency}{ $dataset }{'btile_global_to_dataset_index'} = \%btile_global_to_dataset_index;

        # generate the global->local index sprite mapping table
        my @local_sprite = ( 0 .. scalar( @{ $ctx->{dataset_dependency}{ $dataset }{'sprites'} } ) - 1 );
        my @global_sprite = map { $ctx->{dataset_dependency}{ $dataset }{'sprites'}[ $_ ] } @local_sprite;
        my %sprite_global_to_dataset_index = ( zip @global_sprite, @local_sprite );
        $ctx->{dataset_dependency}{ $dataset }{'sprite_global_to_dataset_index'} = \%sprite_global_to_dataset_index;

        # generate the global->local index rule mapping table
        my @local_rule = ( 0 .. scalar( @{ $ctx->{dataset_dependency}{ $dataset }{'rules'} } ) - 1 );
        my @global_rule = map { $ctx->{dataset_dependency}{ $dataset }{'rules'}[ $_ ] } @local_rule;
        my %rule_global_to_dataset_index = ( zip @global_rule, @local_rule );
        $ctx->{dataset_dependency}{ $dataset }{'rule_global_to_dataset_index'} = \%rule_global_to_dataset_index;

        # generate the global->local index screen mapping table
        my @local_screen = ( 0 .. scalar( @{ $ctx->{dataset_dependency}{ $dataset }{'screens'} } ) - 1 );
        my @global_screen = map { $ctx->{dataset_dependency}{ $dataset }{'screens'}[ $_ ] } @local_screen;
        my %screen_global_to_dataset_index = ( zip @global_screen, @local_screen );
        $ctx->{dataset_dependency}{ $dataset }{'screen_global_to_dataset_index'} = \%screen_global_to_dataset_index;
    }
}

# fixes dependencies between build features.  put here all exceptions and
# mangling needed for build features that need/exclude others, etc.
# AU4-3: derive CPC audio backend macros (Phase AU4 of
# doc/multiplatform-plan/audio.md). CPC has only the AY backend (no
# beeper). On CPC, Arkos2 is the only tracker — vortex2 is a ZX-only
# tracker and is rejected at validation time (check_game_config_is_valid).
#
#   PLATFORM cpc464 + TRACKER            -> MUSIC: CPC_AY
#                                          (+ CPC_AY SFX if FX_CHANNEL set)
#
# The always-present beeper-SFX compat shims that satisfy the engine's
# unconditional audio_sfx_beeper_*() calls live in audio_cpc_ay.h and are
# pulled in for EVERY CPC build by audio.h's CPC platform predicate — they
# need no feature macro of their own.
#
# This is its own sub (not inlined in fix_feature_dependencies) because the
# screen-less CPC fast path in main() bypasses fix_feature_dependencies; it
# calls this directly so the AU4-3 macros are emitted on minimal CPC games too.
sub derive_cpc_audio_backend_features {
    my $ctx = shift;
    if ( defined( $ctx->{conditional_build_features}{ 'PLATFORM_CPC464' } ) and
         defined( $ctx->{conditional_build_features}{ 'TRACKER' } ) ) {
        # Music backend: AY music on CPC whenever a TRACKER is configured.
        add_build_feature( $ctx, 'AUDIO_MUSIC_BACKEND_CPC_AY' );
        # SFX backend: AY SFX channel, only when FX_CHANNEL is set.
        if ( defined( $ctx->{conditional_build_features}{ 'TRACKER_SOUNDFX' } ) ) {
            add_build_feature( $ctx, 'AUDIO_SFX_BACKEND_CPC_AY' );
        }
    }
}

sub fix_feature_dependencies {
    my $ctx = shift;

    # currently, the CRUMBS feature needs to have byte-size tile types, so
    # if CRUMBS are used, disable the default packed tile map
    if ( defined( $ctx->{conditional_build_features}{ 'CRUMBS' } ) and
        defined( $ctx->{conditional_build_features}{ 'BTILE_2BIT_TYPE_MAP' }) ) {
        delete $ctx->{conditional_build_features}{ 'BTILE_2BIT_TYPE_MAP' };
    }

    # if ZX_TARGET is 48, CODESETs make no sense
    if ( defined( $ctx->{conditional_build_features}{ 'ZX_TARGET_48' } ) and
        defined( $ctx->{conditional_build_features}{ 'CODESETS' }) ) {
        delete $ctx->{conditional_build_features}{ 'CODESETS' };
    }

    # AU2-3: derive BUILD_FEATURE_AUDIO_*_BACKEND_* macros (Phase AU2 of
    # doc/multiplatform-plan/audio.md). These are emitted *alongside*
    # the legacy BUILD_FEATURE_TRACKER* macros — they do not replace
    # anything yet. Per §3.2 backend-split table:
    #
    #   PLATFORM zx48                       -> SFX: ZX_BEEPER
    #   PLATFORM zx128 (no TRACKER)         -> SFX: ZX_BEEPER
    #   PLATFORM zx128 + TRACKER            -> MUSIC: ZX_AY
    #                                          SFX:   ZX_BEEPER
    #                                          (+ ZX_AY if FX_CHANNEL set)
    #
    # CPC backends are not derived here; they enter the picture in
    # Phase AU4 once the PLATFORM_CPC* macros land.
    if ( defined( $ctx->{conditional_build_features}{ 'ZX_TARGET_48' } ) or
         defined( $ctx->{conditional_build_features}{ 'ZX_TARGET_128' } ) ) {
        # SFX backend: beeper is always available on ZX (48 or 128).
        add_build_feature( $ctx, 'AUDIO_SFX_BACKEND_ZX_BEEPER' );
    }
    if ( defined( $ctx->{conditional_build_features}{ 'ZX_TARGET_128' } ) and
         defined( $ctx->{conditional_build_features}{ 'TRACKER' } ) ) {
        # Music backend: AY music on ZX128 whenever a TRACKER is configured.
        add_build_feature( $ctx, 'AUDIO_MUSIC_BACKEND_ZX_AY' );
        # Second SFX backend: AY SFX channel, only when FX_CHANNEL is set
        # (today's TRACKER_SOUNDFX gate; vortex2 forbids it at parse time).
        if ( defined( $ctx->{conditional_build_features}{ 'TRACKER_SOUNDFX' } ) ) {
            add_build_feature( $ctx, 'AUDIO_SFX_BACKEND_ZX_AY' );
        }
    }

    # AU4-3: derive CPC audio backend macros. Factored into its own sub so
    # the screen-less CPC fast path (which bypasses fix_feature_dependencies)
    # can derive them too — see derive_cpc_audio_backend_features.
    derive_cpc_audio_backend_features( $ctx );

    # AU3-5: rename the legacy BUILD_FEATURE_TRACKER* capability macros to
    # the BUILD_FEATURE_AUDIO_* family (doc/multiplatform-plan/audio.md
    # §3.2). The old names are emitted *in parallel indefinitely* as
    # permanent silent aliases per README §5.6 — external games that
    # #ifdef on the old macros keep building forever. Mapping:
    #   BUILD_FEATURE_TRACKER          -> BUILD_FEATURE_AUDIO_MUSIC
    #   BUILD_FEATURE_TRACKER_ARKOS2   -> BUILD_FEATURE_AUDIO_MUSIC_ARKOS2
    #   BUILD_FEATURE_TRACKER_VORTEX2  -> BUILD_FEATURE_AUDIO_MUSIC_VORTEX2
    #   BUILD_FEATURE_TRACKER_SOUNDFX  -> BUILD_FEATURE_AUDIO_SFX_TRACKER
    if ( defined( $ctx->{conditional_build_features}{ 'TRACKER' } ) ) {
        add_build_feature( $ctx, 'AUDIO_MUSIC' );
    }
    if ( defined( $ctx->{conditional_build_features}{ 'TRACKER_ARKOS2' } ) ) {
        add_build_feature( $ctx, 'AUDIO_MUSIC_ARKOS2' );
    }
    if ( defined( $ctx->{conditional_build_features}{ 'TRACKER_VORTEX2' } ) ) {
        add_build_feature( $ctx, 'AUDIO_MUSIC_VORTEX2' );
    }
    if ( defined( $ctx->{conditional_build_features}{ 'TRACKER_SOUNDFX' } ) ) {
        add_build_feature( $ctx, 'AUDIO_SFX_TRACKER' );
    }

    # additional fixes here...
}

1;

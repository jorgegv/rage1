package RAGE::Datagen::Validate;

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
## RAGE::Datagen::Validate — game-data consistency checks for datagen (Task 6,
## Stage 2 extraction).  Moved verbatim from tools/datagen.pl; the shared model
## globals live in the RAGE::Datagen::Context object ($ctx), threaded in as the
## first positional arg of each sub and reached as $ctx->{all_btiles},
## $ctx->{all_screens}, $ctx->{all_sprites}, $ctx->{all_items},
## $ctx->{game_config}; the helper subs from sibling modules
## (is_build_feature_enabled / add_build_feature from BuildFeatures,
## optional_hex_decode from Util) are imported here.  Behaviour (and any emitted
## bytes / warnings / fatal-error counts) is unchanged.
##
## NOTE: check_game_config_is_valid intentionally MUTATES $ctx->{game_config}
## (defaults zx_target / color mode, decodes SUB addresses) and calls
## add_build_feature — those writes act on the same shared state datagen.pl uses
## afterwards.
##
################################################################################

use strict;
use warnings;
use utf8;

use RAGE::Datagen::BuildFeatures qw( is_build_feature_enabled add_build_feature );
use RAGE::Datagen::Util qw( optional_hex_decode );

use Exporter 'import';
our @EXPORT_OK = qw( check_game_config_is_valid run_consistency_checks );

sub check_screen_sprites_are_valid {
    my $ctx = shift;
    my $errors = 0;
    my %is_valid_sprite = map { $_->{'name'}, 1 } @{ $ctx->{all_sprites} };
    foreach my $screen ( @{ $ctx->{all_screens} } ) {
        foreach my $sprite ( @{ $screen->{'sprites'} } ) {
            if ( not $is_valid_sprite{ $sprite->{'name'} } ) {
                warn sprintf( "Screen '%s': undefined sprite '%s'\n", $screen->{'name'}, $sprite->{'name'} );
                $errors++;
            }
        }
    }
    return $errors;
}

sub check_screen_btiles_are_valid {
    my $ctx = shift;
    my $errors = 0;
    my %is_valid_btile = map { $_->{'name'}, 1 } @{ $ctx->{all_btiles} };
    foreach my $screen ( @{ $ctx->{all_screens} } ) {
        foreach my $btile ( @{ $screen->{'btiles'} } ) {
            if ( not defined( $btile->{'btile'} ) ) {
                warn sprintf( "Screen '%s': %s has no associated btile attribute\n", $screen->{'name'}, $btile->{'type'} );
                $errors++;
                next;
            }
            if ( not $is_valid_btile{ $btile->{'btile'} } ) {
                warn sprintf( "Screen '%s': undefined btile '%s'\n", $screen->{'name'}, $btile->{'btile'} );
                $errors++;
            }
        }
    }
    return $errors;
}

# items are btiles
sub check_screen_items_are_valid {
    my $ctx = shift;
    my $errors = 0;
    my %is_valid_btile = map { $_->{'name'}, 1 } @{ $ctx->{all_btiles} };
    foreach my $screen ( @{ $ctx->{all_screens} } ) {
        foreach my $item ( map { $ctx->{all_items}[ $_ ] } @{ $screen->{'items'} } ) {
            if ( not $is_valid_btile{ $item->{'btile'} } ) {
                warn sprintf( "Screen '%s': undefined btile '%s' for item '%s'\n",
                    $screen->{'name'},
                    $item->{'btile'},
                    $item->{'name'},
                );
                $errors++;
            }
        }
    }
    return $errors;
}

sub check_game_config_is_valid {
    my $ctx = shift;
    my $errors = 0;
    # T2-6: CPC platforms have no ZX_TARGET concept; skip the check.
    my $is_cpc = ( defined( $ctx->{game_config}->{'platform'} ) and
                   $ctx->{game_config}->{'platform'} =~ /^cpc/ );
    if ( $is_cpc ) {
        # For CPC, set a synthetic zx_target so the rest of datagen.pl's
        # ZX-centric code (dataset layout, 48K fallback paths) degrades
        # gracefully to the 48K (flat/no-banking) code path.  This is
        # intentionally the most conservative fallback.
        $ctx->{game_config}->{'zx_target'} = '48' unless defined( $ctx->{game_config}->{'zx_target'} );
    } elsif ( defined( $ctx->{game_config}->{'zx_target'} ) ) {
        ( $ctx->{game_config}->{'zx_target'} eq '48' ) or
        ( $ctx->{game_config}->{'zx_target'} eq '128' ) or do {
            warn sprintf( "Game Config: invalid '%s' value for 'zx_target' setting", $ctx->{game_config}->{'zx_target'} );
            $errors++;
        }
    } else {
        $ctx->{game_config}->{'zx_target'} = '48';
        warn "Game Config: 'zx_target' not defined - building for 48K mode\n";
    }
    if ( is_build_feature_enabled( $ctx, 'INVENTORY') and not defined( $ctx->{game_config}->{'inventory_area'} ) ) {
        warn "Game Config: using INVENTORY feature, but no INVENTORY_AREA defined\n";
        $errors++;
    }

    if ( is_build_feature_enabled( $ctx, 'SCREEN_TITLES') and not defined( $ctx->{game_config}->{'title_area'} ) ) {
        warn "Game Config: using SCREEN_TITLES feature, but no TITLE_AREA defined\n";
        $errors++;
    }

    # tracker configuration
    if ( defined( $ctx->{game_config}->{'tracker'} ) ) {
        if ( not defined( $ctx->{game_config}->{'tracker'}{'type'} ) ) {
            warn "TRACKER: tracker TYPE must be specified\n";
            $errors++;
        }
        if ( not scalar( @{ $ctx->{game_config}->{'tracker'}{'songs'} } ) ) {
            warn "TRACKER: no music songs defined (TRACKER_SONG directive)\n";
            $errors++;
        }
        if ( defined( $ctx->{game_config}->{'tracker'}{'in_game_song'} ) and
                not grep { $_->{'name'} eq $ctx->{game_config}->{'tracker'}{'in_game_song'} }
                @{ $ctx->{game_config}->{'tracker'}{'songs'} } ) {
            warn "TRACKER: unknown song name in IN_GAME_SONG parameter\n";
            $errors++;
        }
        # AU4-3: TRACKER is supported on ZX128 (AY) and on CPC (AY). It is
        # NOT supported on ZX48 (no AY hardware exposed by the engine).
        my $tracker_platform = $ctx->{game_config}->{'platform'} // '';
        my $is_cpc = ( $tracker_platform =~ /^cpc/ );
        if ( ( not $is_cpc ) and ( ( $ctx->{game_config}->{'zx_target'} // '' ) ne '128' ) ) {
            warn "TRACKER: must be used together with ZX_TARGET = 128 (or a CPC platform)\n";
            $errors++;
        }
        # AU4-3: vortex2 is a ZX-only tracker; CPC only supports arkos2.
        if ( $is_cpc and ( lc( $ctx->{game_config}->{'tracker'}{'type'} ) eq 'vortex2' ) ) {
            warn "TRACKER: tracker type vortex2 is not supported on CPC (use arkos2)\n";
            $errors++;
        }
        if ( ( lc( $ctx->{game_config}->{'tracker'}{'type'} ) eq 'vortex2' ) ) {
            if ( defined(  $ctx->{game_config}->{'tracker'}{'fxtable'} ) ) {
                warn "TRACKER: vortex2 tracker does not support sound effects (TRACKER_FXTABLE directive)\n";
                $errors++;
            }
            if ( defined(  $ctx->{game_config}->{'tracker'}{'fx_channel'} ) ) {
                warn "TRACKER: vortex2 tracker does not support sound effects (FX_CHANNEL directive)\n";
                $errors++;
            }
            if ( defined(  $ctx->{game_config}->{'tracker'}{'fx_volume'} ) ) {
                warn "TRACKER: vortex2 tracker does not support sound effects (FX_VOLUME directive)\n";
                $errors++;
            }
        }
    }

    # check color mode, if nothing specified set to FULL
    if ( defined( $ctx->{game_config}->{'color'} ) ) {
        if ( not defined( $ctx->{game_config}->{'color'}{'mode'} ) ) {
            warn "COLOR: MODE parameter is mandatory\n";
            $errors++;
        } else {
            if ( lc( $ctx->{game_config}->{'color'}{'mode'} ) eq 'mono' ) {
                if ( not defined( $ctx->{game_config}->{'color'}{'gamearea_attr'} ) ) {
                    warn "COLOR: when MODE=MONO, GAMEAREA_ATTR parameter is mandatory\n";
                    $errors++;
                }
            } elsif ( lc( $ctx->{game_config}->{'color'}{'mode'} ) ne 'full' ) {
                warn "COLOR: parameter MODE must be one of MONO, FULL\n";
                $errors++;
            }
        }
    } else {
        $ctx->{game_config}->{'color'}{'mode'} = 'full';
    }
    # now we are sure color mode is one of 'full' or 'mono'
    if ( lc( $ctx->{game_config}->{'color'}{'mode'} ) eq 'mono' ) {
        add_build_feature( $ctx, 'GAMEAREA_COLOR_MONO' );
    } else {
        add_build_feature( $ctx, 'GAMEAREA_COLOR_FULL' );
    }

    # check SUBs configuration
    my %used_sub_names;
    foreach my $sub ( @{ $ctx->{game_config}->{'single_use_blobs'} } ) {
        if ( not defined( $sub->{'org_address'} ) ) {
            $sub->{'org_address'} = $sub->{'load_address'};
        }
        if ( not defined( $sub->{'run_address'} ) ) {
            $sub->{'run_address'} = $sub->{'org_address'};
        }
        if ( not defined( $sub->{'compress'} ) ) {
            $sub->{'compress'} = 0;
        }
        $sub->{'load_address'} = optional_hex_decode( $sub->{'load_address'} );
        $sub->{'org_address'} = optional_hex_decode( $sub->{'org_address'} );
        $sub->{'run_address'} = optional_hex_decode( $sub->{'run_address'} );

        # at this point, NAME,LOAD_ADDRESS,ORG_ADDRESS,RUN_ADDRESS and COMPRESS are always defined
        # Now with the logic checks

        if ( $used_sub_names{ $sub->{'name'} }++ ) {
            warn "SINGLE_USE_BLOB: $sub->{'name'}: duplicate SUB name\n";
            $errors++;
        }

        if ( ( $sub->{'load_address'} < 0xC000 ) and not is_build_feature_enabled( $ctx, 'ZX_TARGET_128' ) ) {
            warn "SINGLE_USE_BLOB: $sub->{'name'}: LOAD_ADDRESS lower than 0xC000 can only be used in 128K mode games\n";
            $errors++;
        }

        if ( ( $sub->{'compress'} ) and ( $sub->{'load_address'} == $sub->{'org_address'} ) ) {
            warn "SINGLE_USE_BLOB: $sub->{'name'}: LOAD_ADDRESS and ORG_ADDRESS can't be the same if COMPRESS=1\n";
            $errors++;
        }
    }

    return $errors;
}

# this function is called from main
sub run_consistency_checks {
    my $ctx = shift;
    my $errors = 0;
    $errors += check_game_config_is_valid( $ctx );
    $errors += check_screen_sprites_are_valid( $ctx );
    $errors += check_screen_btiles_are_valid( $ctx );
    $errors += check_screen_items_are_valid( $ctx );
    die sprintf( "*** %d errors were found in configuration\n", $errors )
        if ( $errors );
}

1;

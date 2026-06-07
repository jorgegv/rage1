package RAGE::Datagen::GameConfig;

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
## RAGE::Datagen::GameConfig — game-functions, game-areas, the game_data.h
## header/ending, the game-configuration emitter, misc data, conditional
## build-feature macros and the interrupt-configuration values, for datagen
## (Task 6, Stage 2 extraction).  Moved verbatim from tools/datagen.pl; the
## shared globals live in the RAGE::Datagen::Context object ($ctx), threaded in
## as the first positional arg of each sub and reached as $ctx->{game_config},
## $ctx->{all_screens}, $ctx->{all_sprites}, $ctx->{sprite_name_to_index},
## $ctx->{screen_name_to_index}, $ctx->{hero}, $ctx->{max_flow_var_id},
## $ctx->{conditional_build_features}, $ctx->{cfg}, $ctx->{build_dir},
## $ctx->{valid_game_functions} and the emit accumulators $ctx->{c_game_data_lines},
## $ctx->{h_game_data_lines} and $ctx->{h_build_features_lines}.
## get_gfx_backend, add_build_feature and is_build_feature_enabled are imported
## from RAGE::Datagen::BuildFeatures.  Behaviour (and emitted bytes) is
## unchanged.
##
## Exported: generate_game_functions, generate_game_areas, generate_h_header,
## generate_h_ending, generate_game_config, generate_misc_data,
## generate_conditional_build_features, generate_configuration_values.
## generate_single_game_area is module-private (only called by
## generate_game_areas).
##
################################################################################

use strict;
use warnings;
use utf8;

use RAGE::Datagen::BuildFeatures qw( get_gfx_backend add_build_feature is_build_feature_enabled );

use Exporter 'import';
our @EXPORT_OK = qw(
    generate_game_functions generate_game_areas generate_h_header
    generate_h_ending generate_game_config generate_misc_data
    generate_conditional_build_features generate_configuration_values
);

sub generate_game_functions {
    my $ctx = shift;
    push @{ $ctx->{h_game_data_lines} }, "// game config\n";

    # generate extern declarations, only for functions in 'home' codeset
    push @{ $ctx->{h_game_data_lines} }, join( "\n",
        map {
            sprintf( "void %s( void );", $ctx->{game_config}->{'game_functions'}{ $_ }{'name'} )
        } grep {
            ( $ctx->{game_config}->{'zx_target'} eq '48' ) or
            ( $ctx->{game_config}->{'game_functions'}{ $_ }{'codeset'} eq 'home' )
        } grep {
            $_ ne 'custom'
        } sort keys %{ $ctx->{game_config}->{'game_functions'} } );
    push @{ $ctx->{h_game_data_lines} }, "\n\n";

    # generate macro calls for all functions
    push @{ $ctx->{h_game_data_lines} }, join( "\n",
        map {
            sprintf( "#define run_game_function_%-30s %s",
                lc( $_ ) . '()',
                ( defined( $ctx->{game_config}->{'game_functions'}{ $_ } ) ?
                  $ctx->{game_config}->{'game_functions'}{ $_ }{'codeset_function_call_macro'} :
                  '' ),
            )
        } grep {
            $_ ne 'custom'
        } sort @{ $ctx->{valid_game_functions} }
    );

    push @{ $ctx->{h_game_data_lines} }, "\n\n";
}

sub generate_single_game_area {
    my $ctx = shift;
    my $area = shift;
    return if not defined ( $ctx->{game_config}->{ $area } );
    push @{ $ctx->{c_game_data_lines} }, "\n" . join( "\n", map {
        sprintf( "gfx_rect_t %s = { %s_TOP, %s_LEFT, %s_WIDTH, %s_HEIGHT };",
            $_, ( uc( $_ ) ) x 4 )
        } ( $area )
    ) . "\n";
    push @{ $ctx->{h_game_data_lines} }, "\n" . join( "\n", map {
            "// " .uc( $_ ). " definitions\n" .
            sprintf( "#define %s_TOP	%d\n", uc( $_ ), $ctx->{game_config}->{ $_ }{'top'} ) .
            sprintf( "#define %s_LEFT	%d\n", uc( $_ ), $ctx->{game_config}->{ $_ }{'left'} ) .
            sprintf( "#define %s_BOTTOM	%d\n", uc( $_ ), $ctx->{game_config}->{ $_ }{'bottom'} ) .
            sprintf( "#define %s_RIGHT	%d\n", uc( $_ ), $ctx->{game_config}->{ $_ }{'right'} ) .
            sprintf( "#define %s_WIDTH	( %s_RIGHT - %s_LEFT + 1 )\n", uc( $_ ), uc( $_ ), uc( $_ ) ) .
            sprintf( "#define %s_HEIGHT	( %s_BOTTOM - %s_TOP + 1 )\n", uc( $_ ), uc( $_ ), uc( $_ ) ) .
            sprintf( "extern gfx_rect_t %s;\n", $_ )
        } ( $area )
    ) . "\n\n";
}

sub generate_game_areas {
    my $ctx = shift;

    # output mandatory game areas
    push @{ $ctx->{c_game_data_lines} }, "// screen areas\n";
    foreach my $area ( qw( game_area lives_area debug_area ) ) {
        generate_single_game_area( $ctx, $area );
    }

    # output optional game areas
    if ( is_build_feature_enabled( $ctx, 'INVENTORY' ) ) {
        generate_single_game_area( $ctx, 'inventory_area' );
    }
    if ( is_build_feature_enabled( $ctx, 'SCREEN_TITLES' ) ) {
        generate_single_game_area( $ctx, 'title_area' );
    }

}

sub generate_h_header {
    my $ctx = shift;
    push @{ $ctx->{h_game_data_lines} }, <<GAME_DATA_H_1
#ifndef _GAME_DATA_H
#define _GAME_DATA_H

#include <stdint.h>

#include "rage1/gfx.h"
#include "rage1/dataset.h"

extern struct dataset_assets_s all_assets_dataset_home;

GAME_DATA_H_1
;
}

sub generate_h_ending {
    my $ctx = shift;
    push @{ $ctx->{h_game_data_lines} }, <<GAME_DATA_H_4
#endif // _GAME_DATA_H
GAME_DATA_H_4
;
}

sub generate_game_config {
    # Emit the BUILD_FEATURE_GFX_BACKEND_<X> macro (defaults to SP1 if not
    # set in game config). The legacy BUILD_FEATURE_SPRITE_ENGINE_<X>
    # macro is also emitted as a silent, indefinite alias — old engine
    # code and external games can keep using either spelling forever
    # (per doc/multiplatform-plan/gfx.md §5.6 / README §5.6). No removal
    # is scheduled.
    my $ctx = shift;
    my $engine_upper = uc( get_gfx_backend( $ctx ) );
    add_build_feature( $ctx, 'GFX_BACKEND_'   . $engine_upper );
    add_build_feature( $ctx, 'SPRITE_ENGINE_' . $engine_upper );

    push @{ $ctx->{h_game_data_lines} }, "\n// game configuration data\n";
    push @{ $ctx->{h_game_data_lines} }, sprintf( "#define MAP_NUM_SCREENS\t%d\n", scalar( @{ $ctx->{all_screens} } ) );
    push @{ $ctx->{h_game_data_lines} }, sprintf( "#define MAP_INITIAL_SCREEN\t%d\n", $ctx->{screen_name_to_index}{ $ctx->{game_config}->{'screen'}{'initial'} } );
    push @{ $ctx->{h_game_data_lines} }, sprintf( "#define DEFAULT_BG_ATTR ( %s )\n", $ctx->{game_config}->{'default_bg_attr'} );

    push @{ $ctx->{h_game_data_lines} }, "\n// sound effect constants\n";
    foreach my $effect ( keys %{$ctx->{game_config}->{'sounds'}} ) {
        push @{ $ctx->{h_game_data_lines} }, sprintf( "#define SOUND_%s %s\n", uc( $effect ), $ctx->{game_config}->{'sounds'}{ $effect } );
    }

    # check maximum sprite usage
    my $max_sprites = 0;
    my $max_spritechars = 0;

    # start with the screens
    foreach my $screen ( @{ $ctx->{all_screens} } ) {
        my $screen_sprites = 0;
        my $screen_spritechars = 0;
        foreach my $sprite ( map { $ctx->{all_sprites}[ $ctx->{sprite_name_to_index}{ $_->{'sprite'} } ] } @{ $screen->{'enemies'} } ) {
            $screen_sprites++;
            # remember: SP1 sprites have 1 extra row and col
            $screen_spritechars += ( $sprite->{'rows'} + 1 ) * ( $sprite->{'cols'} + 1 )
        }
        if ( $screen_sprites > $max_sprites ) {
            $max_sprites = $screen_sprites;
        }
        if ( $screen_spritechars > $max_spritechars ) {
            $max_spritechars = $screen_spritechars;
        }
    }

    # add the hero sprite - just 1
    $max_sprites++;
    my $hs = $ctx->{all_sprites}[ $ctx->{sprite_name_to_index}{ $ctx->{hero}->{'sprite'} } ];
    $max_spritechars += ( $hs->{'rows'} + 1 ) * ( $hs->{'cols'} + 1 );

    # add the bullet sprites - the N bullets
    if ( defined( $ctx->{hero}->{'bullet'} ) ) {
        $max_sprites += $ctx->{hero}->{'bullet'}{'max_bullets'};
        my $bs = $ctx->{all_sprites}[ $ctx->{sprite_name_to_index}{ $ctx->{hero}->{'bullet'}{'sprite'} } ];
        $max_spritechars += $ctx->{hero}->{'bullet'}{'max_bullets'} * ( $bs->{'rows'} + 1 ) * ( $bs->{'cols'} + 1 );
    }

    # JSP pool-sizing constants (only emitted when gfx backend is JSP)
    if ( get_gfx_backend( $ctx ) eq 'jsp' ) {
        my $max_sprite_rows = ( sort { $b <=> $a } map { $_->{'rows'} } @{ $ctx->{all_sprites} } )[0];
        my $max_sprite_cols = ( sort { $b <=> $a } map { $_->{'cols'} } @{ $ctx->{all_sprites} } )[0];
        push @{ $ctx->{h_game_data_lines} }, <<EOF_JSP_POOL
// JSP sprite pool sizing constants
#define GFX_JSP_MAX_SPRITES		$max_sprites
#define GFX_JSP_MAX_SPRITE_ROWS		$max_sprite_rows
#define GFX_JSP_MAX_SPRITE_COLS		$max_sprite_cols

EOF_JSP_POOL
;
    }

    # 20 bytes for a safety margin, plus 6 bytes per allocation, plus 20
    # bytes per sprite, plus 24 bytes per sprite char
    my $max_heap_usage = 20 + $max_sprites * (20 + 6) + $max_spritechars * (24 + 6);

    # max dataset size: memory from $5B00->$7FFF minus the heap
    # 128K interrupt config is the same for both sprite engines
    my $int_key = 'interrupts_128';
    my $max_dataset_size = (
        ( $ctx->{cfg}->{ $int_key }{'base_code_address'} =~ /^0x/ ?
            hex( $ctx->{cfg}->{ $int_key }{'base_code_address'} ) :
            $ctx->{cfg}->{ $int_key }{'base_code_address'} )
         - 0x5B00 ) - $max_heap_usage;

    push @{ $ctx->{h_game_data_lines} }, <<EOF_BLDCFG1

// maximum sprite and heap usage
#define BUILD_MAX_NUM_SPRITES_PER_SCREEN	$max_sprites
#define BUILD_MAX_NUM_SPRITECHARS_PER_SCREEN	$max_spritechars

// 20 bytes for a safety margin, plus 6 bytes per allocation, plus 20
// bytes per sprite, plus 24 bytes per sprite char
#define BUILD_MAX_HEAP_SPRITE_USAGE		$max_heap_usage

// max dataset size when uncompressed to \$5B00
#define	BUILD_MAX_DATASET_SIZE			$max_dataset_size

EOF_BLDCFG1
;


    # add CUSTOM_CHARSET definitions of present
    if ( defined( $ctx->{game_config}->{'custom_charset'} ) ) {
        my ( $char_min, $char_max ) = ( 32, 127 );	# defaults: all ZX ASCII range
        if ( $ctx->{game_config}->{'custom_charset'}{'range'} ) {
            $ctx->{game_config}->{'custom_charset'}{'range'} =~ m/^(\d+)\-(\d+)$/;
            ( $char_min, $char_max ) = ( $1, $2 );
        }
        push @{ $ctx->{h_game_data_lines} }, "\n// custom charset minimum and maximum characters\n";
        push @{ $ctx->{h_game_data_lines} }, sprintf( "#define CUSTOM_CHARSET_MIN_CHAR %d\n", $char_min );
        push @{ $ctx->{h_game_data_lines} }, sprintf( "#define CUSTOM_CHARSET_MAX_CHAR %d\n", $char_max );

        # ...and CUSTOM_CHARSET data to game_data.c
        open( CHAR_DATA, "$ctx->{build_dir}/$ctx->{game_config}->{'custom_charset'}{'file'}" ) or
            die "CUSTOM_CHARSET: could not open $ctx->{game_config}->{'custom_charset'}{'file'} for reading\n";
        binmode CHAR_DATA;
        my $data;
        my $data_offset = ( $char_min - 32 ) * 8;
        my $data_size = ( $char_max - $char_min + 1 ) * 8;
        if ( read( CHAR_DATA, $data, $data_size, $data_offset ) != $data_size ) {
            die "CUSTOM_CHARSET: error reading $data_size bytes from $ctx->{game_config}->{'custom_charset'}{'file'}, offset $data_offset\n";
        }
        close CHAR_DATA;
        push @{ $ctx->{c_game_data_lines} }, "\n// custom charset binary data\n";
        push @{ $ctx->{c_game_data_lines} }, sprintf( "// first char: %d ('%c'), last char: %d ('%c')\n", $char_min, $char_min, $char_max, $char_max );
        push @{ $ctx->{c_game_data_lines} }, "uint8_t custom_charset[ ( CUSTOM_CHARSET_MAX_CHAR - CUSTOM_CHARSET_MIN_CHAR + 1 ) * 8 ] = {\n";
        push @{ $ctx->{c_game_data_lines} }, "\t" . join( ", ", map { sprintf "0x%02x", $_ } unpack('C*', $data ) ) . "\n";
        push @{ $ctx->{c_game_data_lines} }, "};\n\n";
    }

    # add gamearea default attribute if monochrome mode is used
    if ( defined( $ctx->{game_config}->{'color'}{'gamearea_attr'} ) ) {
        push @{ $ctx->{h_game_data_lines} }, "\n// gamearea default attr for monochrome mode\n";
        push @{ $ctx->{h_game_data_lines} }, sprintf( "#define GAMEAREA_COLOR_MONO_ATTR (%s)\n\n", $ctx->{game_config}->{'color'}{'gamearea_attr'} );
    }

    # add custom_state_data config
    if ( defined( $ctx->{game_config}->{'custom_state_data'} ) ) {
        push @{ $ctx->{h_game_data_lines} }, "\n// custom state data size\n";
        push @{ $ctx->{h_game_data_lines} }, sprintf( "#define CUSTOM_STATE_DATA_SIZE %d\n\n", $ctx->{game_config}->{'custom_state_data'}{'size'} );
    }

}

# generate data that does not logically fit elsewhere
sub generate_misc_data {
    my $ctx = shift;

    # number of enemies at game reset
    my $count = 0;
    foreach my $screen ( @{ $ctx->{all_screens} } ) {
        $count += scalar( @{ $screen->{'enemies'} } );
    }
    push @{ $ctx->{h_game_data_lines} }, "\n// Total number of enemies in the game\n";
    push @{ $ctx->{h_game_data_lines} }, sprintf( "#define\tGAME_NUM_TOTAL_ENEMIES\t%d\n\n", $count );

    # number of flow vars
    if ( defined( $ctx->{max_flow_var_id} ) ) {
        push @{ $ctx->{h_game_data_lines} }, "\n// Total number of flow vars in the game\n";
        push @{ $ctx->{h_game_data_lines} }, sprintf( "#define\tGAME_NUM_FLOW_VARS\t%d\n\n", ( $ctx->{max_flow_var_id} + 1 ) );
    }
}

sub generate_conditional_build_features {
    my $ctx = shift;

    # output build features for conditional compiles
    push @{ $ctx->{h_build_features_lines} }, <<EOF_FEATURES1

////////////////////////////////////////////////////////////////
// BUILD FEATURE MACROS FOR CONDITIONAL COMPILES
////////////////////////////////////////////////////////////////

#ifndef _FEATURES_H
#define _FEATURES_H

EOF_FEATURES1
;

    foreach my $f ( sort keys %{ $ctx->{conditional_build_features} } ) {
        push @{ $ctx->{h_build_features_lines} }, sprintf( "#define BUILD_FEATURE_%s\n", uc($f) );
    }

    push @{ $ctx->{h_build_features_lines} }, <<EOF_FEATURES2

////////////////////////////////////////////////////////////////
// END OF BUILD FEATURE MACROS
////////////////////////////////////////////////////////////////

#endif // _FEATURES_H

EOF_FEATURES2
;

}

sub generate_configuration_values {
    my $ctx = shift;

    # interrupt configuration values (same for both sprite engines)
    my $int_key = 'interrupts_128';
    push @{ $ctx->{h_game_data_lines} }, "// Interrupt configuration\n";
    foreach my $k ( qw( iv_table_addr isr_vector_byte base_code_address ) ) {
        my $value = $ctx->{cfg}->{ $int_key }{ $k };
        if ( $value =~ /^0x/ ) {
            $value = hex( $value );
        }
        push @{ $ctx->{h_game_data_lines} }, sprintf( "#define RAGE1_CONFIG_INT128_%-29s 0x%x\n", uc($k), $value );
        if ( $k eq 'isr_vector_byte' ) {
            push @{ $ctx->{h_game_data_lines} }, sprintf( "#define RAGE1_CONFIG_INT128_ISR_ADDRESS                   0x%02x%02x\n",
                $value, $value
            );
        }
    }
    push @{ $ctx->{h_game_data_lines} }, "\n";

}

1;

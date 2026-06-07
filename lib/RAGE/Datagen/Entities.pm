package RAGE::Datagen::Entities;

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
## RAGE::Datagen::Entities — hero, bullets, items and crumb-types validation
## and C/header emission for datagen (Task 6, Stage 2 extraction).  Moved
## verbatim from tools/datagen.pl; the only edits are the mechanical scaffold
## bindings: the shared globals are reached via their RAGE::Datagen::Context
## aliases ($main::hero, @main::all_sprites, @main::all_items,
## @main::all_crumb_types, %main::sprite_name_to_index,
## %main::dataset_dependency, $main::game_config and the header/main-C emit
## accumulators @main::h_game_data_lines and @main::c_game_data_lines).
## add_build_feature is imported from RAGE::Datagen::BuildFeatures.  Behaviour
## (and emitted bytes) is unchanged.
##
## Exported: validate_and_compile_hero (parse-time), generate_hero,
## generate_bullets, generate_items, generate_crumb_types (emit-time).
##
################################################################################

use strict;
use warnings;
use utf8;

# scaffold aliases (RAGE::Datagen::Context) populated at runtime by datagen.pl;
# silence the benign "used only once" check for these main:: globals.
no warnings 'once';

use RAGE::Datagen::BuildFeatures qw( add_build_feature );

use Exporter 'import';
our @EXPORT_OK = qw(
    validate_and_compile_hero generate_hero generate_bullets
    generate_items generate_crumb_types
);

sub validate_and_compile_hero {
    my $hero = shift;
    defined( $hero->{'name'} ) or
        die "Hero has no NAME\n";
    defined( $hero->{'sprite'} ) or
        die "Hero has no SPRITE\n";
    defined( $hero->{'sequence_up'} ) or
        die "Hero has no SEQUENCE_UP\n";
    defined( $hero->{'sequence_down'} ) or
        die "Hero has no SEQUENCE_DOWN\n";
    defined( $hero->{'sequence_left'} ) or
        die "Hero has no SEQUENCE_LEFT\n";
    defined( $hero->{'sequence_right'} ) or
        die "Hero has no SEQUENCE_RIGHT\n";
    defined( $hero->{'animation_delay'} ) or
        die "Hero has no ANIMATION_DELAY\n";
    defined( $hero->{'lives'} ) or
        die "Hero has no LIVES\n";
    defined( $hero->{'hstep'} ) or
        die "Hero has no HSTEP\n";
    defined( $hero->{'vstep'} ) or
        die "Hero has no VSTEP\n";

    # ensure DAMAGE_MODE is always defined
    # remember LIVES are handled separately for compatibility
    my $default_damage_mode = {
        health_max	=> 1,
        enemy_damage	=> 1,
        immunity_period	=> 0,
    };
    my $damage_mode;
    if ( defined( $hero->{'damage_mode'} ) ) {
        # merge the provided parameters with the defaults
        $damage_mode = { %{ $default_damage_mode }, %{ $hero->{'damage_mode'} } };
    } else {
        $damage_mode = $default_damage_mode;
    }
    $hero->{'damage_mode'} = $damage_mode;

    # check for bullet
    if ( defined( $hero->{'bullet'} ) ) {
        add_build_feature( 'HERO_HAS_WEAPON' );
        if ( defined( $hero->{'bullet'}{'initially_enabled'} ) ) {
            add_build_feature( 'INVENTORY' );	# if it not initially enabled we need inventory
            if ( ( not $hero->{'bullet'}{'initially_enabled'} ) and not defined( $hero->{'bullet'}{'weapon_item'} ) ) {
                die "HERO: When BULLET is INITIALLY_ENABLED=0, a WEAPON_ITEM is needed\n";
            }
        } else {
            $hero->{'bullet'}{'initially_enabled'} = 1;
            add_build_feature( 'HERO_WEAPON_ALWAYS_ENABLED' );
        }
        if ( $hero->{'bullet'}{'autofire'} || 0 ) {
            add_build_feature( 'HERO_WEAPON_AUTOFIRE' );
        }
    }
}

sub generate_hero {
    my $num_lives 		= $main::hero->{'lives'}{'num_lives'};
    my $lives_btile_num		= 'BTILE_ID_' . uc( $main::hero->{'lives'}{'btile'} );
    my $sprite			= $main::hero->{'sprite'};
    my $num_sprite		= $main::sprite_name_to_index{ $main::hero->{'sprite'} };
    my $width			= $main::all_sprites[ $num_sprite ]{'cols'} * 8;
    my $height			= $main::all_sprites[ $num_sprite ]{'rows'} * 8;
    my $sequence_up		= $main::all_sprites[ $num_sprite ]{'sequence_name_to_index'}{ $main::hero->{'sequence_up'} };
    my $sequence_down		= $main::all_sprites[ $num_sprite ]{'sequence_name_to_index'}{ $main::hero->{'sequence_down'} };
    my $sequence_left		= $main::all_sprites[ $num_sprite ]{'sequence_name_to_index'}{ $main::hero->{'sequence_left'} };
    my $sequence_right		= $main::all_sprites[ $num_sprite ]{'sequence_name_to_index'}{ $main::hero->{'sequence_right'} };
    my $steady_frame_up		= $main::hero->{'steady_frames'}{'up'} || 0;
    my $steady_frame_down	= $main::hero->{'steady_frames'}{'down'} || 0;
    my $steady_frame_left	= $main::hero->{'steady_frames'}{'left'} || 0;
    my $steady_frame_right	= $main::hero->{'steady_frames'}{'right'} || 0;
    my $delay			= $main::hero->{'animation_delay'};
    my $hstep			= $main::hero->{'hstep'};
    my $vstep			= $main::hero->{'vstep'};
    my $hstep_diag		= $main::hero->{'hstep'} * cos( atan2( $vstep, $hstep ) );
    my $vstep_diag		= $main::hero->{'vstep'} * sin( atan2( $vstep, $hstep ) );
    my $hstep_ffp		= int( 256 * $hstep );
    my $vstep_ffp		= int( 256 * $vstep );
    my $hstep_diag_ffp		= int( 256 * $hstep_diag );
    my $vstep_diag_ffp		= int( 256 * $vstep_diag );
    my $local_num_sprite	= $main::dataset_dependency{'home'}{'sprite_global_to_dataset_index'}{ $num_sprite };
    my $health_max		= $main::hero->{'damage_mode'}{'health_max'};
    my $enemy_damage		= $main::hero->{'damage_mode'}{'enemy_damage'};
    my $immunity_period		= $main::hero->{'damage_mode'}{'immunity_period'};
    my $health_display_function	= $main::hero->{'damage_mode'}{'health_display_function'} || '';

    # Phase G4-4 (gfx.md §G4-4): movement bounds are screen pixel coordinates
    # so their natural HAL type is gfx_xpos_t / gfx_ypos_t.  We emit the bare
    # integer literal here so the #define stays usable in compile-time
    # arithmetic (e.g. `y.value <= HERO_MOVE_YMIN * 256` in banked hero.c).
    # On ZX gfx_{x,y}pos_t is uint8_t and the bare literal already fits.  On
    # a future CPC / Layer-2 backend a sibling tree will emit the same
    # #defines wrapped in a `(gfx_xpos_t)( ... )` cast so the 16-bit width
    # flows through ffp24_t-style position structs (Risk R3 — handled in
    # the CPC bring-up, not here).
    my $move_xmin		= $main::game_config->{'game_area'}{'left'} * 8;
    my $move_xmax		= ( $main::game_config->{'game_area'}{'right'} + 1 ) * 8 - $width;
    my $move_ymin		= $main::game_config->{'game_area'}{'top'} * 8;
    my $move_ymax		= ( $main::game_config->{'game_area'}{'bottom'} + 1 ) * 8 - $height;

    push @main::h_game_data_lines, <<EOF_HERO1

/////////////////////////////
// Hero definition
/////////////////////////////

#define	HERO_SPRITE_ID			$local_num_sprite
#define	HERO_SPRITE_SEQUENCE_UP		$sequence_up
#define	HERO_SPRITE_SEQUENCE_DOWN	$sequence_down
#define	HERO_SPRITE_SEQUENCE_LEFT	$sequence_left
#define	HERO_SPRITE_SEQUENCE_RIGHT	$sequence_right
#define	HERO_SPRITE_STEADY_FRAME_UP	$steady_frame_up
#define	HERO_SPRITE_STEADY_FRAME_DOWN	$steady_frame_down
#define	HERO_SPRITE_STEADY_FRAME_LEFT	$steady_frame_left
#define	HERO_SPRITE_STEADY_FRAME_RIGHT	$steady_frame_right
#define	HERO_SPRITE_ANIMATION_DELAY	$delay
#define HERO_SPRITE_WIDTH		$width
#define HERO_SPRITE_HEIGHT		$height
// FFP value: 256 * $hstep
#define	HERO_MOVE_HSTEP			$hstep_ffp
// FFP value: 256 * $vstep
#define	HERO_MOVE_VSTEP			$vstep_ffp
// FFP value: 256 * $hstep_diag
#define	HERO_MOVE_HSTEP_DIAG		$hstep_diag_ffp
// FFP value: 256 * $vstep_diag
#define	HERO_MOVE_VSTEP_DIAG		$vstep_diag_ffp
// HERO_MOVE_X{MIN,MAX} / Y{MIN,MAX} are screen pixel coordinates with HAL
// type gfx_xpos_t / gfx_ypos_t (uint8_t on ZX, uint16_t on CPC/Layer-2).
// Emitted as bare #defines so they remain usable in compile-time arithmetic
// (e.g. `HERO_MOVE_YMIN * 256` in banked hero.c).  See gfx.md Phase G4-4.
#define	HERO_MOVE_XMIN			$move_xmin
#define	HERO_MOVE_XMAX			$move_xmax
#define	HERO_MOVE_YMIN			$move_ymin
#define	HERO_MOVE_YMAX			$move_ymax
#define	HERO_NUM_LIVES			$num_lives
#define	HERO_LIVES_BTILE_NUM		$lives_btile_num
#define HERO_HEALTH_MAX			$health_max
#define HERO_ENEMY_DAMAGE		$enemy_damage
#define HERO_IMMUNITY_PERIOD		$immunity_period
#define HERO_HEALTH_DISPLAY_FUNCTION	$health_display_function

EOF_HERO1
;

    if ( $health_display_function ne '' ) {
        push @main::h_game_data_lines, "// external declaration for custom health display function\n";
        push @main::h_game_data_lines, "void $health_display_function( void );\n\n";
    }

    # hero sprite must be always available - output sprite into home bank
}

sub generate_bullets {

    return if not defined( $main::hero->{'bullet'} );

    my $sprite = $main::all_sprites[ $main::sprite_name_to_index{ $main::hero->{'bullet'}{'sprite'} } ];
    my $sprite_name = $main::hero->{'bullet'}{'sprite'};
    my $sprite_index = $main::sprite_name_to_index{ $main::hero->{'bullet'}{'sprite'} };
    my $local_sprite_index = $main::dataset_dependency{'home'}{'sprite_global_to_dataset_index'}{ $sprite_index };
    my $width = $sprite->{'cols'} * 8;
    my $height = $sprite->{'rows'} * 8;
    my $max_bullets = $main::hero->{'bullet'}{'max_bullets'};
    my $dx = $main::hero->{'bullet'}{'dx'};
    my $dy = $main::hero->{'bullet'}{'dy'};
    my $delay = $main::hero->{'bullet'}{'delay'};
    my $reload_delay = $main::hero->{'bullet'}{'reload_delay'};
    my $xthresh = ( defined( $sprite->{'real_pixel_width'} ) ?
        ( 8 - ( $sprite->{'real_pixel_width'} % 8 ) + 1 ) % 8 :
        1 );
    my $ythresh = ( defined( $sprite->{'real_pixel_height'} ) ?
        ( 8 - ( $sprite->{'real_pixel_height'} % 8 ) + 1 ) % 8 :
        1 );
    # sprite frames for the different shot directions. If not defined, use frame 0
    my ( $sprite_frame_up, $sprite_frame_down, $sprite_frame_left, $sprite_frame_right ) = map {
        $main::hero->{'bullet'}{ $_ } || 0,
    } qw ( sprite_frame_up sprite_frame_down sprite_frame_left sprite_frame_right );

    my $initial_enable = $main::hero->{'bullet'}{'initially_enabled'} ? 'F_HERO_CAN_SHOOT' : 0;

    push @main::h_game_data_lines, <<EOF_BULLET4

//////////////////////////////
// Bullets definition
//////////////////////////////

#define	BULLET_MAX_BULLETS		$max_bullets
#define	BULLET_SPRITE_WIDTH		$width
#define	BULLET_SPRITE_HEIGHT		$height
#define BULLET_SPRITE_ID		$local_sprite_index
#define	BULLET_SPRITE_XTHRESH		$xthresh
#define	BULLET_SPRITE_YTHRESH		$ythresh
#define	BULLET_MOVEMENT_DX		$dx
#define	BULLET_MOVEMENT_DY		$dy
#define	BULLET_MOVEMENT_DELAY		$delay
#define	BULLET_RELOAD_DELAY		$reload_delay
#define BULLET_SPRITE_FRAME_UP		$sprite_frame_up
#define BULLET_SPRITE_FRAME_DOWN	$sprite_frame_down
#define BULLET_SPRITE_FRAME_LEFT	$sprite_frame_left
#define BULLET_SPRITE_FRAME_RIGHT	$sprite_frame_right

#define BULLET_INITIAL_ENABLE		$initial_enable

EOF_BULLET4
;

    push @main::c_game_data_lines, <<EOF_BULLET5

//////////////////////////////
// Bullets definition
//////////////////////////////

struct bullet_state_data_s bullet_state_data[ BULLET_MAX_BULLETS ] = {
EOF_BULLET5
;
    foreach ( 1 .. $max_bullets ) {
        push @main::c_game_data_lines, "\t{ NULL, { .x.value = 0, .y.value = 0, .xmax = 0, .ymax = 0 }, 0, 0, 0, NULL, 0 },\n";
    }
    push @main::c_game_data_lines, "};\n\n";

    # bullet sprite must be always available - output sprite into home bank
}

sub generate_items {

    # do not generate anything related to inventory if no items defined
    return if ( not scalar( @main::all_items ) );

    my $max_items = scalar( @main::all_items );
    my $all_items_mask = 0;
    my $mask = 1;
    foreach my $i ( 1 .. $max_items ) {
        $all_items_mask += $mask;
        $mask <<= 1;
    }

    push @main::h_game_data_lines, <<GAME_DATA_H_3

// Global Items table
#define INVENTORY_MAX_ITEMS $max_items
#define INVENTORY_ALL_ITEMS_MASK $all_items_mask
extern struct item_info_s all_items[];

// Item constants
GAME_DATA_H_3
;

    # output constants for inventory items
    foreach my $i ( 0 .. ($max_items - 1) ) {
        my $item = $main::all_items[ $i ];
        my $item_mask = 1 << $i;
        push @main::h_game_data_lines, sprintf( "#define\tINVENTORY_ITEM_%s\t%d\n",
            uc( $item->{'name'} ), $item_mask
        );
        push @main::h_game_data_lines, sprintf( "#define\tINVENTORY_ITEM_%s_NUM\t%d\n",
            uc( $item->{'name'} ), $i
        );
    }
    push @main::h_game_data_lines, "\n";

    # output Inventory item for weapon if selected
    if ( defined( $main::hero->{'bullet'} ) ) {
        if ( defined( $main::hero->{'bullet'}{'weapon_item'} ) ) {
            push @main::h_game_data_lines, sprintf( "#define WEAPON_ITEM INVENTORY_ITEM_%s\n", uc( $main::hero->{'bullet'}{'weapon_item'} ) );
            push @main::h_game_data_lines, sprintf( "#define WEAPON_ITEM_NUM INVENTORY_ITEM_%s_NUM\n", uc( $main::hero->{'bullet'}{'weapon_item'} ) );
        }
    }

    push @main::c_game_data_lines, <<EOF_ITEMS1

///////////////////////
// Global items table
///////////////////////

struct item_info_s all_items[ INVENTORY_MAX_ITEMS ] = {
EOF_ITEMS1
;
    push @main::c_game_data_lines, join( ",\n",
        map {
            sprintf( "\t{ BTILE_ID_%s, 0x%04x, F_ITEM_ACTIVE }",
                uc( $main::all_items[ $_ ]{'btile'} ),
                ( 0x1 << $_ ),
            )
        } ( 0 .. ( $max_items - 1 ) )
    );

    push @main::c_game_data_lines, <<EOF_ITEMS2

};

EOF_ITEMS2
;

}

sub generate_crumb_types {

    # do not generate anything related to inventory if no items defined
    return if ( not scalar( @main::all_crumb_types ) );

    my $crumb_num_types = scalar( @main::all_crumb_types );

    push @main::h_game_data_lines, <<GAME_DATA_H_2

// Global Crumb Types table
#define CRUMB_NUM_TYPES $crumb_num_types

// Crumb constants
GAME_DATA_H_2
;

    # output constants for crumb types
    foreach my $i ( 0 .. ( $crumb_num_types - 1 ) ) {
        push @main::h_game_data_lines, sprintf( "#define\tCRUMB_TYPE_%s\t%d\n",
            uc( $main::all_crumb_types[ $i ]{'name'} ), $i
        );
    }
    push @main::h_game_data_lines, "\n";

    push @main::c_game_data_lines, <<EOF_CRUMBS1

/////////////////////////////////
// Global Crumb Types table
/////////////////////////////////

struct crumb_info_s all_crumb_types[ CRUMB_NUM_TYPES ] = {
EOF_CRUMBS1
;
    push @main::c_game_data_lines, join( ",\n",
        map {
            sprintf( "\t{ .btile_num = BTILE_ID_%s, .counter = 0, .do_action = %s, .required_items = %s }",
                uc( $main::all_crumb_types[ $_ ]{'btile'} ),
                $main::all_crumb_types[ $_ ]{'action_function'} || 'NULL',
                $main::all_crumb_types[ $_ ]{'required_items'} || 0,
            )
        } ( 0 .. ( $crumb_num_types - 1 ) )
    );

    push @main::c_game_data_lines, <<EOF_CRUMBS2

};

EOF_CRUMBS2
;

}

1;

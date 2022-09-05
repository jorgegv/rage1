////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

// hero.c

#include <games/sp1.h>
#include <input.h>
#include <arch/spectrum.h>

#include "features.h"

#include "rage1/hero.h"
#include "rage1/game_state.h"
#include "rage1/btile.h"
#include "rage1/screen.h"
#include "rage1/sprite.h"
#include "rage1/debug.h"
#include "rage1/interrupts.h"
#include "rage1/bullet.h"
#include "rage1/sound.h"
#include "rage1/hotzone.h"
#include "rage1/util.h"
#include "rage1/dataset.h"
#include "rage1/memory.h"
#include "rage1/crumb.h"

#include "game_data.h"

/////////////////////////////
// Hero definition
/////////////////////////////

struct hero_info_s hero_startup_data = {
    NULL,		// sprite ptr - will be initialized at program startup
    HERO_SPRITE_ID,
    {
        HERO_SPRITE_SEQUENCE_UP,
        HERO_SPRITE_SEQUENCE_DOWN,
        HERO_SPRITE_SEQUENCE_LEFT,
        HERO_SPRITE_SEQUENCE_RIGHT,
        HERO_SPRITE_ANIMATION_DELAY,
        HERO_SPRITE_SEQUENCE_DOWN, 0, 0, NULL,
        HERO_SPRITE_STEADY_FRAME_UP,
        HERO_SPRITE_STEADY_FRAME_DOWN,
        HERO_SPRITE_STEADY_FRAME_LEFT,
        HERO_SPRITE_STEADY_FRAME_RIGHT,
    },	// animation
    { 0,0,0,0 },	// position - will be reset when entering a screen, including the first one
    { MOVE_NONE, HERO_MOVE_HSTEP, HERO_MOVE_VSTEP },	// movement
    0,				// flags
    HERO_NUM_LIVES,		// lives
    HERO_LIVES_BTILE_NUM	// btile
};

void init_hero(void) {
    // we need to prepopulate this
    memcpy( &game_state.hero, &hero_startup_data, sizeof( hero_startup_data ) );
    hero_init_sprites();
}

// resets hero position after being killed
void hero_reset_position(void) {
    struct hero_info_s *h;
    struct hero_animation_data_s *anim;
    uint8_t *animation_frame;

    h = &game_state.hero;

    // reset animation sequence
    anim = &h->animation;
    h->animation.current_sequence = h->animation.sequence_down;
    h->animation.current_frame = 0;

    // set pointer to steady frame down
    SET_HERO_FLAG( *h, F_HERO_STEADY );
    animation_frame = home_assets->all_sprite_graphics[ HERO_SPRITE_ID ].frame_data.frames[ HERO_SPRITE_STEADY_FRAME_DOWN ];
    h->movement.last_direction = MOVE_DOWN;

    // set initial position and move it there
    hero_set_position_x( h, game_state.current_screen_ptr->hero_data.startup_x );
    hero_set_position_y( h, game_state.current_screen_ptr->hero_data.startup_y );
    sp1_MoveSprPix( h->sprite, &game_area, animation_frame, h->position.x, h->position.y );
}

// X and Y setting functions - take care of setting XMAX and YMAX also
void hero_set_position_x( struct hero_info_s *h, uint8_t x ) {
    h->position.x = x;
    h->position.xmax = h->position.x + HERO_SPRITE_WIDTH - 1;
}

void hero_set_position_y( struct hero_info_s *h, uint8_t y ) {
    h->position.y = y;
    h->position.ymax = h->position.y + HERO_SPRITE_HEIGHT - 1;
}

// this is initialized on startup, it is used when resetting the hero state
struct sp1_ss *hero_sprite;

// resets hero state at game startup
void hero_reset_all(void) {
    struct hero_info_s *h;

    h = &game_state.hero;

    // bulk copy from data. Sprite ptr gets trashed
    memcpy( h, &hero_startup_data, sizeof( hero_startup_data ) );
    // ...but we saved it in initialization, so restore it
    h->sprite = hero_sprite;

    // set flags
    SET_HERO_FLAG( *h, F_HERO_ALIVE );

    // set default animation sequence and reset position
    hero_reset_position();
}

void hero_draw( void ) {
    sp1_MoveSprPix(
        game_state.hero.sprite,
        &game_area,
        game_state.hero.animation.last_frame_ptr,
        game_state.hero.position.x,
        game_state.hero.position.y
    );
}

//
// void hero_animate_and_move( void )
// moved to banked_code
//

void hero_shoot_bullet( void ) {

    // ignore the shot if we are in the "reloading" phase
    if ( game_state.bullet.reloading-- )
        return;

    // add a new bullet and load the "reload" counter
    bullet_add();
    game_state.bullet.reloading = game_state.bullet.reload_delay;
}

#ifdef BUILD_FEATURE_HERO_CHECK_TILES_BELOW
void hero_check_tiles_below(void) {
    struct sp1_ss *s;
    uint8_t i,j,cols,r,c,tile_type;

#ifdef BUILD_FEATURE_INVENTORY
    uint8_t item;
    struct item_location_s *item_loc;
#endif

#ifdef BUILD_FEATURE_CRUMBS
    uint8_t crumb_type;
    struct crumb_location_s *crumb_loc;
#endif

    s = game_state.hero.sprite;

    // run all chars and search for items
    cols = s->width;	// SP1 units: chars (_not_ pixels!)

    i = s->height;		// same comment as above!
    while ( i-- ) {
        r = s->row + i;
        j = cols;
        while ( j-- ) {
            c = s->col + j;
            tile_type = GET_TILE_TYPE_AT( r, c );

#ifdef BUILD_FEATURE_INVENTORY
            if ( tile_type == TT_ITEM ) {

                // get item location and number
                item_loc = map_get_item_location_at_position( game_state.current_screen_ptr, r, c );
                item = item_loc->item_num;

                // add item to inventory
                inventory_add_item( &game_state.inventory, item );

                // mark the item as inactive
                RESET_ITEM_FLAG( all_items[ item ], F_ITEM_ACTIVE );

                // remove item from screen - items always have their btiles in home dataset
                btile_remove( item_loc->row, item_loc->col, &home_assets->all_btiles[ all_items[ item ].btile_num ] );

                // update inventory on screen (show)
                inventory_show();

                // play pickup sound
                sound_request_fx( SOUND_ITEM_GRABBED );
            }
#endif // BUILD_FEATURE_INVENTORY

#ifdef BUILD_FEATURE_CRUMBS
            if ( ( tile_type & TT_CRUMB ) == TT_CRUMB ) {

                // get crumb location and type (low nibble)
                crumb_loc = map_get_crumb_location_at_position( game_state.current_screen_ptr, r, c );
                crumb_type = tile_type & 0x0F;

                // do action for the grabbed crumb
                crumb_was_grabbed( crumb_type );

                // mark the crumb as inactive
                RESET_CRUMB_FLAG( game_state.current_screen_asset_state_table_ptr[ crumb_loc->state_index ].asset_state, F_CRUMB_ACTIVE );

                // remove crumb from screen - crumb types always have their btiles in home dataset
                btile_remove( crumb_loc->row, crumb_loc->col, &home_assets->all_btiles[ all_crumb_types[ crumb_type ].btile_num ] );

                // play pickup sound
                sound_request_fx( SOUND_ITEM_GRABBED );
            }
#endif // BUILD_FEATURE_CRUMBS
        }
    }
}
#endif // BUILD_FEATURE_HERO_CHECK_TILES_BELOW

// printing context
struct sp1_pss lives_display_ctx = {
   &lives_area,				// bounds
   SP1_PSSFLAG_INVALIDATE,		// flags
   0,0,					// initial position x,y
   0, DEFAULT_BG_ATTR,			// attr mask and attribute
   0,0					// RESERVED
};

void hero_update_lives_display(void) {
    uint8_t col;
    uint8_t n;

    // clear the area
    sp1_ClearRectInv( &lives_area, DEFAULT_BG_ATTR, ' ', SP1_RFLAG_TILE | SP1_RFLAG_COLOUR );

    // draw one tile per live
    col = LIVES_AREA_LEFT;
    n = game_state.hero.num_lives;
    while ( n-- ) {
        btile_draw( LIVES_AREA_TOP, col, &home_assets->all_btiles[ HERO_LIVES_BTILE_NUM ], TT_DECORATION, &lives_area );
        col += home_assets->all_btiles[ HERO_LIVES_BTILE_NUM ].num_cols;
    }
}

void hero_move_offscreen(void) {
    sprite_move_offscreen( game_state.hero.sprite );
}

// Hero Sprites initialization function
void hero_init_sprites(void) {
    game_state.hero.sprite = hero_sprite = sprite_allocate(
        HERO_SPRITE_HEIGHT >> 3,
        HERO_SPRITE_WIDTH >> 3
    );
}

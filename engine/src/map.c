////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <arch/spectrum.h>
#include <games/sp1.h>
#include <stdlib.h>

#include "rage1/map.h"
#include "rage1/game_state.h"
#include "rage1/inventory.h"
#include "rage1/screen.h"

#include "game_data.h"

#ifdef BUILD_FEATURE_SCREEN_TITLES
struct sp1_pss title_ctx = {
   &title_area,				// bounds
   SP1_PSSFLAG_INVALIDATE,		// flags
   0,0,					// initial position x,y
   0, DEFAULT_BG_ATTR,			// attr mask and attribute
   0,0					// RESERVED
};
#endif // BUILD_FEATURE_SCREEN_TITLES

// draw a given screen
void map_draw_screen(struct map_screen_s *s) {
    uint8_t i,r,c, maxr, maxc, btwidth, btheight;
    struct btile_pos_s *t;
    struct btile_s *bt;

    // clear screen
    sp1_ClearRectInv( &game_area, DEFAULT_BG_ATTR, ' ', SP1_RFLAG_TILE | SP1_RFLAG_COLOUR );

    // clear btile types
    btile_clear_type_all_screen();

    // draw background if present
    if ( s->background_data.probability ) {
        maxr = s->background_data.box.row + s->background_data.box.height - 1;
        maxc = s->background_data.box.col + s->background_data.box.width - 1;

        bt = dataset_get_banked_btile_ptr( s->background_data.btile_num );
        btwidth = bt->num_cols;
        btheight = bt->num_rows;

        r = s->background_data.box.row;
        while ( r <= maxr ) {
            c = s->background_data.box.col;
            while ( c <= maxc ) {
                // draw the btile with probability (s->background_data.probability / 255)
                if ( (uint8_t) rand() <= s->background_data.probability )
                    btile_draw( r, c, bt, TT_DECORATION, &s->background_data.box );
                c += btwidth;
            }
            r += btheight;
        }
    }

    // draw tiles
    i = s->btile_data.num_btiles;
    while ( i-- ) {
        t = &s->btile_data.btiles_pos[i];
        // we draw if there is no state ( no state = always active ), or if the btile is active
        if ( ( t->state_index == ASSET_NO_STATE ) ||
            IS_BTILE_ACTIVE( all_screen_asset_state_tables[ s->global_screen_num ].states[ t->state_index ].asset_state ) )
            btile_draw( t->row, t->col, dataset_get_banked_btile_ptr( t->btile_id ), t->type, &game_area );
    }

#ifdef BUILD_FEATURE_HERO_CHECK_TILES_BELOW
    // draw items
    i = s->item_data.num_items;
    while ( i-- ) {
        struct item_location_s *it;
        it = &s->item_data.items[i];
        if ( ! IS_ITEM_ACTIVE( all_items[ it->item_num ] ) )
            continue;
        btile_draw( it->row, it->col, &home_assets->all_btiles[ all_items[ it->item_num ].btile_num ], TT_ITEM, &game_area );
    }
#endif // BUILD_FEATURE_HERO_CHECK_TILES_BELOW

#ifdef BUILD_FEATURE_SCREEN_TITLES
    sp1_ClearRectInv( &title_area, DEFAULT_BG_ATTR, ' ', SP1_RFLAG_TILE | SP1_RFLAG_COLOUR );
    if ( game_state.current_screen_ptr->title ) {
        sp1_SetPrintPos( &title_ctx, 0, 0 );
        sp1_PrintString( &title_ctx, game_state.current_screen_ptr->title );
    }
#endif // BUILD_FEATURE_SCREEN_TITLES

}

#ifdef BUILD_FEATURE_HERO_CHECK_TILES_BELOW
struct item_location_s *map_get_item_location_at_position( struct map_screen_s *s, uint8_t row, uint8_t col ) {
    uint8_t i, rmax, cmax;
    struct item_location_s *it;

    i = s->item_data.num_items;
    while ( i-- ) {
        it = &s->item_data.items[i];
        rmax = it->row + home_assets->all_btiles[ all_items[ it->item_num ].btile_num ].num_rows - 1;
        cmax = it->col + home_assets->all_btiles[ all_items[ it->item_num ].btile_num ].num_cols - 1;
        if ( ( row >= it->row ) && ( row <= rmax ) &&
             ( col >= it->col ) && ( col <= cmax ) )
            return it;
    }
    return NULL;	// no object
}
#endif // BUILD_FEATURE_HERO_CHECK_TILES_BELOW

void map_enter_screen( uint8_t screen_num ) {
    // If we are in 128 mode, we need to switch to the dataset where the
    // screen resides.  If in 48 mode, this is not needed since everything
    // is in home dataset

#ifdef BUILD_FEATURE_ZX_TARGET_128
    // We can just call dataset_activate with the screen dataset number.
    // The function returns immediately if the current dataset is already
    // loaded and does not need to be changed
    dataset_activate( screen_dataset_map[ screen_num ].dataset_num );
#endif

    // we must use the local screen number when indexing on banked_assets->all_screens!
    map_allocate_sprites( &banked_assets->all_screens[ screen_dataset_map[ screen_num ].dataset_local_screen_num ] );
}

void map_exit_screen( struct map_screen_s *s ) {
    map_free_sprites( s );
}

void map_allocate_sprites( struct map_screen_s *m ) {
    uint8_t i;
    struct sp1_ss *s;
    struct sprite_graphic_data_s *g;

    i = m->enemy_data.num_enemies;
    while ( i-- ) {
        g = dataset_get_banked_sprite_ptr( m->enemy_data.enemies[ i ].num_graphic );
        s = sprite_allocate(
            g->height >> 3,
            g->width >> 3
        );
        sprite_set_color( s, m->enemy_data.enemies[ i ].color );
        m->enemy_data.enemies[ i ].sprite = s;
    }
}

// this function can be used generically, since the only data needed for
// free is the pointer itself, and we know the number of sprites from
// map_screen_s struct
void map_free_sprites( struct map_screen_s *s ) {
    uint8_t i;
    i = s->enemy_data.num_enemies;
    while ( i-- )
        sp1_DeleteSpr( s->enemy_data.enemies[ i ].sprite );
}

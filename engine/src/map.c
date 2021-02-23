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

#include "map.h"
#include "game_state.h"
#include "inventory.h"
#include "game_data.h"
#include "screen.h"

// draw a given screen
void map_draw_screen(struct map_screen_s *s) {
    static uint8_t i;
    static struct btile_pos_s *t;
    static struct item_location_s *it;

    // clear screen
    sp1_ClearRectInv( &game_area, DEFAULT_BG_ATTR, ' ', SP1_RFLAG_TILE | SP1_RFLAG_COLOUR );

    // clear btile types
    btile_clear_type_all_screen();

    // draw tiles
    i = s->btile_data.num_btiles;
    while ( i-- ) {
        t = &s->btile_data.btiles_pos[i];
        if ( ! IS_BTILE_ACTIVE( *t ) )
            continue;
        btile_draw( t->row, t->col, t->btile, t->type );
    }

    // draw items
    i = s->item_data.num_items;
    while ( i-- ) {
        it = &s->item_data.items[i];
        if ( ! IS_ITEM_ACTIVE( all_items[ it->item_num ] ) )
            continue;
        btile_draw( it->row, it->col, all_items[ it->item_num ].btile, TT_ITEM );
    }
}

uint8_t map_get_item_at_position( struct map_screen_s *s, uint8_t row, uint8_t col ) {
    static uint8_t i;
    static struct item_location_s *it;

    i = s->item_data.num_items;
    while ( i-- ) {
        it = &s->item_data.items[i];
        if ( ( it->row == row ) && ( it->col == col) )
            return it->item_num;
    }
    return 255;	// no object
}

void map_screen_reset_all_sprites( struct map_screen_s *s ) {
    static uint8_t i;
    i = s->sprite_data.num_sprites;
    while ( i-- )
        SET_SPRITE_FLAG( s->sprite_data.sprites[ i ], F_SPRITE_ACTIVE );
}

void map_sprites_reset_all(void) {
    static uint8_t i;
    i = MAP_NUM_SCREENS;
    while ( i-- )
        map_screen_reset_all_sprites ( &map[ i ] );
}

uint16_t map_count_enemies_all(void) {
    static uint16_t count;
    static uint8_t i;

    count = 0;
    i = MAP_NUM_SCREENS;
    while ( i-- )
        count += map[ i ].sprite_data.num_sprites;

    return count;
}

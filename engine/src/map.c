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

// draw a given screen
void map_draw_screen(struct map_screen_s *s) {
    static uint8_t i,r,c, maxr, maxc, btwidth, btheight;
    static struct btile_pos_s *t;
    static struct item_location_s *it;

    // clear screen
    sp1_ClearRectInv( &game_area, DEFAULT_BG_ATTR, ' ', SP1_RFLAG_TILE | SP1_RFLAG_COLOUR );

    // clear btile types
    btile_clear_type_all_screen();

    // draw background if present
    if ( s->background_data.btile ) {
        maxr = s->background_data.box.row + s->background_data.box.height - 1;
        maxc = s->background_data.box.col + s->background_data.box.width - 1;
        btwidth = s->background_data.btile->num_cols;
        btheight = s->background_data.btile->num_rows;

        r = s->background_data.box.row;
        while ( r <= maxr ) {
            c = s->background_data.box.col;
            while ( c <= maxc ) {
                // draw the btile with probability (s->background_data.probability / 255)
                if ( (uint8_t) rand() <= s->background_data.probability )
                    btile_draw( r, c, s->background_data.btile, TT_DECORATION, &s->background_data.box );
                c += btwidth;
            }
            r += btheight;
        }
    }

    // draw tiles
    i = s->btile_data.num_btiles;
    while ( i-- ) {
        t = &s->btile_data.btiles_pos[i];
        if ( ! IS_BTILE_ACTIVE( *t ) )
            continue;
        btile_draw( t->row, t->col, t->btile, t->type, &game_area );
    }

    // draw items
    i = s->item_data.num_items;
    while ( i-- ) {
        it = &s->item_data.items[i];
        if ( ! IS_ITEM_ACTIVE( all_items[ it->item_num ] ) )
            continue;
        btile_draw( it->row, it->col, all_items[ it->item_num ].btile, TT_ITEM, &game_area );
    }
}

struct item_location_s *map_get_item_location_at_position( struct map_screen_s *s, uint8_t row, uint8_t col ) {
    static uint8_t i, rmax, cmax;
    static struct item_location_s *it;

    i = s->item_data.num_items;
    while ( i-- ) {
        it = &s->item_data.items[i];
        rmax = it->row + all_items[ it->item_num ].btile->num_rows - 1;
        cmax = it->col + all_items[ it->item_num ].btile->num_cols - 1;
        if ( ( row >= it->row ) && ( row <= rmax ) &&
             ( col >= it->col ) && ( col <= cmax ) )
            return it;
    }
    return NULL;	// no object
}

void map_screen_reset_all_sprites( struct map_screen_s *s ) {
    static uint8_t i;
    i = s->enemy_data.num_enemies;
    while ( i-- )
        SET_SPRITE_FLAG( s->enemy_data.enemies[ i ], F_SPRITE_ACTIVE );
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
        count += map[ i ].enemy_data.num_enemies;

    return count;
}

void map_enter_screen( struct map_screen_s *s ) {
    if ( s->allocate_sprites ) s->allocate_sprites( s );
}

void map_exit_screen( struct map_screen_s *s ) {
    if ( s->free_sprites ) s->free_sprites( s );
}

// this function can be used generically, since the only data needed for
// free is the pointer itself, and we know the number of sprites from
// map_screen_s struct
void map_generic_free_sprites_function( struct map_screen_s *s ) {
    static uint8_t i;
    i = s->enemy_data.num_enemies;
    while ( i-- )
        sp1_DeleteSpr( s->enemy_data.enemies[ i ].sprite );
}

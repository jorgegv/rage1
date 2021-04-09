////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

//
// implementation of inventory and item grabbing
//

#include <arch/spectrum.h>
#include <games/sp1.h>

#include "inventory.h"
#include "game_state.h"
#include "map.h"
#include "debug.h"
#include "screen.h"
#include "game_data.h"

void inventory_reset_all(void) {
    static uint8_t i;

    // reset item state in all screens
    i = 16;
    while ( i-- )
        SET_ITEM_FLAG( all_items[i], F_ITEM_ACTIVE );

    // reset inventory for game
    game_state.inventory.owned_items = 0;
}

void inventory_show(void) {
    static uint8_t col, item_index;
    struct inventory_info_s *inv;
    struct btile_s *tile;

    // clear the area
    sp1_ClearRectInv( &inventory_area, DEFAULT_BG_ATTR, ' ', SP1_RFLAG_TILE | SP1_RFLAG_COLOUR );

    // draw owned items, right to left
    col = INVENTORY_AREA_RIGHT;
    inv = &game_state.inventory;
    item_index = 16;
    while ( item_index-- ) {
        tile = all_items[ item_index ].btile;
        if ( ( tile != NULL ) && ( INVENTORY_HAS_ITEM( inv, all_items[ item_index].item_id ) ) )
            btile_draw( INVENTORY_AREA_TOP, col--, tile, TT_DECORATION, &inventory_area );
    }
}

void inventory_add_item( struct inventory_info_s *inv, uint8_t item ) {
    static uint8_t num_items, c;
    static uint16_t id;

    // add item to inventory
    ADD_TO_INVENTORY( inv, all_items[ item ].item_id );

    // check if we have all items and set flag if so
    if ( game_state.inventory.owned_items == INVENTORY_ALL_ITEMS_MASK )
        SET_GAME_FLAG( F_GAME_GOT_ALL_ITEMS );
}

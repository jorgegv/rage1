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

#include "features.h"

#include "rage1/inventory.h"
#include "rage1/game_state.h"
#include "rage1/map.h"
#include "rage1/debug.h"
#include "rage1/screen.h"

#include "game_data.h"

#ifdef BUILD_FEATURE_INVENTORY

// a guard, just in case...
#ifndef BUILD_FEATURE_HERO_CHECK_TILES_BELOW
  #error BUILD_FEATURE_HERO_CHECK_TILES_BELOW must be defined!
#endif

void inventory_reset_all(void) {
    uint8_t i;

    // reset item state in all screens
    i = INVENTORY_MAX_ITEMS;
    while ( i-- )
        SET_ITEM_FLAG( all_items[i], F_ITEM_ACTIVE );

    // reset inventory for game
    game_state.inventory.owned_items = 0;
}

void inventory_show(void) {
    uint8_t col, item_index;

    // clear the area
    sp1_ClearRectInv( &inventory_area, DEFAULT_BG_ATTR, ' ', SP1_RFLAG_TILE | SP1_RFLAG_COLOUR );

    // draw owned items, left to right
    col = INVENTORY_AREA_LEFT;
    item_index = INVENTORY_MAX_ITEMS;
    while ( item_index-- ) {
        if ( INVENTORY_HAS_ITEM( &game_state.inventory, all_items[ item_index].item_id ) ) {
            btile_draw( INVENTORY_AREA_TOP, col, &home_assets->all_btiles[ all_items[ item_index ].btile_num ], TT_DECORATION, &inventory_area );
            col += home_assets->all_btiles[ all_items[ item_index ].btile_num ].num_cols;
        }
    }

#ifndef BUILD_FEATURE_GAMEAREA_COLOR_FULL
    // If the game is monochrome, the default color can be changed while
    // during the game, and the btile draw routine uses its value to draw
    // all btiles, including inventory ones.  This would end with some items
    // drawn with different colors depending on the mono attr value when
    // they were grabbed.  To avoid this, we must reset the colors of the
    // inventory area to the original game default mono attr
    sp1_ClearRectInv( &inventory_area, GAMEAREA_COLOR_MONO_ATTR, 0, SP1_RFLAG_COLOUR );
#endif
}

void inventory_add_item( struct inventory_info_s *inv, uint8_t item ) {
    // add item to inventory
    ADD_TO_INVENTORY( inv, all_items[ item ].item_id );

    // check if we have all items and set flag if so
    if ( game_state.inventory.owned_items == INVENTORY_ALL_ITEMS_MASK )
        SET_GAME_FLAG( F_GAME_GOT_ALL_ITEMS );
}

#endif // BUILD_FEATURE_INVENTORY

////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _INVENTORY_H
#define _INVENTORY_H

#include <stdint.h>

#include "features.h"

#include "rage1/btile.h"

//
// Item definitions and management
//

// struct for an item in the global item table
struct item_info_s {
    uint8_t btile_num;	// btile used for this item
    uint16_t item_id;		// inventory mask for this item: only 1 bit set
    uint8_t flags;
};

// struct for location of an item on a given screen
struct item_location_s {
    uint8_t item_num;
    uint8_t row,col;
};

// item flags macros and definitions
#define GET_ITEM_FLAG(i,f)	( (i).flags & (f) )
#define SET_ITEM_FLAG(i,f)	( (i).flags |= (f) )
#define RESET_ITEM_FLAG(i,f)	( (i).flags &= ~(f) )

#define F_ITEM_ACTIVE	0x0001

#define IS_ITEM_ACTIVE(i)	( GET_ITEM_FLAG( ( i ), F_ITEM_ACTIVE ) )

//
// Inventory definitions and management
//
struct inventory_info_s {
    // inventory data - maximum 16 items allowed
    // 1 bit per item (0-15) - 0: not owned, 1: owned
    uint16_t owned_items;
};

void inventory_reset_all(void);
void inventory_show(void);
void inventory_add_item( struct inventory_info_s *inv, uint8_t item );

// inventory management macros
#define INVENTORY_HAS_ITEM(inv,item)		( (inv)->owned_items & (item) )
#define ADD_TO_INVENTORY(inv,item)		( (inv)->owned_items |= (item) )
#define REMOVE_FROM_INVENTORY(inv,item)		( (inv)->owned_items &= (~(item) ) )

// flags

#endif //_INVENTORY_H

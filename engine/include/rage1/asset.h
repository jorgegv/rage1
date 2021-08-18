////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _ASSET_H
#define _ASSET_H

#include <stdint.h>

#include "rage1/btile.h"
#include "rage1/sprite.h"
#include "rage1/flow.h"
#include "rage1/map.h"

#include "game_data.h"

// The following structure contains pointers to asset tables.  It is
// intended to be generated as the first element in a banked game_data.c
// file, so that it is the first structure in the generated binary.

// If done this way, the structure is located at a predefined known address
// and can be used as the only entry point to access all the assets on the
// same bank (which is what we want)

struct asset_data_s {
    // BTiles
    uint8_t				num_btiles;
    struct btile_s			*all_btiles;
    // Sprites
    uint8_t				num_sprite_graphics;
    struct sprite_graphic_data_s	*all_sprite_graphics;
    // Flow rules
    // FIXME: this needs to be upgraded to a 16 bit number - we can easily have more than 255 rules in a game
    uint8_t				num_flow_rules;
    struct flow_rule_s			*all_flow_rules;
    // Map
    uint8_t				num_screens;
    struct map_screen_s			*all_screens;
};

#endif // _ASSET_H

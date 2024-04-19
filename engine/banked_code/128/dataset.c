////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <stdint.h>
#include <intrinsic.h>
#include <string.h>
#include <compress/zx0.h>

#include "features.h"

#include "rage1/dataset.h"
#include "rage1/memory.h"
#include "rage1/game_state.h"

#include "game_data.h"

#include "rage1/banked.h"

// acceleration functions
struct btile_s *dataset_get_banked_btile_ptr( uint16_t btile_id ) __z88dk_fastcall {
    return &banked_assets->all_btiles[ btile_id ];
}

struct sprite_graphic_data_s *dataset_get_banked_sprite_ptr( uint8_t sprite_id ) __z88dk_fastcall {
    return &banked_assets->all_sprite_graphics[ sprite_id ];
}

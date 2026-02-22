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

#include "rage1/gfx.h"
#include "rage1/sp1engine.h"
#include "rage1/screen.h"
#include "rage1/debug.h"

#include "game_data.h"

/////////////////////////////////////
//
// GFX library initialization
//
/////////////////////////////////////

#ifdef BUILD_FEATURE_SPRITE_ENGINE_SP1

void gfx_init( uint8_t bg_attr, uint8_t bg_char ) {
   zx_border(INK_BLACK);
   sp1_Initialize(SP1_IFLAG_MAKE_ROTTBL | SP1_IFLAG_OVERWRITE_TILES | SP1_IFLAG_OVERWRITE_DFILE,
      bg_attr, bg_char);
   gfx_invalidate(&full_screen);
   gfx_update();
}

#endif // BUILD_FEATURE_SPRITE_ENGINE_SP1

void init_sp1(void) {
   gfx_init( DEFAULT_BG_ATTR, ' ' );
}

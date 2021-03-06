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

#include "rage1/sp1engine.h"
#include "rage1/screen.h"
#include "rage1/debug.h"

#include "game_data.h"

/////////////////////////////////////
//
// SP1 library initialization
//
/////////////////////////////////////

void init_sp1(void) {
   // Initialize SP1.LIB
   zx_border(INK_BLACK);
   sp1_Initialize(SP1_IFLAG_MAKE_ROTTBL | SP1_IFLAG_OVERWRITE_TILES | SP1_IFLAG_OVERWRITE_DFILE,
      DEFAULT_BG_ATTR, ' ');
   sp1_Invalidate(&full_screen);
   sp1_UpdateNow();
}

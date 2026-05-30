///////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

// G7: ZX arch include routed through the platform shim (byte-identical on ZX,
// compiles under +cpc — see rage1/platform.h).
#include "rage1/platform.h"

#include "rage1/gfx.h"

#include "game_data.h"

void init_gfx(void) {
   gfx_init( GFX_DEFAULT_BG_ATTR, ' ' );
}

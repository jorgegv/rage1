////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _SCREEN_H
#define _SCREEN_H

#include <stdint.h>

#include "rage1/gfx.h"

// off-screen cell coords used for "parking" sprites are now backend-internal
// (Phase G5 — gfx.md §G5-4): see GFX_PARK_ROW / GFX_PARK_COL and the
// gfx_sprite_park() entrypoint in the backend gfx_*.h headers.

// rectangle covering the full screen
extern gfx_rect_t full_screen;

#endif // _SCREEN_H

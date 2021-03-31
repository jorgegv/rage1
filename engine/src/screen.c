////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <games/sp1.h>

#include "rage1.h"

// rectangles covering the full screen and other screen areas
struct sp1_Rect full_screen	= { 0, 0, 32, 24 };
struct sp1_Rect border_area	= { BORDER_TOP, BORDER_LEFT, BORDER_WIDTH, BORDER_HEIGHT };
struct sp1_Rect game_area	= { GAME_AREA_TOP, GAME_AREA_LEFT, GAME_AREA_WIDTH, GAME_AREA_HEIGHT };
struct sp1_Rect inventory_area	= { INVENTORY_TOP, INVENTORY_LEFT, INVENTORY_WIDTH, INVENTORY_HEIGHT };
struct sp1_Rect lives_area	= { LIVES_AREA_TOP, LIVES_AREA_LEFT, LIVES_AREA_WIDTH, LIVES_AREA_HEIGHT };

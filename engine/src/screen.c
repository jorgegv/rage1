////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <arch/zx/sprites/sp1.h>

#include "rage1/screen.h"

// rectangles covering the full screen and other screen areas
struct sp1_Rect full_screen	= { 0, 0, 32, 24 };

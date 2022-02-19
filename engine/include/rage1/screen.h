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

#include <arch/zx/sprites/sp1.h>
#include <stdint.h>

#include "features.h"

// off-screen cell coords (used for "parking" sprites)
#define OFF_SCREEN_ROW		24
#define OFF_SCREEN_COLUMN	0

// rectangle covering the full screen
extern struct sp1_Rect full_screen;

#endif // _SCREEN_H

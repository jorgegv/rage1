////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _BEEPER_H
#define _BEEPER_H

#include <sound.h>

#include "features.h"

// this is a private copy of bit_beepfx function
// effect definitions are the same and compatible, so we can use them

extern void bit_beepfx(void *bfx) __z88dk_fastcall;
//#define bit_beepfx(a) bit_beepfx_fastcall(a)

#endif // _BEEPER_H

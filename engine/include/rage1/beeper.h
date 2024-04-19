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

// for the beepfx FX constants
#include <sound/bit.h>

#include "features.h"

void init_beeper( void );

// requests that a special FX be played at the end of the game loop
void beeper_request_fx( void *sfx );

// play the pending FX requests
void beeper_play_pending_fx( void );

// plays a beeper fx
void beeper_play_fx( void *sfx );

#endif //_BEEPER_H

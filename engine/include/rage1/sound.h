////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _SOUND_H
#define _SOUND_H

#include <sound.h>

#include "features.h"

// requests that a special FX be played at the end of the game loop
void sound_request_fx( void *sfx );

// play the pending FX request
void sound_play_pending_fx( void );

#endif //_SOUND_H

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

// On 128K builds these symbols are provided as banked-call macros from
// banked_function_defs.h (included via memory.h). When that header is
// pulled in *before* this one, the macros are already defined and the
// real prototypes must be suppressed to avoid "too many arguments to
// macro" errors. The #ifndef guards make this header order-independent
// while keeping the prototypes visible on builds where the function is
// a real linkable symbol (48K, or the banked-code build itself).

#ifndef init_beeper
void init_beeper( void );
#endif

// requests that a special FX be played at the end of the game loop
#ifndef beeper_request_fx
void beeper_request_fx( void *sfx );
#endif

// play the pending FX requests
#ifndef beeper_play_pending_fx
void beeper_play_pending_fx( void );
#endif

// plays a beeper fx
#ifndef beeper_play_fx
void beeper_play_fx( void *sfx );
#endif

#endif //_BEEPER_H

////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _GAME_LOOP_H
#define _GAME_LOOP_H

#include <stdint.h>

#include "rage1/interrupts.h"

void run_main_game_loop(void);

// Use this macro to run a function only once per frame.  Invoke it just at
// the beginning of the function this way:
//
// void do_domething(void) {
//     RUN_ONLY_ONCE_PER_FRAME;
//     ...
//     (code)
//     ...
// }
//
// The global frame counter in the current_time struct is updated in the
// background via interrupts.  If the function has already been called in
// this frame, it will return immediately; otherwise, it will update the
// current frame number and continue with the rest of the function code

#define RUN_ONLY_ONCE_PER_FRAME		static uint8_t __last_frame; if ( __last_frame == current_time.frame ) return; else __last_frame = current_time.frame

#endif // _GAME_LOOP_H

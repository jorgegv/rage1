////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#include "features.h"

#include "rage1/timer.h"
#include "rage1/game_state.h"
#include "rage1/interrupts.h"

#include "game_data.h"

#ifdef BUILD_FEATURE_GAME_TIME

void init_timer( void ) {
    // for now, nothing needs to be initialized
}

void timer_reset_all_timers( void ) {
    // reset main game timer
    game_state.game_time = 0;
    // user timers will be reset here when they exist
}

uint8_t last_sec = 0;
void timer_update_all_timers( void ) {
    if ( current_time.sec != last_sec ) {
        // update last second
        last_sec = current_time.sec;
        // update main game timer
        game_state.game_time++;
        // user timers will be incremented here when they exist
    }
}

#endif // BUILD_FEATURE_GAME_TIME
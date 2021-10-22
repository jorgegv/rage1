////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _MEMORY_H
#define _MEMORY_H

#include <stdint.h>

#include "features.h"

#include "rage1/game_state.h"

#ifdef BUILD_FEATURE_ZX_TARGET_128

    extern uint8_t memory_current_memory_bank;
    void memory_switch_bank( uint8_t bank_num );

    ////////////////////////////////////////////////
    //
    // Definitions for engine banked functions
    //
    ////////////////////////////////////////////////

    // reserved memory bank for banked functions in engine code
    #define ENGINE_CODE_MEMORY_BANK		4

    // all banked functions must be declared as
    //   void function( void );
    typedef void (*banked_function_t)( void );

    // trampoline function to call banked functions
    void memory_call_banked_function( uint8_t function_id );

    // banked function IDs
    #define BANKED_FUNCTION_SOUND_PLAY_PENDING_FX_ID	0
    #define BANKED_FUNCTION_HERO_ANIMATE_AND_MOVE	1

    // maximum assigned banked function ID. Keep in sync with the previous IDs
    // 128K versions
    #define BANKED_FUNCTION_MAX_ID		1

#endif

// function call macros - 128K versions
#ifdef BUILD_FEATURE_ZX_TARGET_128
    #define CALL_SOUND_PLAY_PENDING_FX()	( memory_call_banked_function( BANKED_FUNCTION_SOUND_PLAY_PENDING_FX_ID ) )
    #define CALL_HERO_ANIMATE_AND_MOVE()	( memory_call_banked_function( BANKED_FUNCTION_HERO_ANIMATE_AND_MOVE ) )
#endif

// function call macros - 48K versions
#ifdef BUILD_FEATURE_ZX_TARGET_48
    #define CALL_SOUND_PLAY_PENDING_FX()	( sound_play_pending_fx() )
    #define CALL_HERO_ANIMATE_AND_MOVE()	( hero_animate_and_move() )
#endif


void init_memory(void);

#endif // _MEMORY_H

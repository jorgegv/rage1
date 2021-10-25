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

// memory subsystem initialization (heap, banks. etc.)
void init_memory(void);

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
    #define BANKED_FUNCTION_ENEMY_ANIMATE_AND_MOVE_ALL	2
    #define BANKED_FUNCTION_BULLET_ANIMATE_AND_MOVE_ALL	3
    #define BANKED_FUNCTION_BULLET_ADD			4

    // maximum assigned banked function ID. Keep in sync with the previous IDs
    // 128K versions
    #define BANKED_FUNCTION_MAX_ID		4

    // Banked function call macros (128K versions) - In 128K mode we
    // redefine the regular calls to banked functions as calls to
    // the trampoline memory_call_banked_function()
    #define sound_play_pending_fx()		( memory_call_banked_function( BANKED_FUNCTION_SOUND_PLAY_PENDING_FX_ID ) )
    #define hero_animate_and_move()		( memory_call_banked_function( BANKED_FUNCTION_HERO_ANIMATE_AND_MOVE ) )
    #define enemy_animate_and_move_all()	( memory_call_banked_function( BANKED_FUNCTION_ENEMY_ANIMATE_AND_MOVE_ALL ) )
    #define bullet_animate_and_move_all()	( memory_call_banked_function( BANKED_FUNCTION_BULLET_ANIMATE_AND_MOVE_ALL ) )
    #define bullet_add()			( memory_call_banked_function( BANKED_FUNCTION_BULLET_ADD ) )

#endif

#endif // _MEMORY_H

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
    typedef void (*banked_function_a16_t)( uint16_t arg );

    // trampoline functions to call banked functions
    void memory_call_banked_function( uint8_t function_id );
    void memory_call_banked_function_a16( uint8_t function_id, uint16_t arg );

    // banked function IDs
    #define BANKED_FUNCTION_BEEPER_PLAY_PENDING_FX	0
    #define BANKED_FUNCTION_HERO_ANIMATE_AND_MOVE	1
    #define BANKED_FUNCTION_ENEMY_ANIMATE_AND_MOVE_ALL	2
    #define BANKED_FUNCTION_BULLET_ANIMATE_AND_MOVE_ALL	3
    #define BANKED_FUNCTION_BULLET_ADD			4
    #define BANKED_FUNCTION_INIT_TRACKER		5
    #define BANKED_FUNCTION_TRACKER_SELECT_SONG		6
    #define BANKED_FUNCTION_TRACKER_START		7
    #define BANKED_FUNCTION_TRACKER_STOP		8
    #define BANKED_FUNCTION_TRACKER_DO_PERIODIC_TASKS	9
    #define BANKED_FUNCTION_INIT_TRACKER_SOUND_EFFECTS	10
    #define BANKED_FUNCTION_TRACKER_PLAY_FX		11
    #define BANKED_FUNCTION_TRACKER_REWIND		12
    #define BANKED_FUNCTION_TRACKER_PLAY_PENDING_FX	13
    #define BANKED_FUNCTION_TRACKER_REQUEST_FX		14
    #define BANKED_FUNCTION_BEEPER_REQUEST_FX		15
    #define BANKED_FUNCTION_INIT_BEEPER			16
    #define BANKED_FUNCTION_BEEPER_PLAY_FX		17

    // WARNING! Don't forget to update the banked function call table
    // in engine/banked_code/128/00main.asm !!!!

    // maximum assigned banked function ID. Keep in sync with the previous IDs
    // 128K versions
    #define BANKED_FUNCTION_MAX_ID			17

    // Banked function call macros (128K versions) - In 128K mode we
    // redefine the regular calls to banked functions as calls to
    // the trampoline memory_call_banked_function()
    #define beeper_play_pending_fx()		( memory_call_banked_function( BANKED_FUNCTION_BEEPER_PLAY_PENDING_FX ) )
    #define hero_animate_and_move()		( memory_call_banked_function( BANKED_FUNCTION_HERO_ANIMATE_AND_MOVE ) )
    #define enemy_animate_and_move_all()	( memory_call_banked_function( BANKED_FUNCTION_ENEMY_ANIMATE_AND_MOVE_ALL ) )
    #define bullet_animate_and_move_all()	( memory_call_banked_function( BANKED_FUNCTION_BULLET_ANIMATE_AND_MOVE_ALL ) )
    #define bullet_add()			( memory_call_banked_function( BANKED_FUNCTION_BULLET_ADD ) )
    #define init_tracker()			( memory_call_banked_function( BANKED_FUNCTION_INIT_TRACKER ) )
    #define tracker_select_song(a)		( memory_call_banked_function_a16( BANKED_FUNCTION_TRACKER_SELECT_SONG, (a) ) )
    #define tracker_start()			( memory_call_banked_function( BANKED_FUNCTION_TRACKER_START ) )
    #define tracker_stop()			( memory_call_banked_function( BANKED_FUNCTION_TRACKER_STOP ) )
    #define tracker_do_periodic_tasks()		( memory_call_banked_function( BANKED_FUNCTION_TRACKER_DO_PERIODIC_TASKS ) )
    #define init_tracker_sound_effects()	( memory_call_banked_function( BANKED_FUNCTION_INIT_TRACKER_SOUND_EFFECTS ) )
    #define tracker_play_fx(a)			( memory_call_banked_function_a16( BANKED_FUNCTION_TRACKER_PLAY_FX, (a) ) )
    #define tracker_rewind()			( memory_call_banked_function( BANKED_FUNCTION_TRACKER_REWIND ) )
    #define tracker_play_pending_fx()		( memory_call_banked_function( BANKED_FUNCTION_TRACKER_PLAY_PENDING_FX ) )
    #define tracker_request_fx(a)		( memory_call_banked_function_a16( BANKED_FUNCTION_TRACKER_REQUEST_FX, (a) ) )
    #define beeper_request_fx(a)		( memory_call_banked_function_a16( BANKED_FUNCTION_BEEPER_REQUEST_FX, (uint16_t)(a) ) )
    #define init_beeper()			( memory_call_banked_function( BANKED_FUNCTION_INIT_BEEPER ) )
    #define beeper_play_fx(a)			( memory_call_banked_function_a16( BANKED_FUNCTION_BEEPER_PLAY_FX, (uint16_t)(a) ) )
#endif

#endif // _MEMORY_H

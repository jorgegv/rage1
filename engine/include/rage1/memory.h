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

    #include "banked_function_defs.h"

#endif

#endif // _MEMORY_H

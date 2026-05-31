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

// B5-4: guard updated from BUILD_FEATURE_ZX_TARGET_128 to the canonical
// banked-platform condition.  ZX 128 defines both macros; the new
// condition is equivalent there (byte-identical).  cpc-flat compiles out.
#if defined( BUILD_FEATURE_PLATFORM_ZX128 ) || defined( BUILD_FEATURE_PLATFORM_CPC_BANKED )

    extern uint8_t memory_current_memory_bank;
    // returns previous memory bank
    uint8_t memory_switch_bank( uint8_t bank_num ) __z88dk_fastcall;

    // reserved memory bank for banked functions in engine code
    // B1-4: gated on PLATFORM_ZX128; other platforms (e.g. CPC) will
    // define their own ENGINE_CODE_MEMORY_BANK under their own platform
    // macro. Value 4 mirrors banking.zx128.engine_code_memory_bank in
    // etc/rage1-config.yml.
    #ifdef BUILD_FEATURE_PLATFORM_ZX128
        #define ENGINE_CODE_MEMORY_BANK		4
        // base address of the bank-switched 16K window where the engine
        // banked-function table lives. Mirrors banking.zx128.swap_window
        // in etc/rage1-config.yml.
        #define BANKED_FUNCTION_TABLE_BASE	0xC000
        // base address from which a dataset is read when its bank is
        // paged into the swap window. Same physical window as the
        // banked-function table; named separately so dataset code reads
        // semantically (it loads a dataset, not a function table).
        #define DATASET_LOAD_BASE		0xC000
    #endif

    // function type definitions
    // types for all different function signatures used must be defined here
    typedef void (*banked_function_t)( void );
    typedef void (*banked_function_a16_t)( uint16_t arg );
    typedef uint8_t (*banked_function_a16_a8_r8_t)( uint16_t arg1, uint8_t arg2 );

    // trampoline functions to call banked functions
    // functions for all different function signatures used must exist
    void memory_call_banked_function( uint8_t function_id );
    void memory_call_banked_function_a16( uint8_t function_id, uint16_t arg );
    uint8_t memory_call_banked_function_a16_a8_r8( uint8_t function_id, uint16_t arg1, uint8_t arg2 );

    //////////////////////////////////////////////////////////////////////////
    // Definitions for engine banked functions are generated automatically
    // and included from here
    //////////////////////////////////////////////////////////////////////////

    #include "banked_function_defs.h"

#endif // BUILD_FEATURE_PLATFORM_ZX128 || BUILD_FEATURE_PLATFORM_CPC_BANKED

#endif // _MEMORY_H

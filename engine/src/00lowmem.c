////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <stdlib.h>
#include <stdint.h>
#include <alloc.h>

#include "rage1/memory.h"
#include "rage1/debug.h"

#include "game_data.h"

// B5-4: guard updated from BUILD_FEATURE_ZX_TARGET_128 to the canonical
// banked-platform condition.  ZX 128 defines both macros, so the new
// condition is equivalent there (byte-identical output).  cpc-flat
// (no banking) compiles this entire block out cleanly.
#if defined( BUILD_FEATURE_PLATFORM_ZX128 ) || defined( BUILD_FEATURE_PLATFORM_CPC_BANKED )
// trampoline function to call banked functions
void memory_call_banked_function( uint8_t function_id ) {
    // pointer to table of functions in bank
    banked_function_t *run_function = (banked_function_t *) BANKED_FUNCTION_TABLE_BASE;

    uint8_t previous_memory_bank;

    // save current memory bank, get the bank number from the codeset info
    // table and switch to the proper bank
    previous_memory_bank = memory_switch_bank( ENGINE_CODE_MEMORY_BANK );

    // call the function
    run_function[ function_id ]();

    // switch back to previous memory bank
    memory_switch_bank( previous_memory_bank );
}

void memory_call_banked_function_a16( uint8_t function_id, uint16_t arg ) {
    // pointer to table of functions in bank
    banked_function_a16_t *run_function = (banked_function_a16_t *) BANKED_FUNCTION_TABLE_BASE;

    uint8_t previous_memory_bank;

    // save current memory bank, get the bank number from the codeset info
    // table and switch to the proper bank
    previous_memory_bank = memory_switch_bank( ENGINE_CODE_MEMORY_BANK );

    // call the function
    run_function[ function_id ]( arg );

    // switch back to previous memory bank
    memory_switch_bank( previous_memory_bank );
}

uint8_t memory_call_banked_function_a16_a8_r8( uint8_t function_id, uint16_t arg1, uint8_t arg2 ) {


    // pointer to table of functions in bank
    banked_function_a16_a8_r8_t *run_function = (banked_function_a16_a8_r8_t *) BANKED_FUNCTION_TABLE_BASE;

    uint8_t previous_memory_bank;
    uint8_t retval;

    // save current memory bank, get the bank number from the codeset info
    // table and switch to the proper bank
    previous_memory_bank = memory_switch_bank( ENGINE_CODE_MEMORY_BANK );

    // call the function
    retval = run_function[ function_id ]( arg1, arg2 );

    // switch back to previous memory bank
    memory_switch_bank( previous_memory_bank );

    return retval;
}
#endif // BUILD_FEATURE_PLATFORM_ZX128 || BUILD_FEATURE_PLATFORM_CPC_BANKED

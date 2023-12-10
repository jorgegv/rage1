////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#include <stdint.h>

#include "features.h"

#include "rage1/codeset.h"
#include "rage1/dataset.h"
#include "rage1/memory.h"

#include "game_data.h"

#ifdef BUILD_FEATURE_CODESETS

// this should be here, but we need to ensure that it is _always_ in low
// memory below 0xC000, so we put it in lowmem/asmdata.asm
// struct codeset_assets_s *codeset_assets;

// List of valid codeset banks.  Should be in sync with the list of the same
// name in datagen.pl and banktool.pl
uint8_t codeset_valid_banks[1] = { 6 };

// global codeset initialization called from main
void init_codesets( void ) {
    uint8_t i;

    // Setup codeset_assets pointer.  The codeset assets struct is always
    // placed at the beginning of the codeset memory bank, which is mapped
    // at 0xC000
    codeset_assets = ( struct codeset_assets_s *) 0xC000;

    // call init functions for all codesets
    for ( i = 0; i < NUM_CODESETS; i++ ) {
        // codeset_assets always points to 0xC000, but when switching banks
        // we access the different codeset_assets struct for each bank
        memory_switch_bank( codeset_valid_banks[ i ] );
        codeset_assets->game_state	= &game_state;
        codeset_assets->home_assets	= home_assets;
        codeset_assets->banked_assets	= banked_assets;
    }
    // switch back to bank 0
    memory_switch_bank( 0 );
}

// call a given codeset function by its global function index
void codeset_call_function( uint8_t global_function_num ) {
    struct codeset_function_info_s *f;
    uint8_t previous_memory_bank;

    // for efficiency
    f = &all_codeset_functions[ global_function_num ];

    // save current memory bank, get the bank number from the codeset info
    // table and switch to the proper bank
    previous_memory_bank = memory_switch_bank( f->bank_num );

    // call the function
    codeset_assets->functions[ f->local_function_num ]();

    // switch back to previous memory bank
    memory_switch_bank( previous_memory_bank );
}

#endif // BUILD_FEATURE_CODESETS

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

struct codeset_assets_s *codeset_assets;

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
        memory_switch_bank( codeset_info[ i ].bank_num );
        codeset_assets->init( &game_state, home_assets, banked_assets );
    }
    // switch back to bank 0
    memory_switch_bank( 0 );
}

// call a given codeset function by its global function index
void codeset_call_function( uint8_t global_function_num ) {
    struct codeset_function_info_s *f;
    f = &all_codeset_functions[ global_function_num ];

    // get the bank number from the codeset info table and swicth to the
    // proper bank
    memory_switch_bank( codeset_info[ f->codeset_num ].bank_num );

    // call the function
    codeset_assets->functions[ f->local_function_num ]();

    // switch back to bank 0
    memory_switch_bank( 0 );
}

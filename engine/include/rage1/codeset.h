////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _CODESET_H
#define _CODESET_H

#include <stdint.h>

#include "features.h"

#include "rage1/game_state.h"
#include "rage1/dataset.h"

////////////////////////////////////////////////////////////
//
// Definitions for Local Data that goes into each codeset
//
////////////////////////////////////////////////////////////

// type definitions for codeset functions:

// init function - this is called once at program startup
typedef void (*codeset_init_function_t)(
    struct game_state_s		*game_state,
    struct dataset_assets_s	*home_assets,
    struct dataset_assets_s	*banked_assets
);

// general codeset function - this can be called any time
typedef void (*codeset_function_t)( void );

// struct for codeset local info: there is only one instance of this
// structure on each codeset and it goes at a fixed address of 0xC000
// (same trick here as for datasets)
struct codeset_assets_s {

    // codeset initialization function
    codeset_init_function_t	init;

    // these values are setup at program startup with a call to the init
    // function
    struct game_state_s		*game_state;
    struct dataset_assets_s	*banked_assets;
    struct dataset_assets_s	*home_assets;

    // these are the codeset functions themselves
    uint8_t			num_functions;
    codeset_function_t		*functions;

};

///////////////////////////////////////////////////////////
//
// Definitions for Global Data that goes into low memory
//
///////////////////////////////////////////////////////////

// struct definition for the global table of codeset information
struct codeset_info_s {
    uint8_t	bank_num;
};

// global table of codeset info structs
extern struct codeset_info_s codeset_info[];

// struct definition for the global table of codeset function information
struct codeset_function_info_s {
    uint8_t	codeset_num;
    uint8_t	local_function_num;
};
// this array is indexed by the global function number, we use that to get
// the codeset and local function number
extern struct codeset_function_info_s *all_codeset_functions[];

// function to call a given codeset function, wherever it may be
void codeset_call_function( uint8_t global_function_num );

#endif // _CODESET_H

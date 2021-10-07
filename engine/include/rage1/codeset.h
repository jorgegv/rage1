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

// codeset initialization at program start
void init_codesets( void );

// function to call a given codeset function, wherever it may be
void codeset_call_function( uint8_t global_function_num );

////////////////////////////////////////////////////////////////
//
// Engine functions that are implemented as CODESET functions
//
////////////////////////////////////////////////////////////////
//
// We need to define the global function IDs here for CODESET 0 functions
// and those IDs will be reserved.  Global indexes for user CODESET
// functions will be assigned starting with
// CODESET_GLOBAL_INDEX_RESERVED_MAX + 1
//
// Whenever you migrate an engine function to be a CODESET function (or
// create a new one), assign a new ID and update
// CODESET_GLOBAL_INDEX_RESERVED_MAX, so that user CODESET function IDs are
// assigned after that
//
// Example:
// ....
// #define	CODESET_GLOBAL_MY_FUNCTION_1		0
// #define	CODESET_GLOBAL_MY_FUNCTION_2		1
// #define	CODESET_GLOBAL_MY_FUNCTION_3		2
//
// #define	CODESET_GLOBAL_INDEX_RESERVED_MAX	2

// define the engine CODESET reserved function IDs here...
#define CODESET_GLOBAL_INDEX_RESERVED_MAX	0

#endif // _CODESET_H

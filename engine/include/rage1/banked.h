////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _BANKED_H
#define _BANKED_H

// only process this file if building banked code
#ifdef _BANKED_CODE_BUILD

    #include <stdint.h>
    #include "features.h"
    // this is generated during build
    #include "mainsyms.h"
    #include "rage1/game_state.h"

    // commodity #defines using the main symbols above may be defined here
    // remember: these #defines are only valid while compiling BANKED code
    #define	game_state			( *( struct game_state_s *)		MAIN_SYMBOL_game_state )
    #define	screen_pos_tile_type_data	( ( uint8_t *)				MAIN_SYMBOL_screen_pos_tile_type_data )
    #define	home_assets			( *( struct dataset_assets_s **)	MAIN_SYMBOL_home_assets )
    #define	banked_assets			( *( struct dataset_assets_s **)	MAIN_SYMBOL_banked_assets )
    #define	bullet_state_data		( ( struct bullet_state_data_s **)	MAIN_SYMBOL_bullet_state_data )
    #define	full_screen			( *( struct sp1_Rect *)			MAIN_SYMBOL_full_screen )

#endif // _BANKED_CODE_BUILD

#endif // _BANKED_H
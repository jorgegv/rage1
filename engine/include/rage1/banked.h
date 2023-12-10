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

#include <stdint.h>
#include <games/sp1.h>

#include "features.h"

#include "rage1/game_state.h"
#include "rage1/screen.h"
#include "rage1/dataset.h"
#include "rage1/bullet.h"

// shared data between low memory and banked code
struct main_shared_data_s {
    struct game_state_s *game_state;
    struct dataset_assets_s *home_assets;
    struct dataset_assets_s *banked_assets;
    uint8_t *screen_pos_tile_type_data;
    struct bullet_state_data_s *bullet_state_data;
};
extern struct main_shared_data_s main_shared_data;
void init_banked_code( void );

// only process this file if building banked code
#ifdef _BANKED_CODE_BUILD

    #define	game_state			( *main_shared_data.game_state )
    #define	screen_pos_tile_type_data	( main_shared_data.screen_pos_tile_type_data )
    #define	home_assets			( main_shared_data.home_assets )
    #define	banked_assets			( main_shared_data.banked_assets )
    #define	bullet_state_data		( main_shared_data.bullet_state_data )

#endif // _BANKED_CODE_BUILD

#endif // _BANKED_H

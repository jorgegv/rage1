////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include "rage1/game_state.h"
#include "rage1/sprite.h"
#include "rage1/screen.h"
#include "rage1/map.h"
#include "rage1/debug.h"
#include "rage1/util.h"

#include "game_data.h"

#include "rage1/banked.h"

void sprite_move_offscreen( struct sp1_ss *s ) {
    sp1_MoveSprAbs( s, &full_screen, NULL, OFF_SCREEN_ROW, OFF_SCREEN_COLUMN, 0, 0 );
}

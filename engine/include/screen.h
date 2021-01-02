////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _SCREEN_H
#define _SCREEN_H

#include <games/sp1.h>
#include <stdint.h>

// External frame coordinates and dimensions
#define BORDER_TOP		0
#define BORDER_LEFT		0
#define BORDER_BOTTOM		22
#define BORDER_RIGHT		31
#define BORDER_WIDTH		( BORDER_RIGHT - BORDER_LEFT + 1 )
#define BORDER_HEIGHT		( BORDER_BOTTOM - BORDER_TOP + 1 )

// Internal game area coordinates and dimensions
#define GAME_AREA_TOP		1
#define GAME_AREA_LEFT		1
#define GAME_AREA_BOTTOM	21
#define GAME_AREA_RIGHT		30
#define GAME_AREA_WIDTH		( GAME_AREA_RIGHT - GAME_AREA_LEFT + 1 )
#define GAME_AREA_HEIGHT	( GAME_AREA_BOTTOM - GAME_AREA_TOP + 1 )

// Inventory area
#define INVENTORY_TOP		( BORDER_BOTTOM + 1 )
#define INVENTORY_BOTTOM	( BORDER_BOTTOM + 1 )
#define INVENTORY_LEFT		( BORDER_RIGHT - 15 )
#define INVENTORY_RIGHT		( BORDER_RIGHT )
#define INVENTORY_WIDTH		( INVENTORY_RIGHT - INVENTORY_LEFT + 1 )
#define INVENTORY_HEIGHT	( INVENTORY_BOTTOM - INVENTORY_TOP + 1 )

// Lives area
#define LIVES_AREA_TOP		( BORDER_BOTTOM + 1 )
#define LIVES_AREA_BOTTOM	( BORDER_BOTTOM + 1 )
#define LIVES_AREA_LEFT		( BORDER_LEFT )
#define LIVES_AREA_RIGHT	( BORDER_LEFT + 15 )
#define LIVES_AREA_WIDTH	( LIVES_AREA_RIGHT - LIVES_AREA_LEFT + 1 )
#define LIVES_AREA_HEIGHT	( LIVES_AREA_BOTTOM - LIVES_AREA_TOP + 1 )

// off-screen cell coords (used for "parking" sprites)
#define OFF_SCREEN_ROW		24
#define OFF_SCREEN_COLUMN	0

// rectangles covering the full screen and other screen areas
extern struct sp1_Rect full_screen;
extern struct sp1_Rect border_area;
extern struct sp1_Rect game_area;
extern struct sp1_Rect inventory_area;
extern struct sp1_Rect lives_area;

// global text printing context
extern struct sp1_pss print_ctx;

// functions
void run_menu_screen(void);
void run_intro_screen(void);
void run_game_end_screen(void);
void run_game_over_screen(void);

#endif // _SCREEN_H

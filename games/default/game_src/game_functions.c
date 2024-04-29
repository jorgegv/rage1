////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <arch/spectrum.h>
#include <games/sp1.h>
#include <input.h>

#include "rage1/screen.h"
#include "rage1/map.h"
#include "rage1/sp1engine.h"
#include "rage1/game_state.h"
#include "rage1/controller.h"
#include "rage1/beeper.h"
#include "rage1/btile.h"
#include "rage1/flow.h"
#include "rage1/debug.h"
#include "rage1/memory.h"

#include "game_data.h"

#include "kbd.h"

// External frame coordinates and dimensions
#define BORDER_TOP		0
#define BORDER_LEFT		0
#define BORDER_BOTTOM		22
#define BORDER_RIGHT		31
#define BORDER_WIDTH		( BORDER_RIGHT - BORDER_LEFT + 1 )
#define BORDER_HEIGHT		( BORDER_BOTTOM - BORDER_TOP + 1 )

struct sp1_Rect border_area = { BORDER_TOP, BORDER_LEFT, BORDER_WIDTH, BORDER_HEIGHT };

// global text printing context
struct sp1_pss print_ctx = {
   &border_area,			// bounds
   SP1_PSSFLAG_INVALIDATE,		// flags
   0,0,					// initial position x,y
   0, DEFAULT_BG_ATTR,			// attr mask and attribute
   0,0					// RESERVED
};

void my_menu_screen(void) {

   uint8_t i;
   uint16_t key_pressed;

   // clear screen
   sp1_ClearRectInv( &full_screen, DEFAULT_BG_ATTR, ' ', SP1_RFLAG_TILE | SP1_RFLAG_COLOUR );
   sp1_UpdateNow();

   // draw external border
   for ( i=1; i<31; i++ ) {
      btile_draw( BORDER_TOP, i, 	BTILE_BORDERH, TT_DECORATION, &full_screen);
      btile_draw( BORDER_BOTTOM, i,	BTILE_BORDERH, TT_DECORATION, &full_screen );
   }
   for ( i=1; i<23; i++ ) {
      btile_draw( i, BORDER_LEFT,	BTILE_BORDERV, TT_DECORATION, &full_screen );
      btile_draw( i, BORDER_RIGHT,	BTILE_BORDERV, TT_DECORATION, &full_screen );
   }
   btile_draw( BORDER_TOP, BORDER_LEFT,		BTILE_BORDERTL, TT_DECORATION, &full_screen );
   btile_draw( BORDER_TOP, BORDER_RIGHT,	BTILE_BORDERTR, TT_DECORATION, &full_screen );
   btile_draw( BORDER_BOTTOM, BORDER_LEFT,	BTILE_BORDERBL, TT_DECORATION, &full_screen );
   btile_draw( BORDER_BOTTOM, BORDER_RIGHT,	BTILE_BORDERBR, TT_DECORATION, &full_screen );

   // draw menu
   sp1_PrintString( &print_ctx, "\x13\x01" );		// bright 1
   sp1_PrintString( &print_ctx, "\x10\x04" );		// green color
   sp1_PrintString( &print_ctx, "\x16\x09\x07 Test Adventure" );
   sp1_PrintString( &print_ctx, "\x10\x05" );		// cyan color
   sp1_PrintString( &print_ctx, "\x16\x0e\x09 1: KEYBOARD" );
   sp1_PrintString( &print_ctx, "\x16\x0f\x09 2: KEMPSTON" );
   sp1_PrintString( &print_ctx, "\x16\x10\x09 3: SINCLAIR" );
   sp1_PrintString( &print_ctx, "\x16\x11\x09 4: REDEFINE" );

   // draw full screen
   sp1_UpdateNow();

   controller_reset_all();

   tracker_select_song( TRACKER_SONG_GAME_SONG );
   tracker_rewind();
   tracker_start();

   // wait for selection
   sp1_PrintString( &print_ctx, "\x16\x13\x06 Selection: " );
   while ( ! game_state.controller.type ) {
      key_pressed = 0;
      while ( ! key_pressed ) { key_pressed = in_inkey(); }
      switch ( key_pressed ) {
         case '1':
            game_state.controller.type = CTRL_TYPE_KEYBOARD;
            sp1_PrintString( &print_ctx, "Keyboard" );
            break;
         case '2':
            game_state.controller.type = CTRL_TYPE_KEMPSTON;
            sp1_PrintString( &print_ctx, "Kempston" );
            break;
         case '3':
            game_state.controller.type = CTRL_TYPE_SINCLAIR1;
            sp1_PrintString( &print_ctx, "Sinclair" );
            break;
         case '4':
            // wait until no key pressed
            in_wait_nokey();

            sp1_PrintString( &print_ctx,"\x16\x13\x06 Key UP:   " );
            sp1_UpdateNow();
            game_state.controller.keys.up = capture_key_scancode();
            beeper_play_fx( SOUND_CONTROLLER_SELECTED );
            in_pause( 500 );

            sp1_PrintString( &print_ctx,"\x16\x13\x06 Key DOWN: " );
            sp1_UpdateNow();
            game_state.controller.keys.down = capture_key_scancode();
            beeper_play_fx( SOUND_CONTROLLER_SELECTED );
            in_pause( 500 );

            sp1_PrintString( &print_ctx,"\x16\x13\x06 Key LEFT: " );
            sp1_UpdateNow();
            game_state.controller.keys.left = capture_key_scancode();
            beeper_play_fx( SOUND_CONTROLLER_SELECTED );
            in_pause( 500 );

            sp1_PrintString( &print_ctx,"\x16\x13\x06 Key RIGHT:" );
            sp1_UpdateNow();
            game_state.controller.keys.right = capture_key_scancode();
            beeper_play_fx( SOUND_CONTROLLER_SELECTED );
            in_pause( 500 );

            sp1_PrintString( &print_ctx,"\x16\x13\x06 Key FIRE: " );
            sp1_UpdateNow();
            game_state.controller.keys.fire = capture_key_scancode();
            beeper_play_fx( SOUND_CONTROLLER_SELECTED );
            in_pause( 500 );

            sp1_PrintString( &print_ctx, "\x16\x13\x06 Selection: " );
            sp1_UpdateNow();
            break;
      }
   }
   sp1_UpdateNow();
   in_pause(100);
   beeper_play_fx( SOUND_CONTROLLER_SELECTED );
   in_pause(500);

   // stop playing and reset the song
   tracker_stop();
   tracker_select_song( TRACKER_SONG_GAME_SONG );
   tracker_rewind();

   // clear screen and exit to main game loop
   sp1_ClearRectInv( &game_area, DEFAULT_BG_ATTR, ' ', SP1_RFLAG_TILE | SP1_RFLAG_COLOUR );
}

// info box text printing context
struct sp1_pss textbox_ctx = {
   &border_area,			// bounds
   SP1_PSSFLAG_INVALIDATE,		// flags
   0,0,					// initial position x,y
   0, DEFAULT_BG_ATTR | BRIGHT,		// attr mask and attribute
   0,0					// RESERVED
};

void draw_text_box( struct sp1_Rect *box, char *msg ) {
   static uint8_t i;
   static struct sp1_Rect interior;

   interior.row = box->row + 1;
   interior.col = box->col + 1;
   interior.width = box->width - 2;
   interior.height = box->height - 2;

   // draw external border
   i = box->col + box->width - 2;
   while ( i > box->col ) {
      btile_draw( box->row, i, BTILE_BORDERH, TT_DECORATION, &full_screen );
      btile_draw( box->row + box->height - 1, i, BTILE_BORDERH, TT_DECORATION, &full_screen );
      i--;
   }

   i = box->row + box->height - 2;
   while ( i > box->row ) {
      btile_draw( i, box->col, BTILE_BORDERV, TT_DECORATION, &full_screen );
      btile_draw( i, box->col + box->width - 1, BTILE_BORDERV, TT_DECORATION, &full_screen );
      i--;
   }

   btile_draw( box->row, box->col, BTILE_BORDERTL, TT_DECORATION, &full_screen );
   btile_draw( box->row, box->col + box->width - 1, BTILE_BORDERTR, TT_DECORATION, &full_screen );
   btile_draw( box->row + box->height - 1, box->col, BTILE_BORDERBL, TT_DECORATION, &full_screen );
   btile_draw( box->row + box->height - 1, box->col + box->width - 1, BTILE_BORDERBR, TT_DECORATION, &full_screen );

   // clear interior rectangle
   if ( ( interior.width > 0 ) && ( interior.height > 0 ) ) {
      sp1_ClearRectInv( &interior, DEFAULT_BG_ATTR | BRIGHT, ' ', SP1_RFLAG_TILE | SP1_RFLAG_COLOUR );

      // output text
      textbox_ctx.bounds = &interior;
      sp1_SetPrintPos( &textbox_ctx, 0, 0 );
      sp1_PrintString( &textbox_ctx, msg );
   }

   // update screen
   sp1_UpdateNow();
}

struct sp1_Rect b1 = { 12, 12,  6, 2 };
struct sp1_Rect b2 = { 11,  9, 12, 3 };
struct sp1_Rect b3 = {  9,  8, 16, 5 };

void my_intro_screen(void) {

   draw_text_box( &b1, "" );
   sp1_UpdateNow();
   in_pause( 100 );

   draw_text_box( &b2, "" );
   sp1_UpdateNow();
   in_pause( 100 );

   draw_text_box( &b3, "Get all items\r and kill all\r   enemies!" );
   sp1_UpdateNow();

   in_wait_key();

   // clear screen and exit
   sp1_ClearRectInv( &game_area, DEFAULT_BG_ATTR, ' ', SP1_RFLAG_TILE | SP1_RFLAG_COLOUR );
   sp1_UpdateNow();
}

void my_game_end_screen(void) {
   draw_text_box( &b2, " You won!" );
   sp1_UpdateNow();
   beeper_play_fx( SOUND_GAME_WON );

   in_wait_nokey();
   in_wait_key();

   // clear screen and exit
   sp1_ClearRectInv( &game_area, DEFAULT_BG_ATTR, ' ', SP1_RFLAG_TILE | SP1_RFLAG_COLOUR );
   sp1_UpdateNow();
}

void my_game_over_screen(void) {
   draw_text_box( &b2, "GAME OVER!" );
   sp1_UpdateNow();
   beeper_play_fx( SOUND_GAME_OVER );

   in_wait_nokey();
   in_wait_key();

   // clear screen and exit
   sp1_ClearRectInv( &game_area, DEFAULT_BG_ATTR, ' ', SP1_RFLAG_TILE | SP1_RFLAG_COLOUR );
   sp1_UpdateNow();
}


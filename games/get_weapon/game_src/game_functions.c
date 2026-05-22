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
#include <input.h>

#include "rage1/screen.h"
#include "rage1/map.h"
#include "rage1/gfx.h"
#include "rage1/game_state.h"
#include "rage1/controller.h"
#include "rage1/beeper.h"
#include "rage1/btile.h"
#include "rage1/flow.h"
#include "rage1/debug.h"
#include "rage1/memory.h"

#include "game_data.h"

// External frame coordinates and dimensions
#define BORDER_TOP		0
#define BORDER_LEFT		0
#define BORDER_BOTTOM		22
#define BORDER_RIGHT		31
#define BORDER_WIDTH		( BORDER_RIGHT - BORDER_LEFT + 1 )
#define BORDER_HEIGHT		( BORDER_BOTTOM - BORDER_TOP + 1 )

gfx_rect_t border_area = { BORDER_TOP, BORDER_LEFT, BORDER_WIDTH, BORDER_HEIGHT };

// global text printing context
gfx_print_ctx_t print_ctx = GFX_PRINT_CTX_INIT( border_area, DEFAULT_BG_ATTR );

void my_menu_screen(void) {

   uint8_t i;
   uint16_t key_pressed;

   // clear screen
   gfx_clear_rect( &full_screen, DEFAULT_BG_ATTR, ' ', GFX_CLEAR_TILE | GFX_CLEAR_COLOUR );
   gfx_update();

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
   gfx_print_string( &print_ctx, "\x13\x01" );		// bright 1
   gfx_print_string( &print_ctx, "\x10\x04" );		// green color
   gfx_print_string( &print_ctx, "\x16\x09\x07 Test Adventure" );
   gfx_print_string( &print_ctx, "\x10\x05" );		// cyan color
   gfx_print_string( &print_ctx, "\x16\x0e\x09 1: KEYBOARD" );
   gfx_print_string( &print_ctx, "\x16\x0f\x09 2: KEMPSTON" );
   gfx_print_string( &print_ctx, "\x16\x10\x09 3: SINCLAIR" );

   // draw full screen
   gfx_update();

   controller_reset_all();

   tracker_select_song( TRACKER_SONG_GAME_SONG );
   tracker_rewind();
   tracker_start();

   // wait for selection
   gfx_print_string( &print_ctx, "\x16\x12\x06 Selection: " );
   while ( ! game_state.controller.type ) {
      key_pressed = 0;
      while ( ! key_pressed ) { key_pressed = in_inkey(); }
      switch ( key_pressed ) {
         case '1':
            game_state.controller.type = CTRL_TYPE_KEYBOARD;
            gfx_print_string( &print_ctx, "Keyboard" );
            break;
         case '2':
            game_state.controller.type = CTRL_TYPE_KEMPSTON;
            gfx_print_string( &print_ctx, "Kempston" );
            break;
         case '3':
            game_state.controller.type = CTRL_TYPE_SINCLAIR1;
            gfx_print_string( &print_ctx, "Sinclair" );
            break;
      }
   }
   gfx_update();
   in_pause(100);
   beeper_play_fx( SOUND_CONTROLLER_SELECTED );
   in_pause(500);

   // stop playing and reset the song
   tracker_stop();
   tracker_select_song( TRACKER_SONG_GAME_SONG );
   tracker_rewind();

   // clear screen and exit to main game loop
   gfx_clear_rect( &game_area, DEFAULT_BG_ATTR, ' ', GFX_CLEAR_TILE | GFX_CLEAR_COLOUR );
}

// info box text printing context
gfx_print_ctx_t textbox_ctx = GFX_PRINT_CTX_INIT( border_area, DEFAULT_BG_ATTR | BRIGHT );

void draw_text_box( gfx_rect_t *box, char *msg ) {
   static uint8_t i;
   static gfx_rect_t interior;

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
      gfx_clear_rect( &interior, DEFAULT_BG_ATTR | BRIGHT, ' ', GFX_CLEAR_TILE | GFX_CLEAR_COLOUR );

      // output text
      gfx_print_set_clip( &textbox_ctx, &interior );
      gfx_print_set_pos( &textbox_ctx, 0, 0 );
      gfx_print_string( &textbox_ctx, msg );
   }

   // update screen
   gfx_update();
}

gfx_rect_t b1 = { 12, 12,  6, 2 };
gfx_rect_t b2 = { 11,  9, 12, 3 };
gfx_rect_t b3 = {  9,  8, 16, 5 };

void my_intro_screen(void) {

   draw_text_box( &b1, "" );
   gfx_update();
   in_pause( 100 );

   draw_text_box( &b2, "" );
   gfx_update();
   in_pause( 100 );

   draw_text_box( &b3, "Get all items\r and kill all\r   enemies!" );
   gfx_update();

   in_wait_key();

   // clear screen and exit
   gfx_clear_rect( &game_area, DEFAULT_BG_ATTR, ' ', GFX_CLEAR_TILE | GFX_CLEAR_COLOUR );
   gfx_update();
}

void my_game_end_screen(void) {
   draw_text_box( &b2, " You won!" );
   gfx_update();
   beeper_play_fx( SOUND_GAME_WON );

   in_wait_nokey();
   in_wait_key();

   // clear screen and exit
   gfx_clear_rect( &game_area, DEFAULT_BG_ATTR, ' ', GFX_CLEAR_TILE | GFX_CLEAR_COLOUR );
   gfx_update();
}

void my_game_over_screen(void) {
   draw_text_box( &b2, "GAME OVER!" );
   gfx_update();
   beeper_play_fx( SOUND_GAME_OVER );

   in_wait_nokey();
   in_wait_key();

   // clear screen and exit
   gfx_clear_rect( &game_area, DEFAULT_BG_ATTR, ' ', GFX_CLEAR_TILE | GFX_CLEAR_COLOUR );
   gfx_update();
}


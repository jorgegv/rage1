#include <stdint.h>
#include <games/sp1.h>

#include "rage1/dataset.h"
#include "rage1/game_state.h"

#include "game_data.h"

struct sp1_Rect title_box = { 23, 12, 10, 1 };

struct sp1_pss title_ctx = {
   &title_box,				// bounds
   SP1_PSSFLAG_INVALIDATE,		// flags
   0,0,					// initial position x,y
   0, DEFAULT_BG_ATTR,			// attr mask and attribute
   0,0					// RESERVED
};

void show_screen_title( void ) {
    sp1_ClearRectInv( &title_box, DEFAULT_BG_ATTR, ' ', SP1_RFLAG_TILE | SP1_RFLAG_COLOUR );
    if ( game_state.current_screen_ptr->title ) {
        sp1_SetPrintPos( &title_ctx, 0, 0 );
        sp1_PrintString( &title_ctx, "\x13\x01" );           // bright 1
        sp1_PrintString( &title_ctx, game_state.current_screen_ptr->title );
    }
}

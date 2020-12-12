////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is ublished under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#pragma output REGISTER_SP		= 0xd000    // place stack at $d000 at startup
#pragma output CRT_STACK_SIZE		= 500
#pragma output CRT_ENABLE_RESTART	= 1         // not returning to basic
#pragma output CRT_ENABLE_CLOSE		= 0         // do not close files on exit
#pragma output CLIB_EXIT_STACK_SIZE	= 0         // no exit stack
#pragma output CLIB_MALLOC_HEAP_SIZE	= -1      // malloc heap size (not sure what is needed exactly)
#pragma output CLIB_STDIO_HEAP_SIZE	= 0         // no memory needed to create file descriptors
#pragma output CLIB_FOPEN_MAX		= 0         // no allocated FILE structures, -1 for no file lists too
#pragma output CLIB_OPEN_MAX		= 0         // no fd table

#include <intrinsic.h>
#include <arch/spectrum.h>

#include "memory.h"
#include "sp1engine.h"
#include "map.h"

// Big tile 'BorderTL'

uint8_t btile_BorderTL_tile_data[8] = {
0x00, 0x07, 0x1f, 0x38, 0x30, 0x63, 0x67, 0x66
};
uint8_t *btile_BorderTL_tiles[1] = { &btile_BorderTL_tile_data[0] };
uint8_t btile_BorderTL_attrs[1] = { INK_CYAN | PAPER_BLACK | BRIGHT };
struct map_btile_s btile_BorderTL = { 1, 1, TT_DECORATION, &btile_BorderTL_tiles[0], &btile_BorderTL_attrs[0] };

void init_program(void) {
   init_memory();
   init_sp1();
}


void main(void)
{
   init_program();
   while (1) {
      map_draw_btile( &btile_BorderTL, 0, 0 );
//      sp1_PrintAtInv( 0, 0, INK_YELLOW | PAPER_BLACK, (uint16_t)btile_BorderTL_tiles[0] );
      sp1_UpdateNow();
      intrinsic_halt();
   }
}

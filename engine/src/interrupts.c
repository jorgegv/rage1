////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

/////////////////////////////////////
//
// Interrupt initialization
//
/////////////////////////////////////

#include <stdlib.h>
#include <im2.h>
#include <string.h>
#include <intrinsic.h>
#include <z80.h>

#include "rage1/debug.h"

// data struct and ISR hook for timekeeping
struct time {
   uint8_t hour, min, sec, frame;
} current_time = { 0, 0, 0, 0 };

// timer tick routine
IM2_DEFINE_ISR(do_timer_tick)
{
   if ( ++current_time.frame == 50 ) {		// 50 frames per second
      current_time.frame = 0;
      if ( ++current_time.sec == 60 ) {
         current_time.sec = 0;
         if ( ++current_time.min == 60 ) {
            current_time.min = 0;
            ++current_time.hour;
         }
      }
   }
}

// Initialize interrupts in IM2 mode
#define IV_ADDR		( ( unsigned char * ) 0xd000 )
#define ISR_ADDR	( ( unsigned char * ) 0xd1d1 )
#define IV_BYTE		( 0xd1 )
#define Z80_OPCODE_JP	( 0xc3 )

void init_interrupts(void) {
   intrinsic_di();
   im2_init(IV_ADDR);
   memset(IV_ADDR,IV_BYTE,257);
   z80_bpoke( ISR_ADDR, Z80_OPCODE_JP );
   z80_wpoke( ISR_ADDR + 1, (uint16_t) do_timer_tick );
   im2_init( IV_ADDR );
   intrinsic_ei();
}

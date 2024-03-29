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

#include "rage1/interrupts.h"
#include "rage1/debug.h"
#include "rage1/memory.h"

#include "game_data.h"

// data struct and ISR hook for timekeeping
// struct time_s current_time = { 0, 0, 0, 0 };
// moved to lowmem/asmdata.asm to ensure it is placed in memory below 0xC000

// timer tick routine, invoked from ISR
void do_timer_tick( void ) {
   current_time.ticks++;
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

// extern uint8_t periodic_tasks_enabled;

// periodic tasks function, invoked from ISR
// do not add code here unless it is strictly needed!
void do_periodic_isr_tasks( void ) {
#ifdef BUILD_FEATURE_TRACKER
   tracker_do_periodic_tasks();
#endif
}

void interrupt_enable_periodic_isr_tasks( void ) {
   periodic_tasks_enabled++;
}
 
///////////////////////
// ISR CONFIGURATION
///////////////////////

// ISR definition
IM2_DEFINE_ISR(service_interrupt)
{
    do_timer_tick();
    if ( periodic_tasks_enabled )
        do_periodic_isr_tasks();
}

// Initialize interrupts in IM2 mode
// IV_ADDR must be 256-byte aligned
// ISR_ADDR and IV_BYTE must match: if IV_BYTE is 0x81, ISR_ADDR must be
// 0x8181

// In 128 mode, IV is at 0x8000-0x8100, ISR at 0x8181, but can be changed in config file
#ifdef BUILD_FEATURE_ZX_TARGET_128
   #define IV_ADDR	( ( unsigned char * ) RAGE1_CONFIG_INT128_IV_TABLE_ADDR )

   #define ISR_ADDR	( ( unsigned char * ) RAGE1_CONFIG_INT128_ISR_ADDRESS )
   #define IV_BYTE	( RAGE1_CONFIG_INT128_ISR_VECTOR_BYTE )
#endif

// In 48 mode, IV is at 0xD000-0xD100, ISR at 0xD1D1
#ifdef BUILD_FEATURE_ZX_TARGET_48
   #define IV_ADDR	( ( unsigned char * ) 0xD000 )
   #define ISR_ADDR	( ( unsigned char * ) 0xD1D1 )
   #define IV_BYTE	( 0xD1 )
#endif

// code to patch at ISR_ADDR: jp xxxx
#define Z80_OPCODE_JP	( 0xc3 )

// This is the only function where barebones intrinsic_ei() and
// intrinsic_di() calls are allowed.  In the rest of RAGE1 code
// intrinsic_di_if_needed() and intrinsic_ei_if_needed() should be used,
// which take into account the interrupt nesting level and only
// disable/enable ints if needed

void init_interrupts(void) {

   // do not disturb :-)
   intrinsic_di();

   // configure ISR
   memset( IV_ADDR, IV_BYTE, 257);
   z80_bpoke( ISR_ADDR, Z80_OPCODE_JP );
   z80_wpoke( ISR_ADDR + 1, (uint16_t) service_interrupt );
   im2_init( IV_ADDR );

   // reset interrupt nesting level
   interrupt_nesting_level = 0;

   // ensure periodic tasks do not run yet
   periodic_tasks_enabled = 0;

   // everything is setup, allow everything now
   intrinsic_ei();
}

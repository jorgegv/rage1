////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _INTERRUPTS_H
#define _INTERRUPTS_H

#include <stdint.h>
#include <intrinsic.h>

#include "features.h"

struct time_s {
   uint8_t hour, min, sec, frame;
   union {
      uint32_t ticks;
      struct {
         uint8_t b0,b1,b2,b3;
      } ticks_bytes;
   };
};
extern struct time_s current_time;

extern uint8_t periodic_tasks_enabled;

extern uint8_t interrupt_nesting_level;

void init_interrupts(void);
void interrupt_enable_periodic_isr_tasks( void );

// enable and disable ints only if needed
#define intrinsic_di_if_needed()	do { if ( !interrupt_nesting_level++ ) intrinsic_di(); } while(0);
#define intrinsic_ei_if_needed()	do { if ( !--interrupt_nesting_level ) intrinsic_ei(); } while(0);

#endif // _INTERRUPTS_H

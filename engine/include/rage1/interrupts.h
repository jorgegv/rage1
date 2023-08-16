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

void init_interrupts(void);
void interrupt_enable_periodic_isr_tasks( void );

#endif // _INTERRUPTS_H

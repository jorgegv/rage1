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
};
extern struct time_s current_time;

void init_interrupts(void);

#endif // _INTERRUPTS_H

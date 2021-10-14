////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _MEMORY_H
#define _MEMORY_H

#include <stdint.h>

#include "features.h"

#ifdef BUILD_FEATURE_ZX_TARGET_128
extern uint8_t memory_current_memory_bank;
void memory_switch_bank( uint8_t bank_num );
#endif

void init_memory(void);

#endif // _MEMORY_H

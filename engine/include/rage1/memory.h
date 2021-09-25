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

#include "game_data.h"

// Memory allocator settings
#define MALLOC_HEAP_SIZE        BUILD_MAX_HEAP_SPRITE_USAGE
#define MALLOC_HEAP_START       ((unsigned char *)(0x8000 - MALLOC_HEAP_SIZE))

void memory_switch_bank( uint8_t bank_num );

void init_memory(void);
#endif // _MEMORY_H

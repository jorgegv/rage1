////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <stdlib.h>
#include <stdint.h>
#include <alloc.h>

#include "rage1/memory.h"
#include "rage1/debug.h"

#include "game_data.h"

/////////////////////////////////////
//
// Memory initialization
//
/////////////////////////////////////

// Memory allocator settings
#define MALLOC_HEAP_SIZE        BUILD_MAX_HEAP_SPRITE_USAGE
#define MALLOC_HEAP_START       ((unsigned char *)(0x8000 - MALLOC_HEAP_SIZE))

// memory init depends on the target

#ifdef BUILD_FEATURE_ZX_TARGET_128
// heap is specifically defined in 128K build
unsigned char *_malloc_heap;
void init_memory(void) {
    _malloc_heap = MALLOC_HEAP_START;
    heap_init( MALLOC_HEAP_START, MALLOC_HEAP_SIZE );
}
#endif

#ifdef BUILD_FEATURE_ZX_TARGET_48
// heap is defined automatically in 48K build
void init_memory(void) {
}
#endif

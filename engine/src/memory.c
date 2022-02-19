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
#include <alloc/malloc.h>

#include "rage1/memory.h"
#include "rage1/debug.h"

#include "game_data.h"

/////////////////////////////////////
//
// Memory initialization
//
/////////////////////////////////////

// more memory related code and critical data in directory
// engine/src/lowmem/

// Memory allocator settings
#define MALLOC_HEAP_SIZE        BUILD_MAX_HEAP_SPRITE_USAGE

// memory init depends on the target

// in 128K mode, heap is at the top of the 0x5B00-0x7FFF area
#ifdef BUILD_FEATURE_ZX_TARGET_128
    #define MALLOC_HEAP_START       ((unsigned char *)(0x8000 - MALLOC_HEAP_SIZE))
#endif

// in 48K mode, we define a heap in the BSS segment
#ifdef BUILD_FEATURE_ZX_TARGET_48
    #define MALLOC_HEAP_START       (&_rage1_heap[0])
    unsigned char _rage1_heap[ MALLOC_HEAP_SIZE ];
#endif

// memory initialization
unsigned char *_malloc_heap;
void init_memory(void) {
    _malloc_heap = MALLOC_HEAP_START;
    heap_init( MALLOC_HEAP_START, MALLOC_HEAP_SIZE );

#ifdef BUILD_FEATURE_ZX_TARGET_128
    // initial memory bank
    memory_current_memory_bank = 0;
#endif
}

// trampoline function to call banked functions
// void memory_call_banked_function( uint8_t function_id )
// moved to engine/lowmem so that it is linked in low memory

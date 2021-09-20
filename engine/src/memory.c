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

// memory init depends on the target

#if ( BUILD_FEATURE_ZX_TARGET == 128 )

// heap is specifically defined in 128K build
unsigned char *_malloc_heap;
void init_memory(void) {
    _malloc_heap = MALLOC_HEAP_START;
    heap_init( MALLOC_HEAP_START, MALLOC_HEAP_SIZE );
}

#else

// heap is defined automatically in 48K build
void init_memory(void) {
}

#endif

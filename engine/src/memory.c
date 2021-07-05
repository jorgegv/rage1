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
#include <alloc.h>
#include <stdint.h>

#include "rage1/memory.h"
#include "rage1/debug.h"

/////////////////////////////////////
//
// Memory initialization
//
/////////////////////////////////////

#define MALLOC_HEAP_ADDR	0xbc00
#define MALLOC_HEAP_SIZE	4096

unsigned char *_malloc_heap = MALLOC_HEAP_ADDR;

void init_memory(void) {
   heap_init( (unsigned char *) MALLOC_HEAP_ADDR, MALLOC_HEAP_SIZE );
}

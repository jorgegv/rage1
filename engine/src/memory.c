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

#include "rage1/memory.h"
#include "rage1/debug.h"

/////////////////////////////////////
//
// Memory initialization
//
/////////////////////////////////////

// Memory Allocation Policy
// the sp1 library will call these functions
//void *u_malloc, *u_free;

uint8_t _malloc_heap[ MALLOC_HEAP_SIZE ];

void init_memory(void) {
//   u_malloc = malloc;
//   u_free = free;
}

void memory_select_bank( uint8_t bank_num ) {
}

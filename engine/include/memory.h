////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is ublished under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _MEMORY_H
#define _MEMORY_H

#include <stdint.h>

// Memory allocator settings
#define MALLOC_HEAP_SIZE        2048

void init_memory(void);
#endif // _MEMORY_H

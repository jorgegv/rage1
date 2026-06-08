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

// more memory related code and critical data in directory
// engine/src/lowmem/

// Memory allocator settings
#define MALLOC_HEAP_SIZE        BUILD_MAX_HEAP_SPRITE_USAGE

// memory init depends on the target

// in 128K mode, heap is at the top of the 0x5B00-0x7FFF area, just below the interrupt table
#ifdef BUILD_FEATURE_ZX_TARGET_128
    #define MALLOC_HEAP_START       ((unsigned char *)(RAGE1_CONFIG_INT128_IV_TABLE_ADDR - MALLOC_HEAP_SIZE))
#endif

// in 48K mode, we define a heap in the BSS segment
#ifdef BUILD_FEATURE_ZX_TARGET_48
    #define MALLOC_HEAP_START       (&_rage1_heap[0])
    unsigned char _rage1_heap[ MALLOC_HEAP_SIZE ];
#endif

// G7: cpc-flat (cpc464) is a flat 64K model with no banking — like ZX48, the
// heap lives in the BSS segment.  This is the G7-stub memory map; the real CPC
// memory layout (and cpc6128 banking) is finalised in Phase B/T3.
// B6-3/B6-4: cpc-banked (cpc6128) reuses the same BSS heap reservation for
// now so the file compiles; its final heap placement within page C (Shape A)
// vs page A (Shape B) is a measure-and-iterate item of the memory-HAL work.
#if defined( BUILD_FEATURE_PLATFORM_CPC464 ) || defined( BUILD_FEATURE_PLATFORM_CPC_FLAT ) || \
    defined( BUILD_FEATURE_PLATFORM_CPC6128 ) || defined( BUILD_FEATURE_PLATFORM_CPC_BANKED )
    #ifndef MALLOC_HEAP_START
    #define MALLOC_HEAP_START       (&_rage1_heap[0])
    unsigned char _rage1_heap[ MALLOC_HEAP_SIZE ];
    #endif
#endif

// memory initialization
unsigned char *_malloc_heap;
void init_memory(void) {
    _malloc_heap = MALLOC_HEAP_START;
    // G7: heap_init( heap, size ) is the z88dk new-lib (-clib=sdcc_iy)
    // 2-argument API the ZX engine is written against.  The +cpc build uses a
    // DIFFERENT default clib whose <alloc.h> does not expose that 2-arg form
    // (SDCC error 101 "too many parameters").  Wiring the CPC heap/allocator
    // is the memory-HAL's job in Phase B/T3 — out of scope for the G7 gfx
    // stub.  On CPC the heap BSS array is still reserved above; we just skip
    // the new-lib heap_init() call so the file compiles.  ZX path unchanged
    // (byte-identical).
    // B6-3/B6-4: cpc-banked uses the same +cpc default clib, so it must take
    // the same skip path (the 2-arg heap_init is absent there too).
#if defined( BUILD_FEATURE_PLATFORM_CPC464 ) || defined( BUILD_FEATURE_PLATFORM_CPC_FLAT ) || \
    defined( BUILD_FEATURE_PLATFORM_CPC6128 ) || defined( BUILD_FEATURE_PLATFORM_CPC_BANKED )
    (void) _malloc_heap;    // G7 STUB: CPC allocator wired in Phase B/T3
#else
    heap_init( MALLOC_HEAP_START, MALLOC_HEAP_SIZE );
#endif

#ifdef BUILD_FEATURE_ZX_TARGET_128
    // initial memory bank
    memory_current_memory_bank = 0;
#endif
}

// trampoline function to call banked functions
// void memory_call_banked_function( uint8_t function_id )
// moved to engine/lowmem so that it is linked in low memory

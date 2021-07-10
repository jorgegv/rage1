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
#include <string.h>
#include <arch/zx.h>

#include "rage1/memory.h"
#include "rage1/debug.h"

/////////////////////////////////////
//
// Paging memory manager
//
/////////////////////////////////////

// default memory manager
struct mm_manager_s *mm_default;

// default definitions for ZX128 memory manager
// using banks 1, 3, 4, 6 and 7 with 4 x 4 kB pages each

// 5 banks * 4 pages per bank = 20 pages
#define MM_ZX128_NUM_PAGES	20

// address where memory banks are mapped by the hardware
#define MM_ZX128_BANK_FRAME	0xC000

// address of LOWMEM buffer
#define MM_ZX128_PAGE_FRAME	0x5B00

// page size
#define MM_PAGE_SIZE		4096

// ZX128 page definitions 
struct mm_page_s mm_zx128_pages[ MM_ZX128_NUM_PAGES ] = {	// page number:
    { .bank = 1, .page = 0, .flags = MM_PAGE_ACCESS_RO },	// #0
    { .bank = 1, .page = 1, .flags = MM_PAGE_ACCESS_RO },	// #1
    { .bank = 1, .page = 2, .flags = MM_PAGE_ACCESS_RO },	// #2
    { .bank = 1, .page = 3, .flags = MM_PAGE_ACCESS_RO },	// #3
    { .bank = 3, .page = 0, .flags = MM_PAGE_ACCESS_RO },	// #4
    { .bank = 3, .page = 1, .flags = MM_PAGE_ACCESS_RO },	// #5
    { .bank = 3, .page = 2, .flags = MM_PAGE_ACCESS_RO },	// #6
    { .bank = 3, .page = 3, .flags = MM_PAGE_ACCESS_RO },	// #7
    { .bank = 4, .page = 0, .flags = MM_PAGE_ACCESS_RO },	// #8
    { .bank = 4, .page = 1, .flags = MM_PAGE_ACCESS_RO },	// #9
    { .bank = 4, .page = 2, .flags = MM_PAGE_ACCESS_RO },	// #10
    { .bank = 4, .page = 3, .flags = MM_PAGE_ACCESS_RO },	// #11
    { .bank = 6, .page = 0, .flags = MM_PAGE_ACCESS_RO },	// #12
    { .bank = 6, .page = 1, .flags = MM_PAGE_ACCESS_RO },	// #13
    { .bank = 6, .page = 2, .flags = MM_PAGE_ACCESS_RO },	// #14
    { .bank = 6, .page = 3, .flags = MM_PAGE_ACCESS_RO },	// #15
    { .bank = 7, .page = 0, .flags = MM_PAGE_ACCESS_RO },	// #16
    { .bank = 7, .page = 1, .flags = MM_PAGE_ACCESS_RO },	// #17
    { .bank = 7, .page = 2, .flags = MM_PAGE_ACCESS_RO },	// #18
    { .bank = 7, .page = 3, .flags = MM_PAGE_ACCESS_RO },	// #19
};
struct mm_manager_s mm_manager_zx128 = {
    .current_page	= 0,
    .current_bank	= 0,
    .num_pages		= MM_ZX128_NUM_PAGES,
    .pages		= mm_zx128_pages,
};

void zx128_switch_bank( uint8_t bank ) {
    // Bits 0,1,2 will be always used for selecting banks 0-7
    // Bit 3 = 0 selects normal screen
    // Bit 4 = 0 selects 128K ROM (which is irrelevant for us)
    // Bit 5 = 0 means memory banking is kept enabled (which is what we want)
    // Bits 6,7 are unused
    // ...so if we just write the bank number to the the port, we are fine ;-)
    IO_7FFD = bank & 0x07;
}

void mm_page_in( uint8_t page_no ) {

    // switch source bank
    zx128_switch_bank( mm_default->pages[ page_no ].bank );

    // copy data:
    // bank address: 0xC000, 0xD000, 0xE000 0xF000
    // top nibble is 0xC plus the page number (local to the bank: 0-3)
    // so we need to rotate the page number into position (12 positions left)
    memcpy( (void *) MM_ZX128_PAGE_FRAME,
        (void *) ( MM_ZX128_BANK_FRAME | ( mm_default->pages[ page_no ].page << 12 ) ),
        MM_PAGE_SIZE
    );

    // note the page that was mapped and switch back home bank
    mm_default->current_page = page_no;
    zx128_switch_bank( 0 );
}

void mm_page_out( void ) {

    // only do something for RW pages, ignore otherwise
    if ( mm_default->pages[ mm_default->current_page ].flags & MM_PAGE_ACCESS_RW ) {

        // switch destination bank
        zx128_switch_bank( mm_default->pages[ mm_default->current_page ].bank );

        // copy data back
        // same calculation as above
        memcpy( (void *) ( MM_ZX128_BANK_FRAME | ( mm_default->pages[ mm_default->current_page ].page << 12 ) ),
            (void *) MM_ZX128_PAGE_FRAME,
            MM_PAGE_SIZE
        );

        // switch back home bank
        zx128_switch_bank( 0 );
    }
}

/////////////////////////////////////
//
// Memory initialization
//
/////////////////////////////////////

#define MALLOC_HEAP_ADDRESS	0xbc00
#define MALLOC_HEAP_SIZE	4096

unsigned char *_malloc_heap = MALLOC_HEAP_ADDRESS;

void init_memory(void) {

    // set default paging manager and make sure home bank (0) is mapped
    mm_default = &mm_manager_zx128;
    zx128_switch_bank( 0 );

    // initialize heap
    heap_init( (unsigned char *) MALLOC_HEAP_ADDRESS, MALLOC_HEAP_SIZE );
}

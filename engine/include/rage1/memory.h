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

struct mm_page_s {
    uint8_t		bank;		// bank number - 128K just uses numbers 0-7 but ZXNext can use much more
    unsigned int	page:4;		// up to 16 pages per bank (1kB page size)
    unsigned int	flags:4;	// reserved for flags
};

#define MM_PAGE_ACCESS_RW	1
#define MM_PAGE_ACCESS_RO	0

struct mm_manager_s {
    uint8_t		current_page;
    uint8_t		current_bank;
    uint8_t		num_pages;
    struct mm_page_s	*pages;
};

extern struct mm_manager_s mm_manager_zx128;

// initializes heap and memory manager
void init_memory(void);

// copies the given page from source bank into LOWMEM buffer
void mm_page_in( uint8_t page_no );

// copies the currently mapped page from LOWMEM back into its source bank
// only if it's a RW mapping
void mm_page_out( void );

#endif // _MEMORY_H

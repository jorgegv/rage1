////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _SUB_H
#define _SUB_H

#include <stdint.h>

// Single Use Blob (SUB) data definitions (see doc/SINGLE-USE-BLOBS.md)

// SUB types
#define SUB_TYPE_DSBUF		0
#define SUB_TYPE_SP1BUF		1

struct sub_s {
    uint8_t type:2;
    uint8_t needs_swap:1;
    uint16_t size;
    void ( *load_address )( void );
    void ( *execute_address )( void );
};

// these two are generated externally in an ASM file
extern uint8_t num_subs;
extern struct sub_s sub_info[];

void subs_load( void );
void subs_run( void );

#endif // _SUB_H

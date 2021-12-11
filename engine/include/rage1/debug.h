////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _DEBUG_H
#define _DEBUG_H

#include <stdint.h>
#include <input.h>

#include "features.h"

void debug_out( char * );
void debug_waitkey( void );
void debug_flush( void );

// debug panic will store the given panic code at fixed address $FFFF
// and then will halt the machine with a fancy color screen. You will
// then be able to launch the debugger and examine memory to get the
// panic cause. Panic codes must be defined below.
void debug_panic( uint8_t code );

char *itohex( uint16_t );
char *i8toa( uint8_t i );

extern uint16_t debug_flags;
#define GET_DEBUG_FLAG(f)	( debug_flags & (f) )
#define SET_DEBUG_FLAG(f)	( debug_flags |= (f) )
#define RESET_DEBUG_FLAG(f)	( debug_flags &= ~(f) )

#ifdef RAGE1_DEBUG
    #define DEBUG_ASSERT(a,b)	do { if ( !(a) ) debug_panic((b)); } while (0)
#else
    #define DEBUG_ASSERT(a,b)
#endif

// DEBUG_PANIC codes
#define PANIC_GENERIC		0x40
#define PANIC_SPRITE_IS_NULL	0x41

#endif // _DEBUG_H

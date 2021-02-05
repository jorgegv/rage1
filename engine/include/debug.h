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

void debug_out( char * );
void debug_waitkey(void);
void debug_flush(void);

char *itohex( uint16_t );
char *i8toa( uint8_t i );

extern uint16_t debug_flags;
#define debug_set_flag(f)	( debug_flags |= (f) )
#define debug_reset_flag(f)       ( debug_flags &= ~(f) )

#endif // _DEBUG_H

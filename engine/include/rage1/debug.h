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
#define PANIC_GENERIC					0xF0
#define PANIC_SPRITE_IS_NULL				0x40
#define PANIC_DATASET_INVALID_PREVIOUS_BANK		0x50
#define PANIC_DATASET_ACTIVATE_INVALID			0x51
#define PANIC_DATASET_INVALID_NEW_BANK			0x52
#define PANIC_CODESET_INVALID_PREVIOUS_BANK		0x60
#define PANIC_CODESET_INVALID_FUNCTION			0x61
#define PANIC_CODESET_INVALID_NEW_BANK			0x62
#define PANIC_CODESET_INVALID_FUNCTION_POINTER		0x63
#define PANIC_HERO_DRAW_INVALID_X			0x70
#define PANIC_HERO_DRAW_INVALID_XMAX			0x71
#define PANIC_HERO_DRAW_INVALID_Y			0x72
#define PANIC_HERO_DRAW_INVALID_YMAX			0x73

#endif // _DEBUG_H

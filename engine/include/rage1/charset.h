////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _CHARSET_H
#define _CHARSET_H

#include <stdint.h>

#ifdef BUILD_FEATURE_CUSTOM_CHARSET

// pointer to custom character set
extern uint8_t custom_charset[];

// custom character set initialization function
void init_custom_charset( void );

#endif	// BUILD_FEATURE_CUSTOM_CHARSET

#endif	// _CHARSET_H

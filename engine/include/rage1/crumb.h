////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _CRUMB_H
#define _CRUMB_H

#include <stdint.h>

#include "features.h"

struct crumb_info_s {
    uint8_t	btile_num;
    uint16_t	counter;
    void	(*do_action)( struct crumb_info_s *c );
};

struct crumb_location_s {
    uint8_t	crumb_type;
    uint8_t	row,col;
    uint8_t	state_index;	// index into the screen asset state table
}

// crumb flags macros and definitions
#define GET_CRUMB_FLAG(s,f)	( (s) & (f) )
#define SET_CRUMB_FLAG(s,f)	( (s) |= (f) )
#define RESET_CRUMB_FLAG(s,f)	( (s) &= ~(f) )

#define F_CRUMB_ACTIVE	0x0001

#define IS_CRUMB_ACTIVE(i)	( GET_CRUMB_FLAG( ( i ), F_CRUMB_ACTIVE ) )

extern struct crumb_info_s all_crumb_types[];

void crumb_was_grabbed ( uint8_t type );
void crumb_reset_all( void );

#endif // _CRUMB_H

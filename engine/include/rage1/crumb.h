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
    void	(*do_action)(void);
};

extern struct crumb_info_s all_crumbs[];

void crumb_was_grabbed ( uint8_t type );
void crumb_reset_all( void );

#endif // _CRUMB_H

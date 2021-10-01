////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _TYPES_H
#define _TYPES_H

#include <stdint.h>

#include "features.h"

struct position_data_s {
    uint8_t x,y;	// position top, left
    uint8_t xmax,ymax;	// position bottom,right
};

#endif // _TYPES_H

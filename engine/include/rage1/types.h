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

// FFP (Fractional Fixed Point) type definitions
typedef union {
    struct {
        uint8_t fraction;	// low byte, fractional part
        uint8_t integer;	// high byte, integer part
    } part;
    uint16_t value;		// ffp as 16-bit little endian
} ffp16_t;

struct position_data_s {
    ffp16_t x,y;
    uint8_t xmax,ymax;	// position bottom,right
};

#endif // _TYPES_H

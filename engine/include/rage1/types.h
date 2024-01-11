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
    union {
        struct {
            uint8_t x_frac;	// x pos, with optional fractional part
            uint8_t x_int;
            uint8_t y_frac;	// y pos, with optional fractional part
            uint8_t y_int;
        } u8;
        struct {
            uint16_t x;		// x pos, as 16-bit fixed-point (8+8)
            uint16_t y;		// y pos, as 16-bit fixed-point (8+8)
        } u16;
    } coords;
    uint8_t xmax,ymax;	// position bottom,right
};

#endif // _TYPES_H

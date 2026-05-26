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
//
// Phase G4 Risk R3 (gfx.md §G4-3, "trickiest semantic ripple"):
// `ffp16_t` is a deliberate union of (uint8_t fraction, uint8_t integer) and
// a uint16_t `value` field, giving 8.8 fixed-point with packed access.  On a
// CPC / ZX Next Layer-2 backend the integer part needs 16 bits (320- or
// 640-pixel horizontal range), which would push `value` to 24 bits and
// break every callsite that does fixed-point arithmetic through
// `position.x.value` (multiplications by 256, comparisons against
// HERO_MOVE_X{MIN,MAX} * 256, etc.).
//
// Decision: keep `ffp16_t` and `position_data_s` unchanged on ZX.  The CPC /
// Layer-2 bring-up (Phase G7+) will add a *parallel* `position16_t` /
// `ffp24_t` struct used only on backends where `gfx_xpos_t == uint16_t`.
// Engine code paths that consume the integer part continue to use
// `position.x.part.integer` (uint8_t on ZX); paths that take a generic
// pixel coordinate as an HAL argument use `gfx_xpos_t` / `gfx_ypos_t`
// (which is `uint8_t` on ZX so still compiles unchanged here).
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

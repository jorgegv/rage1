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

// Wide-coordinate platform detection (Phase G8a).
//
// On the CPC (mode-1 is 320 px / 40 cols wide) the gfx pixel-coordinate type
// `gfx_xpos_t`/`gfx_ypos_t` is `uint16_t` (Phase G4/R4), but the engine's
// sprite/hero/enemy fixed-point POSITION integer part was still `uint8_t`, so
// a sprite could never be placed at x>255 — the right ~64 px were unreachable.
// G8a widens the POSITION integer part to 16 bits on CPC, mirroring the same
// per-platform-typedef pattern G4 used for the gfx coords.  ZX is untouched
// (byte-identical: the integer part and `value` keep their historical widths).
#if defined( BUILD_FEATURE_PLATFORM_CPC464 ) || \
    defined( BUILD_FEATURE_PLATFORM_CPC6128 ) || \
    defined( BUILD_FEATURE_PLATFORM_CPC_FLAT ) || \
    defined( BUILD_FEATURE_PLATFORM_CPC_BANKED )
#define RAGE1_FEATURE_WIDE_POSITION_COORDS	1
#endif

// FFP (Fractional Fixed Point) type definitions
//
// Phase G4 Risk R3 (gfx.md §G4-3, "trickiest semantic ripple"):
// `ffp16_t` is a deliberate union of (uint8_t fraction, uint8_t integer) and
// a uint16_t `value` field, giving 8.8 fixed-point with packed access.  Engine
// code does fixed-point arithmetic through `position.x.value` (multiplications
// by 256, comparisons against HERO_MOVE_X{MIN,MAX} * 256, etc.) and reads the
// integer part through `position.x.part.integer`.
//
// G8a per-platform widening:
//   - ZX (default): integer part `uint8_t`, `value` `uint16_t` — UNCHANGED,
//     so ZX codegen is byte-identical.
//   - CPC (RAGE1_FEATURE_WIDE_POSITION_COORDS): integer part `uint16_t` so a
//     sprite can be placed at x in [0,319]; `value` widened to `uint32_t` so
//     the packed 8.8 -> 16.8 fixed-point math (`* 256`, `/ 256`, `value`
//     comparisons) still holds with no overflow.  Little-endian layout keeps
//     `value == 256*integer + fraction` on both platforms, so all the existing
//     `position.x.value` arithmetic stays correct under the wider type.
//
// `pos_int_t` is the integer-part / bounds type (xmax, ymax, hotzone & enemy
// bounce limits) so those widen in lock-step with the coordinate range.

#ifdef RAGE1_FEATURE_WIDE_POSITION_COORDS

typedef uint16_t pos_int_t;	// position integer part / screen-pixel bound
typedef uint32_t ffp_value_t;	// packed fixed-point value (16.8, 24 bits used)

typedef union {
    struct {
        uint8_t  fraction;	// low byte, fractional part
        uint16_t integer;	// integer part (16-bit: CPC 0..319)
    } part;
    ffp_value_t value;		// ffp as 24-bit usable value (little endian)
} ffp16_t;

#else

typedef uint8_t pos_int_t;	// position integer part / screen-pixel bound
typedef uint16_t ffp_value_t;	// packed fixed-point value (8.8)

typedef union {
    struct {
        uint8_t fraction;	// low byte, fractional part
        uint8_t integer;	// high byte, integer part
    } part;
    ffp_value_t value;		// ffp as 16-bit little endian
} ffp16_t;

#endif // RAGE1_FEATURE_WIDE_POSITION_COORDS

struct position_data_s {
    ffp16_t x,y;
    pos_int_t xmax,ymax;	// position bottom,right
};

// Scale an integer pixel coordinate to a packed fixed-point value (<< 8).
//
// On z88dk `int` is 16 bits, so the historical ZX idiom `256 * pixel` computes
// in 16-bit and is correct only because the result is masked to the 16-bit
// `value`.  On CPC a pixel can be up to 319, so `256 * 312` (= 79872) must NOT
// truncate to 16 bits: we force the product into the 32-bit `ffp_value_t`.
//
// ZX MUST keep the EXACT original `( 256 * (px) )` expression so codegen is
// byte-identical (the (uint32_t) cast variant changed SDCC's 16-bit codegen —
// verified via main.map drift).  Only CPC takes the widened form.
#ifdef RAGE1_FEATURE_WIDE_POSITION_COORDS
#define FFP_FROM_PIXEL(px)	( (ffp_value_t)(px) * 256 )
#else
#define FFP_FROM_PIXEL(px)	( 256 * (px) )
#endif

#endif // _TYPES_H

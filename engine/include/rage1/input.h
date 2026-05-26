////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _RAGE1_INPUT_H
#define _RAGE1_INPUT_H

// Cross-platform input HAL surface (Phase IN2 of the multiplatform plan).
//
// At this stage the header is additive: it provides the new
// INPUT_STATE_* state-bit constants and HAL prototypes, but the engine
// continues to use the z88dk <input.h> entry points directly. Phase IN3
// will route the engine call sites through this HAL.

#include <stdint.h>

#include "features.h"

////////////////////////////////////////////////////////////////////////////////
//
// Cross-platform input state bits (returned by joystick/keyboard readers).
//
// Values are identical-valued on every backend by design: this is the
// byte-packing convention shared across the HAL, see input.md §3.1.
// The ZX values below match z88dk's IN_STICK_* bit-for-bit so existing
// engine code keeps producing byte-identical output during the rename.
//
////////////////////////////////////////////////////////////////////////////////

#define INPUT_STATE_UP      0x01
#define INPUT_STATE_DOWN    0x02
#define INPUT_STATE_LEFT    0x04
#define INPUT_STATE_RIGHT   0x08
#define INPUT_STATE_FIRE    0x80
#define INPUT_STATE_FIRE_2  0x40
#define INPUT_STATE_FIRE_3  0x20
#define INPUT_STATE_NONE    0x00
#define INPUT_STATE_DIRS    ( INPUT_STATE_UP   | INPUT_STATE_DOWN | \
                              INPUT_STATE_LEFT | INPUT_STATE_RIGHT )

////////////////////////////////////////////////////////////////////////////////
//
// HAL type aliases.
//
////////////////////////////////////////////////////////////////////////////////

typedef uint8_t  input_state_t;     // packed INPUT_STATE_* bits
typedef uint16_t input_scancode_t;  // backend-defined encoding

////////////////////////////////////////////////////////////////////////////////
//
// HAL prototypes (Phase IN3 will provide the bodies; declared here so
// engine call sites can be migrated incrementally without re-touching
// this header). These are declared BEFORE the backend wrapper is
// included so the per-backend macro definitions in input_zx.h /
// input_cpc.h do not collide with the prototypes here.
//
// `controller_type` matches the `type` field of
// `struct controller_info_s` from rage1/controller.h.
//
////////////////////////////////////////////////////////////////////////////////

// Read the current state of a controller (joystick/keyboard) and write
// the packed INPUT_STATE_* bits into *out_state.
void input_state_read( uint8_t controller_type, uint8_t *out_state );

// Non-blocking: is the key with the given backend scancode pressed
// right now?
uint8_t input_key_pressed( uint16_t scancode );

// Blocking: wait until any key is pressed / until no key is pressed.
void input_wait_key( void );
void input_wait_nokey( void );

////////////////////////////////////////////////////////////////////////////////
//
// Per-backend wrapper headers. ZX is the only backend at IN2; the
// wrapper supplies the INPUT_SCANCODE_* / KBD_DEFAULT_* constants and
// the macros that map input_* -> in_* z88dk entry points.
//
////////////////////////////////////////////////////////////////////////////////

#if defined( BUILD_FEATURE_PLATFORM_ZX48 ) || defined( BUILD_FEATURE_PLATFORM_ZX128 )
#include "rage1/input_zx.h"
#endif

#endif // _RAGE1_INPUT_H

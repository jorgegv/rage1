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

// The user-defined-keys struct used by keyboard-as-joystick mode is
// fully defined by each backend wrapper (rage1/input_zx.h /
// rage1/input_cpc.h). Engine code holds it by value (as a field of
// `struct controller_info_s`) and reads its `up/down/left/right/fire`
// fields. The forward declaration here lets `input_state_read()` carry
// an `input_udk_t *` in its prototype without input.h needing to know
// the backend struct layout.
struct input_udk_s;
typedef struct input_udk_s input_udk_t;

////////////////////////////////////////////////////////////////////////////////
//
// HAL prototypes (the bodies live in engine/src/input.c; on ZX the
// macros defined in rage1/input_zx.h below replace most of them with
// thin wrappers over z88dk's <input.h> entry points, so the prototypes
// here describe the cross-platform contract but only `input_state_read`
// turns into a real function call on ZX).
//
// These are declared BEFORE the backend wrapper is included so the
// per-backend function-like macros in rage1/input_zx.h /
// rage1/input_cpc.h substitute the call sites without clobbering the
// prototype tokens here.
//
////////////////////////////////////////////////////////////////////////////////

// Read the current state of a controller (joystick/keyboard) and
// return it as packed INPUT_STATE_* bits. `type` is one of the
// CTRL_TYPE_* values (see rage1/controller.h); `udk` is the
// user-defined-keys struct, used only for CTRL_TYPE_KEYBOARD; backends
// ignore the `udk` argument for joystick types.
input_state_t input_state_read( uint8_t type, input_udk_t *udk );

// Non-blocking: is the key with the given backend scancode pressed
// right now? (ZX: macro that calls in_key_pressed; CPC: macro that
// reads cpct_keyboardStatusBuffer.)
uint8_t input_key_pressed( input_scancode_t scancode );

// Blocking: wait until any key is pressed / until no key is pressed.
// On ZX both are macros that resolve to in_wait_key / in_wait_nokey.
void input_wait_key( void );
void input_wait_nokey( void );

// Per-frame keyboard-state refresh. On ZX this is a no-op macro
// (z88dk's in_stick_* read the port synchronously every call); on CPC
// it must call cpct_scanKeyboard() to refresh the status buffer
// before any input_state_read / input_key_pressed call. Engine calls
// this once at the start of check_controller(), so the per-frame
// scan-point is in place even on backends that do not need it.
void input_scan( void );

// ASCII -> backend scancode lookup, used by init_controllers() and by
// per-game key-redefine flows so they do not reference IN_KEY_SCANCODE_*
// (ZX) or cpct_keyID (CPC) directly. ZX: macro for in_key_scancode.
input_scancode_t input_lookup_key( uint8_t ascii );

// Blocking raw keyboard scan: spin until exactly one key is pressed,
// then return its backend scancode in the form expected by the
// keyboard-as-joystick reader (ZX: a krepress scancode, i.e. the same
// encoding stored in controller_info_s.keys.* / struct input_udk_s).
// Used by per-game key-redefine ("Redefine keys") menu flows. On ZX
// this is a real function (engine/src/input.c) that scans the keyboard
// matrix directly; CPC will implement it via cpctelera later. Unlike
// input_lookup_key() (ASCII -> scancode), this reads the physical
// keyboard and blocks until a key is detected.
input_scancode_t input_capture_scancode( void ) __z88dk_fastcall;

////////////////////////////////////////////////////////////////////////////////
//
// Per-backend wrapper headers. ZX is the only backend at IN3; the
// wrapper supplies the INPUT_SCANCODE_* / KBD_DEFAULT_* constants, the
// `struct input_udk_s` layout, and the macros that map input_* ->
// in_* z88dk entry points.
//
////////////////////////////////////////////////////////////////////////////////

#if defined( BUILD_FEATURE_PLATFORM_ZX48 ) || defined( BUILD_FEATURE_PLATFORM_ZX128 )
#include "rage1/input_zx.h"
#endif

#endif // _RAGE1_INPUT_H

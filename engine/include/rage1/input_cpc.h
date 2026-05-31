////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

//
// Amstrad CPC backend for the cross-platform input HAL — STUB (Phase IN5).
//
// This is the CPC analogue of rage1/input_zx.h.  It supplies the full input
// HAL contract that the engine needs to compile under +cpc: the backend
// `struct input_udk_s` layout, the INPUT_SCANCODE_* / KBD_DEFAULT_* constants,
// and the input_* macro family.
//
// At Phase IN5 this is a STUB — there is NO real CPC keyboard reading yet.
// The macros below either resolve to harmless no-ops/zero or are intentionally
// left undefined so the engine call sites bind to the real (but stubbed)
// function bodies in engine/src/input.c (guarded by
// BUILD_FEATURE_INPUT_BACKEND_CPC).  Phase IN6 replaces the macro bodies and
// the input.c bodies with cpctelera-backed implementations
// (cpct_scanKeyboard / cpct_isKeyPressed / cpct_keyID ...); see input.md §3.2
// and Phase IN6.
//
// Backend split mirrors the documented CPC design (input.md §3.2):
//   - macros here (preprocessor, no input.c body):
//       input_scan(), input_test_key(), input_key_pressed()
//   - real functions in input.c (no native cpctelera macro equivalent):
//       input_state_read(), input_capture_scancode(), input_pause(),
//       input_wait_key(), input_wait_nokey(), input_inkey(),
//       input_lookup_key()
// This differs from the ZX backend, where wait/pause/inkey/lookup are thin
// macros over z88dk's <input.h> entry points.
//

#ifndef _RAGE1_INPUT_CPC_H
#define _RAGE1_INPUT_CPC_H

////////////////////////////////////////////////////////////////////////////////
// Backend `struct input_udk_s` definition.
//
// Same field order / scancode width as the ZX backend (input.md §3.2
// cross-platform field-order rationale).  On CPC the scancode encoding is a
// cpctelera keyID (low byte = matrix line, high byte = bit mask within that
// line); IN6 fills the real encoding in.  The layout is fixed here so the
// engine's by-value `input_udk_t keys` field (struct controller_info_s) is a
// complete type.
////////////////////////////////////////////////////////////////////////////////

struct input_udk_s {
    input_scancode_t fire;
    input_scancode_t right;
    input_scancode_t left;
    input_scancode_t down;
    input_scancode_t up;
};

////////////////////////////////////////////////////////////////////////////////
// CPC controller-type constants.
//
// CTRL_TYPE_UNDEFINED / CTRL_TYPE_KEYBOARD live in rage1/controller.h (shared,
// platform-independent).  The CPC joystick types JOY0 / JOY1 occupy the next
// free contiguous slots (4, 5) after the ZX joystick types (KEMPSTON=2,
// SINCLAIR1=3), so input_state_read() can dispatch on a single contiguous
// CTRL_TYPE_* range on both backends (input.md §3.3, IN6-3).  These are stub
// placeholders at IN5; IN6 wires the cpctelera reads.
////////////////////////////////////////////////////////////////////////////////

#define CTRL_TYPE_JOY0  4
#define CTRL_TYPE_JOY1  5

////////////////////////////////////////////////////////////////////////////////
// Backend scancode / default-key constants.
//
// Placeholder values at IN5 (real cpctelera keyIDs — Key_Y, Joy0_Up, ... —
// land in IN6, see input.md §3.2 and Q3 for the pause-key decision).
//
// KBD_DEFAULT_* are platform-portable ASCII defaults (same chars as ZX) fed
// through input_lookup_key() by init_controllers(); the lookup is a stub at
// IN5 so they currently translate to scancode 0.
////////////////////////////////////////////////////////////////////////////////

#define INPUT_SCANCODE_PAUSE          0

#define INPUT_SCANCODE_DEFAULT_UP     0
#define INPUT_SCANCODE_DEFAULT_DOWN   0
#define INPUT_SCANCODE_DEFAULT_LEFT   0
#define INPUT_SCANCODE_DEFAULT_RIGHT  0
#define INPUT_SCANCODE_DEFAULT_FIRE   0

#define KBD_DEFAULT_UP                'Q'
#define KBD_DEFAULT_DOWN              'A'
#define KBD_DEFAULT_LEFT              'O'
#define KBD_DEFAULT_RIGHT             'P'
#define KBD_DEFAULT_FIRE              ' '

////////////////////////////////////////////////////////////////////////////////
// HAL macro family (preprocessor-resolved entry points).
//
// At IN5 these are no-op / zero stubs.  IN6 points them at the real cpctelera
// symbols (cpct_scanKeyboard_if / cpct_isAnyKeyPressed_f / cpct_isKeyPressed).
//
// input_state_read(), input_capture_scancode(), input_pause(),
// input_wait_key(), input_wait_nokey(), input_inkey() and input_lookup_key()
// are real functions (prototypes in input.h / below, stub bodies in input.c)
// and are intentionally NOT defined here as macros.
////////////////////////////////////////////////////////////////////////////////

// Per-frame keyboard refresh. ZX is a no-op; on CPC this becomes
// cpct_scanKeyboard_if() at IN6. No-op stub at IN5.
#define input_scan()                  ( (void) 0 )

// "Is any key currently pressed?" -> cpct_isAnyKeyPressed_f() at IN6.
#define input_test_key()              ( (uint8_t) 0 )

// Single-key query by backend scancode -> cpct_isKeyPressed( sc ) at IN6.
#define input_key_pressed( sc )       ( (void)(sc), (uint8_t) 0 )

////////////////////////////////////////////////////////////////////////////////
// Prototypes for the CPC-specific HAL functions that are macros on ZX but
// real function bodies on CPC (input.md §3.2).  input.h already declares
// input_state_read / input_capture_scancode / input_wait_key /
// input_wait_nokey / input_lookup_key (the cross-platform contract), so only
// the CPC-only ones are declared here.
////////////////////////////////////////////////////////////////////////////////

// Busy-wait `ms` milliseconds, early-out on keypress, return remaining ms.
// ZX resolves this to z88dk's in_pause() via a macro; CPC needs a real loop
// (cpct_scanKeyboard_f + cpct_isAnyKeyPressed_f) at IN6. Stub at IN5.
uint16_t input_pause( uint16_t ms );

// ASCII of the single key currently down (0 if none/ambiguous). ZX -> macro
// over z88dk's in_inkey(); CPC needs a buffer walk + ASCII table at IN6.
uint16_t input_inkey( void );

#endif // _RAGE1_INPUT_CPC_H

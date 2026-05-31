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
// Amstrad CPC backend for the cross-platform input HAL — STUB (Phase G7).
//
// The CPC input HAL proper is Phase IN5 (input.md), not G7.  But compiling
// the WHOLE engine under +cpc for the G7 gfx-stub compile-test surfaces the
// input HAL gap: input.h only includes input_zx.h on ZX, so on CPC
// `struct input_udk_s` stays an incomplete forward declaration and
// `struct controller_info_s { ... input_udk_t keys; }` fails to compile
// ("field 'keys' has incomplete type").
//
// This header provides the MINIMUM needed for the engine to TYPE-CHECK
// under +cpc: the backend struct layout, the KBD_DEFAULT_* / INPUT_SCANCODE_*
// constants, and no-op / placeholder macro wrappers for the input_* entry
// points used by engine sources.  It is a STUB — no real CPC keyboard
// reading.  IN5 replaces these bodies with cpctelera-backed implementations
// (cpct_scanKeyboard / cpct_isKeyPressed / cpct_keyID ...).
//
// input_state_read() and input_capture_scancode() stay real prototypes
// (declared in input.h); their CPC bodies land in IN5, so at G7 the
// compile-test does not attempt to link them (linkage may fail — acceptable).
//

#ifndef _RAGE1_INPUT_CPC_H
#define _RAGE1_INPUT_CPC_H

////////////////////////////////////////////////////////////////////////////////
// Backend `struct input_udk_s` definition.
//
// Same field order / scancode width as the ZX backend (input.md §3.2
// cross-platform field-order rationale).  On CPC the scancode encoding is a
// cpctelera keyID (filled in at IN5); the layout is fixed here so the engine's
// by-value `input_udk_t keys` field is a complete type.
////////////////////////////////////////////////////////////////////////////////

struct input_udk_s {
    input_scancode_t fire;
    input_scancode_t right;
    input_scancode_t left;
    input_scancode_t down;
    input_scancode_t up;
};

////////////////////////////////////////////////////////////////////////////////
// Backend scancode / default-key constants.
//
// Placeholder values at G7 (real cpctelera keyIDs land in IN5).  KBD_DEFAULT_*
// are platform-portable ASCII defaults (same chars as ZX) fed through
// input_lookup_key() by init_controllers().
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
// HAL macro stubs (no real CPC keyboard at G7; IN5 wires cpctelera).
//
// input_state_read() and input_capture_scancode() are real functions (declared
// in input.h, bodies in IN5) and are intentionally NOT defined here.
////////////////////////////////////////////////////////////////////////////////

#define input_scan()                  ( (void) 0 )
#define input_wait_key()              ( (void) 0 )
#define input_wait_nokey()            ( (void) 0 )
#define input_key_pressed( sc )       ( (void)(sc), (uint8_t) 0 )
#define input_lookup_key( c )         ( (input_scancode_t)(c) )

#endif // _RAGE1_INPUT_CPC_H

////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _RAGE1_INPUT_ZX_H
#define _RAGE1_INPUT_ZX_H

// ZX Spectrum backend for the cross-platform input HAL.
//
// This is a thin wrapper around z88dk's <input.h>: every input_*
// HAL macro resolves to the corresponding in_* z88dk entry point at
// preprocessing time, so the generated code is identical to a direct
// z88dk call. See input.md §3.2 for the rationale.

#include <input.h>

////////////////////////////////////////////////////////////////////////////////
//
// Backend `struct input_udk_s` definition.
//
// The user-defined-keys struct used by keyboard-as-joystick mode. On
// ZX the layout matches z88dk's `struct udk_s` exactly (same field
// order, same uint16_t scancode width) so input.c can pass an
// `input_udk_t *` straight to z88dk's `in_stick_keyboard` via a single
// pointer cast. Game and engine code only see the HAL alias name.
// See input.md §3.2 for the cross-platform field-order rationale.
//
////////////////////////////////////////////////////////////////////////////////

struct input_udk_s {
    input_scancode_t fire;
    input_scancode_t right;
    input_scancode_t left;
    input_scancode_t down;
    input_scancode_t up;
};

////////////////////////////////////////////////////////////////////////////////
//
// Backend scancode / default-key constants (see input.md §3.4).
//
// INPUT_SCANCODE_PAUSE        -- the engine's "pause" key on ZX.
// INPUT_SCANCODE_DEFAULT_*    -- legacy ZX-scancode defaults, kept for
//                                ZX-only callers that have not yet been
//                                migrated to the platform-portable
//                                KBD_DEFAULT_* (ASCII) form.
// KBD_DEFAULT_*               -- platform-portable ASCII defaults that
//                                Phase IN3 will feed through
//                                input_lookup_key().
//
////////////////////////////////////////////////////////////////////////////////

#define INPUT_SCANCODE_PAUSE          IN_KEY_SCANCODE_y

#define INPUT_SCANCODE_DEFAULT_UP     IN_KEY_SCANCODE_q
#define INPUT_SCANCODE_DEFAULT_DOWN   IN_KEY_SCANCODE_a
#define INPUT_SCANCODE_DEFAULT_LEFT   IN_KEY_SCANCODE_o
#define INPUT_SCANCODE_DEFAULT_RIGHT  IN_KEY_SCANCODE_p
#define INPUT_SCANCODE_DEFAULT_FIRE   IN_KEY_SCANCODE_SPACE

// Lowercase letters: z88dk's in_key_scancode() (input_lookup_key on ZX)
// resolves an UPPERCASE letter through the CAPS-SHIFTed block of its
// key-translation table, yielding a scancode that requires CAPS SHIFT to
// be held — so 'Q'/'A'/'O'/'P' would only register as movement with CAPS
// SHIFT down. The unshifted (plain-keypress) scancodes are produced by the
// lowercase chars, matching the legacy INPUT_SCANCODE_DEFAULT_* (q/a/o/p).
#define KBD_DEFAULT_UP                'q'
#define KBD_DEFAULT_DOWN              'a'
#define KBD_DEFAULT_LEFT              'o'
#define KBD_DEFAULT_RIGHT             'p'
#define KBD_DEFAULT_FIRE              ' '

////////////////////////////////////////////////////////////////////////////////
//
// HAL macros that resolve to z88dk entry points (preprocessor-only, no
// runtime cost). input_state_read() is a real function (provided in
// Phase IN3) and is intentionally NOT defined here.
//
////////////////////////////////////////////////////////////////////////////////

#define input_scan()                  ( (void) 0 )
#define input_wait_key()              in_wait_key()
#define input_wait_nokey()            in_wait_nokey()
#define input_test_key()              in_test_key()
#define input_pause( ms )             in_pause( (ms) )
#define input_inkey()                 in_inkey()
#define input_key_pressed( sc )       in_key_pressed( (sc) )
#define input_lookup_key( c )         in_key_scancode( (c) )

#endif // _RAGE1_INPUT_ZX_H

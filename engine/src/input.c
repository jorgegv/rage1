////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

// engine/src/input.c
//
// Cross-platform input HAL bodies (Phase IN3 of the multiplatform
// plan; see doc/multiplatform-plan/input.md §3 and §5 phase IN3).
//
// On ZX the vast majority of the HAL is provided as preprocessor
// macros by rage1/input_zx.h (preprocessor-resolved wrappers over
// z88dk's <input.h> entry points), so they cost zero extra
// instructions vs the pre-HAL engine. The only real function bodies
// that live here are the ones whose CPC counterpart will not be a
// macro:
//
//   - input_state_read() — dispatch over controller type (KEYBOARD /
//     KEMPSTON / SINCLAIR1 on ZX; KEYBOARD / JOY0 / JOY1 on CPC).
//
// The IN3-5 grep-guard explicitly allowlists this file alongside
// rage1/input_zx.h as a HAL implementation site where legacy z88dk
// input symbols (in_*, IN_*, udk_s, ...) are permitted to appear.

#include "features.h"

#include "rage1/input.h"
#include "rage1/controller.h"   // CTRL_TYPE_* constants

#if defined( BUILD_FEATURE_PLATFORM_ZX48 ) || defined( BUILD_FEATURE_PLATFORM_ZX128 )

////////////////////////////////////////////////////////////////////////////////
//
// ZX backend
//
// `struct input_udk_s` (rage1/input_zx.h) has the same field order
// and width as z88dk's `struct udk_s`, so we cast the pointer through
// rather than copy fields.
//
////////////////////////////////////////////////////////////////////////////////

input_state_t input_state_read( uint8_t type, input_udk_t *udk ) {
    switch ( type ) {
        case CTRL_TYPE_KEYBOARD:   return in_stick_keyboard( (struct udk_s *) udk );
        case CTRL_TYPE_KEMPSTON:   return in_stick_kempston();
        case CTRL_TYPE_SINCLAIR1:  return in_stick_sinclair1();
    }
    return INPUT_STATE_NONE;
}

#endif // ZX48 || ZX128

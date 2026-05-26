////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _CONTROLLER_H
#define _CONTROLLER_H

#include <stdint.h>

#include "features.h"
#include "rage1/input.h"

struct controller_info_s {
    // controller type, see below
    uint8_t type;
    // controller keys (HAL-typed; backend-defined layout, see rage1/input_zx.h)
    input_udk_t keys;
    // controller state
    uint8_t state;
};

// Keyboard controller settings.
//
// The default-key values are ASCII characters (KBD_DEFAULT_* — defined
// by the per-backend HAL header, e.g. rage1/input_zx.h). The legacy
// KBD_UP/KBD_DOWN/... aliases (kept as silent aliases per the
// backwards-compat policy in README §5.6) now point at the
// platform-portable ASCII chars instead of z88dk's IN_KEY_SCANCODE_*
// directly; init_controllers() runs input_lookup_key() on each value
// at boot to convert ASCII -> backend scancode.
#define KBD_UP			KBD_DEFAULT_UP
#define KBD_DOWN		KBD_DEFAULT_DOWN
#define KBD_LEFT		KBD_DEFAULT_LEFT
#define KBD_RIGHT		KBD_DEFAULT_RIGHT
#define KBD_FIRE		KBD_DEFAULT_FIRE

// controller types
#define CTRL_TYPE_UNDEFINED	0
#define CTRL_TYPE_KEYBOARD	1
#define CTRL_TYPE_KEMPSTON	2
#define CTRL_TYPE_SINCLAIR1	3

void init_controllers(void);
uint8_t controller_read_state(void);
uint8_t controller_pause_key_pressed(void);
void controller_reset_all(void);

#endif // _CONTROLLER_H

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

#include <input.h>
#include <stdint.h>

#include "features.h"

struct controller_info_s {
    // controller type, see below
    uint8_t type;

    // controller keys
    struct in_UDK keys;
    uint16_t pause_key;

    // controller state
    uint8_t state;
};

// Keyboard controller settings
#define KBD_UP			(in_LookupKey('q'))
#define KBD_DOWN		(in_LookupKey('a'))
#define KBD_LEFT		(in_LookupKey('o'))
#define KBD_RIGHT		(in_LookupKey('p'))
#define KBD_FIRE		(in_LookupKey(' '))
#define KBD_PAUSE		(in_LookupKey('y'))

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

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

#if defined( BUILD_FEATURE_INPUT_BACKEND_ZX )

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

////////////////////////////////////////////////////////////////////////////////
//
// input_capture_scancode() — blocking raw keyboard scan for key-redefine
// flows. Lifted verbatim from the former per-game games/default/game_src/
// kbd.c (Phase IN4). The inline-asm semantics are byte-identical to that
// helper: it spins over all 8 keyboard-matrix rows until exactly one key
// is pressed, then returns the krepress scancode in HL.
//
////////////////////////////////////////////////////////////////////////////////

// ports for all kbd rows
static uint8_t kbd_row_ports[] = { 0xf7,0xfd,0xfb,0xfe,0xef,0xdf,0xbf,0x7f };

input_scancode_t input_capture_scancode( void ) __z88dk_fastcall __naked {
__asm

    ; we scan all rows repeatedly
check_loop:
    ld hl,_kbd_row_ports
    ld b,8
check_row:
    ld a,(hl)
    in a,(0xfe)
    and 0x1f
    cp 0x1f			; key is pressed if bit = 0
    jr nz,got_key
    inc hl
    djnz check_row
    jr check_loop

    ; ...until one key is pressed
got_key:
    ld c,a			; C = key pressed

    ld a,8
    sub b			; A = index in row table ( 8 - counter )

    ld hl,_kbd_row_ports	; search the row port table
    ld b,a			; B = index in row table
search_loop:
    inc hl
    djnz search_loop
    ld l,(hl)			; L = row port value

    ld a,c			; negate the key press value
    cpl				; the library expects it
    and 0x1f
    ld h,a    			; H = key pressed

    ; return HL = krepress scancode
    ret

__endasm;
}

#endif // BUILD_FEATURE_INPUT_BACKEND_ZX

#if defined( BUILD_FEATURE_INPUT_BACKEND_CPC )

////////////////////////////////////////////////////////////////////////////////
//
// CPC backend (Phase IN6).
//
// Real cpctelera-backed bodies for the parts of the input HAL that are macros
// on ZX but must be functions on CPC (input.md §3.2).  They drive the
// hand-translated cpctelera keyboard primitives in
// engine/src/cpc/cpct_keyboard.asm (declared in rage1/input_cpc.h):
//   cpct_scanKeyboard() / cpct_scanKeyboard_f() — refill the 10-byte
//     cpct_keyboardStatusBuffer (0 = pressed, 1 = not pressed);
//   cpct_isKeyPressed( keyID ) — single-key query against the buffer;
//   cpct_isAnyKeyPressed_f()   — "any key down?".
//
// A cpct_keyID is (bit_mask << 8) | matrix_line: low byte = matrix line (0..9,
// index into the buffer), high byte = bit mask (one bit).  When we walk the
// buffer we rebuild a keyID as ( line | (mask << 8) ).
//
// `struct input_udk_s` (rage1/input_cpc.h) keeps the ZX field order
// (fire, right, left, down, up) so engine code that assigns keys.up / keys.fire
// stays source-compatible across both backends.
//
////////////////////////////////////////////////////////////////////////////////

// ASCII <-> cpct_keyID lookup table, shared by input_lookup_key() (ASCII ->
// keyID, used by init_controllers / key-redefine) and input_inkey() (keyID ->
// ASCII).  Only the characters RAGE1's defaults / menus need are mapped; any
// other key resolves to keyID 0 / ASCII 0.  keyID values come from cpctelera
// keyboard.h (mirrored as CPC_Key_* in rage1/input_cpc.h).
struct cpc_ascii_keyid_s {
    uint8_t          ascii;
    input_scancode_t keyid;
};

static const struct cpc_ascii_keyid_s cpc_ascii_keyid_table[] = {
    { 'Q', CPC_Key_Q     },
    { 'A', CPC_Key_A     },
    { 'O', CPC_Key_O     },
    { 'P', CPC_Key_P     },
    { ' ', CPC_Key_Space },
    { 'H', CPC_Key_H     },
    { 'Y', CPC_Key_Y     },
    { 'N', CPC_Key_N     },
    { '0', CPC_Key_0     },
    { 13,  CPC_Key_Return },
    { 27,  CPC_Key_Esc   },
};

#define CPC_ASCII_KEYID_TABLE_SIZE \
    ( sizeof( cpc_ascii_keyid_table ) / sizeof( cpc_ascii_keyid_table[0] ) )

// Read controller state -> packed INPUT_STATE_* bits.
// CTRL_TYPE_KEYBOARD ORs five cpct_isKeyPressed() calls over `udk`;
// CTRL_TYPE_JOY0 / CTRL_TYPE_JOY1 OR the Joy0_*/Joy1_* keyIDs.  input_scan()
// (cpct_scanKeyboard) is called once per frame by check_controller() before
// this, so the status buffer is already fresh.
input_state_t input_state_read( uint8_t type, input_udk_t *udk ) {
    input_state_t state = INPUT_STATE_NONE;

    switch ( type ) {
        case CTRL_TYPE_KEYBOARD:
            if ( cpct_isKeyPressed( udk->up    ) ) state |= INPUT_STATE_UP;
            if ( cpct_isKeyPressed( udk->down  ) ) state |= INPUT_STATE_DOWN;
            if ( cpct_isKeyPressed( udk->left  ) ) state |= INPUT_STATE_LEFT;
            if ( cpct_isKeyPressed( udk->right ) ) state |= INPUT_STATE_RIGHT;
            if ( cpct_isKeyPressed( udk->fire  ) ) state |= INPUT_STATE_FIRE;
            break;
        case CTRL_TYPE_JOY0:
            if ( cpct_isKeyPressed( CPC_Joy0_Up    ) ) state |= INPUT_STATE_UP;
            if ( cpct_isKeyPressed( CPC_Joy0_Down  ) ) state |= INPUT_STATE_DOWN;
            if ( cpct_isKeyPressed( CPC_Joy0_Left  ) ) state |= INPUT_STATE_LEFT;
            if ( cpct_isKeyPressed( CPC_Joy0_Right ) ) state |= INPUT_STATE_RIGHT;
            if ( cpct_isKeyPressed( CPC_Joy0_Fire1 ) ) state |= INPUT_STATE_FIRE;
            break;
        case CTRL_TYPE_JOY1:
            if ( cpct_isKeyPressed( CPC_Joy1_Up    ) ) state |= INPUT_STATE_UP;
            if ( cpct_isKeyPressed( CPC_Joy1_Down  ) ) state |= INPUT_STATE_DOWN;
            if ( cpct_isKeyPressed( CPC_Joy1_Left  ) ) state |= INPUT_STATE_LEFT;
            if ( cpct_isKeyPressed( CPC_Joy1_Right ) ) state |= INPUT_STATE_RIGHT;
            if ( cpct_isKeyPressed( CPC_Joy1_Fire1 ) ) state |= INPUT_STATE_FIRE;
            break;
    }
    return state;
}

// Walk the freshly-scanned status buffer for the first pressed key and return
// its cpct_keyID ( line | (mask << 8) ), or 0 if none is pressed.  Shared by
// input_capture_scancode() (blocking) and input_inkey() (non-blocking).
static input_scancode_t cpc_first_pressed_keyid( void ) {
    uint8_t line;
    for ( line = 0; line < 10; line++ ) {
        uint8_t status = cpct_keyboardStatusBuffer[ line ];
        if ( status != 0xFF ) {
            // at least one bit is 0 (pressed); find the lowest pressed bit
            uint8_t mask = 0x01;
            uint8_t b;
            for ( b = 0; b < 8; b++ ) {
                if ( ( status & mask ) == 0 )
                    return (input_scancode_t) ( line | ( (uint16_t) mask << 8 ) );
                mask <<= 1;
            }
        }
    }
    return (input_scancode_t) 0;
}

// Blocking raw keyboard scan for key-redefine flows: spin until exactly one
// key is detected, then return its cpct_keyID.  Mirrors the ZX
// input_capture_scancode() contract (returns the udk-storable scancode).
input_scancode_t input_capture_scancode( void ) __z88dk_fastcall {
    input_scancode_t keyid;
    do {
        cpct_scanKeyboard();
        keyid = cpc_first_pressed_keyid();
    } while ( keyid == 0 );
    return keyid;
}

// Busy-wait `ms` milliseconds, early-out on keypress, return remaining ms.
// The CPC runs at 4 MHz; the inner delay loop below is calibrated so the
// per-millisecond cost (scan + any-key poll + spin) is ~1 ms.  cpct_scanKeyboard
// is ~170 us, so we spend the remaining ~830 us in a tuned NOP spin.
uint16_t input_pause( uint16_t ms ) {
    while ( ms ) {
        volatile uint16_t spin;
        cpct_scanKeyboard_f();
        if ( cpct_isAnyKeyPressed_f() )
            break;                      // early-out: a key was pressed
        // ~830 us spin at 4 MHz (calibrated NOP loop)
        for ( spin = 0; spin < 360; spin++ )
            ;
        ms--;
    }
    return ms;
}

// Block until at least one key is pressed.
void input_wait_key( void ) {
    do {
        cpct_scanKeyboard_f();
    } while ( ! cpct_isAnyKeyPressed_f() );
}

// Block until no key is pressed.
void input_wait_nokey( void ) {
    do {
        cpct_scanKeyboard_f();
    } while ( cpct_isAnyKeyPressed_f() );
}

// ASCII of the single key currently down (0 if none / unmapped).  Walks the
// freshly-scanned buffer for the first pressed keyID, then reverse-maps it
// through the ASCII<->keyID table.
uint16_t input_inkey( void ) {
    input_scancode_t keyid;
    uint8_t i;

    cpct_scanKeyboard();
    keyid = cpc_first_pressed_keyid();
    if ( keyid == 0 )
        return 0;

    for ( i = 0; i < CPC_ASCII_KEYID_TABLE_SIZE; i++ )
        if ( cpc_ascii_keyid_table[ i ].keyid == keyid )
            return (uint16_t) cpc_ascii_keyid_table[ i ].ascii;
    return 0;
}

// ASCII -> backend scancode (cpct_keyID) for udk population / key-redefine.
// Returns 0 for any unmapped character.
input_scancode_t input_lookup_key( uint8_t ascii ) {
    uint8_t i;
    for ( i = 0; i < CPC_ASCII_KEYID_TABLE_SIZE; i++ )
        if ( cpc_ascii_keyid_table[ i ].ascii == ascii )
            return cpc_ascii_keyid_table[ i ].keyid;
    return (input_scancode_t) 0;
}

#endif // BUILD_FEATURE_INPUT_BACKEND_CPC

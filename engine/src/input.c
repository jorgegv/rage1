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
// CPC backend — STUB (Phase IN5).
//
// These are the real (but stubbed) bodies for the parts of the input HAL that
// are macros on ZX but must be functions on CPC (input.md §3.2): there is no
// native cpctelera one-liner for them, so they live here rather than in
// rage1/input_cpc.h.  At IN5 every body returns zero / does nothing — NO
// busy-waiting, NO real keyboard access.  Phase IN6 fills these in with
// cpctelera reads (cpct_scanKeyboard / cpct_isKeyPressed / cpct_keyID ...).
//
// `struct input_udk_s` (rage1/input_cpc.h) keeps the ZX field order
// (fire, right, left, down, up) so engine code that assigns keys.up / keys.fire
// stays source-compatible across both backends.
//
////////////////////////////////////////////////////////////////////////////////

// Read controller state -> packed INPUT_STATE_* bits.
// IN6: CTRL_TYPE_KEYBOARD ORs five cpct_isKeyPressed() calls over `udk`;
// CTRL_TYPE_JOY0 / CTRL_TYPE_JOY1 OR the Joy0_*/Joy1_* keyIDs.
input_state_t input_state_read( uint8_t type, input_udk_t *udk ) {
    (void) type;
    (void) udk;
    return INPUT_STATE_NONE;
}

// Blocking raw keyboard scan for key-redefine flows.
// IN6: cpct_scanKeyboard() + walk cpct_keyboardStatusBuffer[] for the first
// 0-bit, return (matrix_line | (bit_mask << 8)).
input_scancode_t input_capture_scancode( void ) __z88dk_fastcall {
    return (input_scancode_t) 0;
}

// Busy-wait `ms` ms, early-out on keypress, return remaining ms.
// IN6: poll cpct_scanKeyboard_f() + cpct_isAnyKeyPressed_f(), calibrated for
// 4 MHz.  Stub returns immediately (no busy-wait) with 0 ms remaining.
uint16_t input_pause( uint16_t ms ) {
    (void) ms;
    return 0;
}

// Block until any key is pressed.  IN6: loop on cpct_isAnyKeyPressed_f().
void input_wait_key( void ) {
}

// Block until no key is pressed.  IN6: loop while cpct_isAnyKeyPressed_f().
void input_wait_nokey( void ) {
}

// ASCII of the single key currently down (0 if none/ambiguous).
// IN6: walk the status buffer + a small cpct_keyID -> ASCII table.
uint16_t input_inkey( void ) {
    return 0;
}

// ASCII -> backend scancode for udk population.
// IN6: small ASCII -> cpct_keyID lookup table.  Stub returns 0.
input_scancode_t input_lookup_key( uint8_t ascii ) {
    (void) ascii;
    return (input_scancode_t) 0;
}

#endif // BUILD_FEATURE_INPUT_BACKEND_CPC

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
// Phase IN6 wires this to the real cpctelera keyboard primitives that RAGE1
// hand-translates sdas -> z88dk z80asm in engine/src/cpc/cpct_keyboard.asm
// (cpct_scanKeyboard / cpct_scanKeyboard_f / cpct_isKeyPressed /
// cpct_isAnyKeyPressed_f + the 10-byte cpct_keyboardStatusBuffer).  The macros
// below resolve to those symbols; the heavier HAL entry points (state read,
// scancode capture, pause, inkey, key lookup) are real function bodies in
// engine/src/input.c (BUILD_FEATURE_INPUT_BACKEND_CPC).  See input.md §3.2.
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
// cpctelera keyID: a 16-bit value whose LOW byte is the matrix line (0..9)
// and whose HIGH byte is the bit mask within that line (exactly one bit set).
// This is the encoding cpct_isKeyPressed() consumes (fastcall: L = matrix
// line, H = bit mask).  The layout is fixed here so the engine's by-value
// `input_udk_t keys` field (struct controller_info_s) is a complete type.
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
// CTRL_TYPE_* range on both backends (input.md §3.3, IN6-3).  input_state_read()
// in input.c reads JOY0/JOY1 via the Joy0_*/Joy1_* cpct_keyID values below.
////////////////////////////////////////////////////////////////////////////////

#define CTRL_TYPE_JOY0  4
#define CTRL_TYPE_JOY1  5

////////////////////////////////////////////////////////////////////////////////
// cpctelera keyID constants (subset).
//
// A cpct_keyID is (bit_mask << 8) | matrix_line — i.e. high byte = bit mask
// (exactly one bit), low byte = matrix line (0..9).  Values copied verbatim
// from cpctelera src/keyboard/keyboard.h (pinned 662fc885) for the keys RAGE1
// references: the udk default movement keys, the pause key, the Joy0_*/Joy1_*
// directions/fire, plus the small ASCII<->keyID lookup table set in input.c.
// Only the subset RAGE1 needs is reproduced here (full enum stays upstream).
////////////////////////////////////////////////////////////////////////////////

// Movement / common keys
#define CPC_Key_Q      0x0808
#define CPC_Key_A      0x2008
#define CPC_Key_O      0x0404
#define CPC_Key_P      0x0803
#define CPC_Key_Space  0x8005
#define CPC_Key_H      0x1005       // pause key (Open Q3, IN6-7)
#define CPC_Key_Y      0x0805
#define CPC_Key_N      0x4005
#define CPC_Key_0      0x0104
#define CPC_Key_Enter  0x4000       // small (numeric-pad) Enter
#define CPC_Key_Return 0x0402       // big Return
#define CPC_Key_Esc    0x0408
#define CPC_Key_Del    0x8009

// Joystick 0 (matrix line 0x09)
#define CPC_Joy0_Up    0x0109
#define CPC_Joy0_Down  0x0209
#define CPC_Joy0_Left  0x0409
#define CPC_Joy0_Right 0x0809
#define CPC_Joy0_Fire1 0x1009

// Joystick 1 (shared with cursor/number keys on matrix line 0x06)
#define CPC_Joy1_Up    0x0106
#define CPC_Joy1_Down  0x0206
#define CPC_Joy1_Left  0x0406
#define CPC_Joy1_Right 0x0806
#define CPC_Joy1_Fire1 0x1006

////////////////////////////////////////////////////////////////////////////////
// Backend scancode / default-key constants.
//
// INPUT_SCANCODE_PAUSE is the cpct_keyID of the pause key (Open Q3 / IN6-7:
// "H" for "halt", away from the cursor keys to avoid accidental triggers).
//
// INPUT_SCANCODE_DEFAULT_* are the real cpct_keyID movement defaults (same
// physical keys as the ZX backend: Q/A/O/P + Space fire).
//
// KBD_DEFAULT_* are platform-portable ASCII defaults (same chars as ZX) fed
// through input_lookup_key() by init_controllers(); on CPC the lookup resolves
// each ASCII char to its cpct_keyID.
////////////////////////////////////////////////////////////////////////////////

#define INPUT_SCANCODE_PAUSE          CPC_Key_H

#define INPUT_SCANCODE_DEFAULT_UP     CPC_Key_Q
#define INPUT_SCANCODE_DEFAULT_DOWN   CPC_Key_A
#define INPUT_SCANCODE_DEFAULT_LEFT   CPC_Key_O
#define INPUT_SCANCODE_DEFAULT_RIGHT  CPC_Key_P
#define INPUT_SCANCODE_DEFAULT_FIRE   CPC_Key_Space

#define KBD_DEFAULT_UP                'Q'
#define KBD_DEFAULT_DOWN              'A'
#define KBD_DEFAULT_LEFT              'O'
#define KBD_DEFAULT_RIGHT             'P'
#define KBD_DEFAULT_FIRE              ' '

////////////////////////////////////////////////////////////////////////////////
// Translated cpctelera keyboard primitives (engine/src/cpc/cpct_keyboard.asm).
//
// These are the real cpctelera C-ABI symbols, hand-translated sdas -> z80asm.
// input.c and the macros below call them.  cpct_isKeyPressed() is fastcall
// (keyID in HL); the scan/any routines take no args.  cpct_keyboardStatusBuffer
// is the 10-byte (80-bit) status array (0 = pressed, 1 = not pressed).
////////////////////////////////////////////////////////////////////////////////

extern uint8_t cpct_keyboardStatusBuffer[ 10 ];

extern void    cpct_scanKeyboard( void );
extern void    cpct_scanKeyboard_f( void );
extern uint8_t cpct_isKeyPressed( input_scancode_t keyID ) __z88dk_fastcall;
extern uint8_t cpct_isAnyKeyPressed_f( void );

////////////////////////////////////////////////////////////////////////////////
// HAL macro family (preprocessor-resolved entry points).
//
// input_state_read(), input_capture_scancode(), input_pause(),
// input_wait_key(), input_wait_nokey(), input_inkey() and input_lookup_key()
// are real functions (prototypes in input.h / below, bodies in input.c) and
// are intentionally NOT defined here as macros.
////////////////////////////////////////////////////////////////////////////////

// Per-frame keyboard refresh.  ZX is a no-op (in_stick_* read the port
// synchronously).  On CPC we must repopulate cpct_keyboardStatusBuffer once per
// frame before any read.  cpct_scanKeyboard() manages its own DI/EI, so it is
// safe to call directly from C here (the _if variant requires caller-managed
// DI/EI, which a bare macro cannot wrap — deviation noted in input.md §5).
#define input_scan()                  cpct_scanKeyboard()

// "Is any key currently pressed?" -> cpct_isAnyKeyPressed_f() (reads the buffer
// last filled by input_scan()).
#define input_test_key()              cpct_isAnyKeyPressed_f()

// Single-key query by backend scancode (cpct_keyID) -> cpct_isKeyPressed().
#define input_key_pressed( sc )       cpct_isKeyPressed( (input_scancode_t)(sc) )

////////////////////////////////////////////////////////////////////////////////
// Prototypes for the CPC-specific HAL functions that are macros on ZX but
// real function bodies on CPC (input.md §3.2).  input.h already declares
// input_state_read / input_capture_scancode / input_wait_key /
// input_wait_nokey / input_lookup_key (the cross-platform contract), so only
// the CPC-only ones are declared here.
////////////////////////////////////////////////////////////////////////////////

// Busy-wait `ms` milliseconds, early-out on keypress, return remaining ms.
// ZX resolves this to z88dk's in_pause() via a macro; CPC implements a real
// loop (cpct_scanKeyboard_f + cpct_isAnyKeyPressed_f) in input.c.
uint16_t input_pause( uint16_t ms );

// ASCII of the single key currently down (0 if none/ambiguous). ZX -> macro
// over z88dk's in_inkey(); CPC walks the status buffer against a small
// keyID->ASCII table in input.c.
uint16_t input_inkey( void );

#endif // _RAGE1_INPUT_CPC_H

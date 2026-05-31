////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <stdint.h>

#include "features.h"

// G7: <arch/zx.h> (IO_7FFD etc.) is ZX-only; it is only referenced by the
// ZX-128 banking code below (guarded by BUILD_FEATURE_ZX_TARGET_128).  Guard
// the include too so this file compiles under +cpc.  features.h is included
// first so the platform macro is defined; on ZX the branch is taken exactly as
// before (byte-identical — the include simply moved one line below features.h,
// which is itself header-guarded and order-independent here).
#if defined( BUILD_FEATURE_PLATFORM_ZX48 ) || defined( BUILD_FEATURE_PLATFORM_ZX128 )
#include <arch/zx.h>
#endif

#include "rage1/interrupts.h"

// Memory Banking configuration for port $7FFD:
//
// - Bits 0-2: RAM page (0-7) to map into memory at 0xc000 - OR'ed with the
//   bank number passed as argument
//
// - Bit 3: Select normal (0) or shadow (1) screen to be displayed.  The
//   normal screen is in bank 5, whilst the shadow screen is in bank 7. 
//   Note that this does not affect the memory between 0x4000 and 0x7fff,
//   which is always bank 5.
//
// - Bit 4: ROM select.  ROM 0 is the 128k editor and menu system; ROM 1
//   contains 48K BASIC.
//
// - Bit 5: If set, memory paging will be disabled and further output to
//   this port will be ignored until the computer is reset.
//
// So we want: bits 0-2: bank number to map; bit 3: 0 (normal screen);
// bit 4: 1 (48K ROM - *see below); bit 5: 0 (allow paging)
//
// Desired value: 00010000 | num_bank
//
// We would not care about bit 5 (ROM select) since we are not calling any
// code there.  But SP1 startup copies character bitmaps from ROM for tiles
// 32-127, so that ASCII chars can be regularly used as tiles and output
// text out of the box.  So we NEED the 48K ROM to be paged for SP1 to
// correctly initialize those tiles.

#define DEFAULT_IO_7FFD_BANK_CFG	( 0x10 )

// this only makes sense in banked builds (ZX 128 or future CPC 6128)
// B5-4: guard updated from BUILD_FEATURE_ZX_TARGET_128 to the canonical
// platform condition so cpc-flat (no banking) compiles this code out.
// ZX 128 defines both BUILD_FEATURE_ZX_TARGET_128 and
// BUILD_FEATURE_PLATFORM_ZX128, so the new condition is equivalent on ZX.
#if defined( BUILD_FEATURE_PLATFORM_ZX128 ) || defined( BUILD_FEATURE_PLATFORM_CPC_BANKED )
uint8_t memory_current_memory_bank;

// The following function implemented below in asm to minimize T-states with
// interrupts disabled
//
// uint8_t memory_switch_bank( uint8_t bank ) __z88dk_fastcall {
// 
//     // Mask the 3 lowest bits of bank, then add it to the default value for
//     // IO_7FDD.  Then save the bank that is currently mapped.
// 
//     // atomically update the bank port and the bank state variable.  See
//     // doc/BANKED-FUNCTIONS.md, section "Interrupts" for a detailed
//     // explanation
// 
//     // Returns the previous bank to avoid race conditions between getting
//     // the current bank and setting the new one
// 
//     uint8_t previous_memory_bank;
// 
//     intrinsic_di_if_needed();	// enter critical section
//     previous_memory_bank = memory_current_memory_bank;
//     IO_7FFD = ( DEFAULT_IO_7FFD_BANK_CFG | ( bank & 0x07 ) );
//     memory_current_memory_bank = bank;
//     intrinsic_ei_if_needed();	// exit critical section
// 
//     return previous_memory_bank;
// }

// disable "function must return value" warning
#pragma disable_warning 59
//dusable "unreferenced function argument" warning
#pragma disable_warning 85

uint8_t memory_switch_bank( uint8_t bank ) __z88dk_fastcall {
    __asm
    ;; bank comes in L register
    ld d,l
    di
    ld hl,_interrupt_nesting_level
    inc (hl)
    ld hl,_memory_current_memory_bank
    ld e, (hl)
    ld a, d
    and a,0x07
    or a,0x10
    ld bc,_IO_7FFD
    out (c),a
    ld (hl), d
    ld hl,_interrupt_nesting_level
    dec (hl)
    jr NZ,memory_switch_bank_no_ei
    ei
memory_switch_bank_no_ei:
    ;; return value in L
    ld      l, e
    __endasm;
}

#endif // BUILD_FEATURE_PLATFORM_ZX128 || BUILD_FEATURE_PLATFORM_CPC_BANKED

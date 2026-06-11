////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

/////////////////////////////////////
//
// Interrupt initialization
//
/////////////////////////////////////

#include <stdlib.h>
#include <string.h>
#include <intrinsic.h>

#include "features.h"

// G7: <im2.h> (IM2 ISR macros) and <z80.h> (z80_bpoke/z80_wpoke) are ZX-only
// — the CPC uses a different interrupt mechanism (Phase B/T3).  Guard these
// includes (and the ZX ISR/IM2 machinery below) so this file compiles under
// +cpc against the gfx-stub.  features.h is included first so the platform
// macro is defined; on ZX both includes are taken exactly as before
// (byte-identical).
#if defined( BUILD_FEATURE_PLATFORM_ZX48 ) || defined( BUILD_FEATURE_PLATFORM_ZX128 )
#include <im2.h>
#include <z80.h>
#endif

// CPC platforms use a RAGE1-owned, firmware-free IM1 path: init_interrupts()
// installs `jp rage1_cpc_isr` directly at the 0x0038 IM1 vector and takes full
// control — no firmware ISR, no z88dk-clib vector dispatcher.  So the CPC ISR
// needs no <arch/cpc.h> / <interrupt.h> registration helpers; the shared
// handler lives in engine/src/cpc/rage1_cpc_isr_body.inc.

#include "rage1/audio.h"
#include "rage1/interrupts.h"
#include "rage1/debug.h"
#include "rage1/memory.h"

#include "game_data.h"

// data struct and ISR hook for timekeeping
// struct time_s current_time = { 0, 0, 0, 0 };
// moved to lowmem/asmdata.asm to ensure it is placed in memory below 0xC000

// timer tick routine, invoked from ISR
void do_timer_tick( void ) {
   current_time.ticks++;
   if ( ++current_time.frame == 50 ) {		// 50 frames per second
      current_time.frame = 0;
      if ( ++current_time.sec == 60 ) {
         current_time.sec = 0;
         if ( ++current_time.min == 60 ) {
            current_time.min = 0;
            ++current_time.hour;
         }
      }
   }
}

// extern uint8_t periodic_tasks_enabled;

// periodic tasks function, invoked from ISR
// do not add code here unless it is strictly needed!
void do_periodic_isr_tasks( void ) {
#ifdef BUILD_FEATURE_AUDIO_MUSIC
   audio_music_tick();
#endif
}

void interrupt_enable_periodic_isr_tasks( void ) {
   periodic_tasks_enabled++;
}
 
///////////////////////
// ISR CONFIGURATION
///////////////////////

// G7: the IM2 ISR + init_interrupts() below are ZX-specific (IM2 mode, z80
// pokes, fixed IV/ISR hardware addresses).  The CPC interrupt path is a
// different mechanism and lands in Phase B/T3.  Guard the whole ZX block so
// this file compiles under +cpc; a no-op CPC stub init_interrupts() is
// provided in the #else.  ZX output is byte-identical (the guard is taken on
// both ZX48 and ZX128, exactly as the per-platform #ifdefs below already are).
#if defined( BUILD_FEATURE_PLATFORM_ZX48 ) || defined( BUILD_FEATURE_PLATFORM_ZX128 )

// ISR definition
IM2_DEFINE_ISR(service_interrupt)
{
    do_timer_tick();
    if ( periodic_tasks_enabled )
        do_periodic_isr_tasks();
}

// Initialize interrupts in IM2 mode
// IV_ADDR must be 256-byte aligned
// ISR_ADDR and IV_BYTE must match: if IV_BYTE is 0x81, ISR_ADDR must be
// 0x8181

// B2-3: switch the platform-selecting #ifdefs from the legacy
// BUILD_FEATURE_ZX_TARGET_{48,128} spelling to the cross-platform
// BUILD_FEATURE_PLATFORM_ZX{48,128} spelling. Both macros are emitted in
// parallel by datagen.pl (B1-4), so either spelling is valid here; we
// prefer PLATFORM_* so adding a CPC port (Phase B4+) becomes a sibling
// #elif rather than a separate file. The legacy ZX_TARGET_* macros stay
// emitted indefinitely as silent aliases (README §5.6) — external games
// that test those names directly are unaffected.

// In 128 mode, IV is at 0x8000-0x8100, ISR at 0x8181, but can be changed in config file
#ifdef BUILD_FEATURE_PLATFORM_ZX128
   #define IV_ADDR	( ( unsigned char * ) RAGE1_CONFIG_INT128_IV_TABLE_ADDR )

   #define ISR_ADDR	( ( unsigned char * ) RAGE1_CONFIG_INT128_ISR_ADDRESS )
   #define IV_BYTE	( RAGE1_CONFIG_INT128_ISR_VECTOR_BYTE )
#endif

// In 48 mode: SP1 uses IV at 0xD000, ISR at 0xD1D1; JSP uses IV at 0xE000, ISR at 0xE1E1
#ifdef BUILD_FEATURE_PLATFORM_ZX48
   #ifdef BUILD_FEATURE_GFX_BACKEND_JSP
      #define IV_ADDR	( ( unsigned char * ) 0xE000 )
      #define ISR_ADDR	( ( unsigned char * ) 0xE1E1 )
      #define IV_BYTE	( 0xE1 )
   #else
      #define IV_ADDR	( ( unsigned char * ) 0xD000 )
      #define ISR_ADDR	( ( unsigned char * ) 0xD1D1 )
      #define IV_BYTE	( 0xD1 )
   #endif
#endif

// code to patch at ISR_ADDR: jp xxxx
#define Z80_OPCODE_JP	( 0xc3 )

// This is the only function where barebones intrinsic_ei() and
// intrinsic_di() calls are allowed.  In the rest of RAGE1 code
// intrinsic_di_if_needed() and intrinsic_ei_if_needed() should be used,
// which take into account the interrupt nesting level and only
// disable/enable ints if needed

void init_interrupts(void) {

   // do not disturb :-)
   intrinsic_di();

   // configure ISR
   memset( IV_ADDR, IV_BYTE, 257);
   z80_bpoke( ISR_ADDR, Z80_OPCODE_JP );
   z80_wpoke( ISR_ADDR + 1, (uint16_t) service_interrupt );
   im2_init( IV_ADDR );

   // reset interrupt nesting level
   interrupt_nesting_level = 0;

   // ensure periodic tasks do not run yet
   periodic_tasks_enabled = 0;

   // everything is setup, allow everything now
   intrinsic_ei();
}

#elif defined( BUILD_FEATURE_PLATFORM_CPC464 ) || defined( BUILD_FEATURE_PLATFORM_CPC6128 )

// RAGE1-owned, firmware-free CPC IM1 interrupt path — UNIFIED for cpc-flat and
// cpc-banked.  RAGE1 installs its own low-memory ISR (rage1_cpc_isr, the shared
// body engine/src/cpc/rage1_cpc_isr_body.inc) directly at the 0x0038 IM1 vector
// from init_interrupts() and takes full control: no firmware ISR, no z88dk-clib
// vector dispatcher (cpc_add_fast_isr / asm_interrupt_handler).  The ISR derives
// the 50 Hz tick by dividing the ~300 Hz CPC raster interrupt by six (the Gate
// Array hardware-locks 6 interrupts/frame to the display — drift-free), runs the
// tick body interruptible, and guards reentrancy with isr_busy.  Full design:
// doc/multiplatform-plan/cpc-interrupts.md.
//
// Only the ISR/state PLACEMENT differs per mode (handled by the two wrapper .asm
// files): on cpc-banked the ISR + its state link <0x4000 (page A, always mapped)
// so a tick may fire while a dataset bank is paged into 0x4000-0x7FFF; on cpc-flat
// (no swap window) they are ordinary code/BSS.  The C below is identical for both.

// ISR state.  cpc-banked: hand-placed <0x4000 in asmdata_cpc_banked.asm.
// cpc-flat: plain C BSS in engine/src/cpc/asmdata_cpc.c.
extern uint8_t cpc_isr_div_counter;     // frame-position / divide-by-six counter
extern uint8_t isr_busy;                // 1-bit 50 Hz-body reentrancy guard

// the low asm IM1 handler, installed at 0x0038 by init_interrupts()
extern void rage1_cpc_isr( void );

// The 50 Hz body the asm ISR calls (interrupts enabled) on each frame tick — same
// portable semantics as the ZX IM2 ISR body.  The asm wrapper does all register
// saving and the divide-by-six; this is plain C.  On cpc-banked it MUST link
// <0x4000 (it runs while a dataset bank may be mapped) — ASSERTED by
// section-check-cpc (Makefile-cpc-banked) for _rage1_50hz_tick / _do_timer_tick /
// _do_periodic_isr_tasks; cpc-flat has no such constraint.
void rage1_50hz_tick( void ) {
   do_timer_tick();
   if ( periodic_tasks_enabled )
      do_periodic_isr_tasks();
}

void init_interrupts( void ) {

   // do not disturb while we take over IM1
   intrinsic_di();

   // RAGE1 owns IM1: install `jp rage1_cpc_isr` at 0x0038.  No firmware ISR, no
   // z88dk-clib vector dispatcher (cpc_add_fast_isr / asm_interrupt_handler).
   __asm
      im    1
      ld    a, 0xc3                  ; JP opcode
      ld    (0x0038), a
      ld    hl, _rage1_cpc_isr
      ld    (0x0039), hl
   __endasm;

   cpc_isr_div_counter = 0;
   isr_busy = 0;
   interrupt_nesting_level = 0;
   periodic_tasks_enabled = 0;

   // everything is set up, allow interrupts now
   intrinsic_ei();
}

#else // any other future non-ZX, non-CPC platform

// No-op stub: a platform that is neither ZX nor CPC has no ISR wiring yet.
void init_interrupts( void ) {
}

#endif // PLATFORM_ZX{48,128} / PLATFORM_CPC{464,6128}

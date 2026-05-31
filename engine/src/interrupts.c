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

// G8: CPC platforms use the firmware-free IM1 path.  The z88dk +cpc CRT, built
// with CRT_DISABLE_FIRMWARE_ISR=1 (set in zpragma-cpc-flat.inc), owns the
// 0x0038 IM1 vector and calls registered "fast" handlers at the raw CPC 300 Hz
// rate WITHOUT paging the lower ROM (no firmware).  We register a fast handler
// and divide its 300 Hz cadence by six to drive RAGE1's 50 Hz tick.  banking.md
// §3.5 ("divide-by-six in software").  <arch/cpc.h> provides cpc_add_fast_isr();
// <interrupt.h> provides isr_t.
#if defined( BUILD_FEATURE_PLATFORM_CPC464 ) || defined( BUILD_FEATURE_PLATFORM_CPC6128 )
#include <arch/cpc/cpc.h>
#include <interrupt.h>
#endif

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

// G8: real CPC IM1 interrupt path (firmware-free, owns 0x0038 via the +cpc CRT
// interposer; banking.md §3.5).  This is the cpc-flat implementation; it is
// written so Phase B6 can extend it for cpc-banked.  The divide-by-six counter
// and the 50 Hz tick dispatch are kept platform-neutral here; any bank-specific
// interlock (interrupt_nesting_level vs the bank-switch primitive — banking.md
// §3.5.1) is guarded OUT of cpc-flat and added by B6 for cpc-banked.

// Divide-by-six counter: the CPC raster ISR fires at 300 Hz (fixed by the Gate
// Array).  Every sixth fast tick is one RAGE1 50 Hz frame tick.  banking.md §3.5.
#define CPC_ISR_DIVIDER     6
static uint8_t cpc_isr_div_counter = 0;

// CPC fast ISR (300 Hz), registered with cpc_add_fast_isr().  The +cpc CRT
// fast-isr interposer (CRT_DISABLE_FIRMWARE_ISR=1 path, cpc_crt0.asm) saves
// AF/HL/BC before calling asm_interrupt_handler, which saves BC/DE around each
// registered handler.  Neither layer saves IX, IY, or the Z80 shadow/alternate
// register set (AF'/BC'/DE'/HL').
//
// IX/IY must be saved because SDCC uses IX as a frame pointer in callees.
//
// The shadow registers must ALSO be saved because a future AU5 music tracker
// running inside this ISR (or any library called from do_periodic_isr_tasks)
// may use exx/ex af,af' internally.  Without the save/restore the shadow set
// of the interrupted main code would be silently corrupted, causing intermittent
// crashes once AU5 is wired.  Save them now so the ISR is correct regardless
// of what the tick body does — defensive correctness, not a pre-optimisation.
//
// Save/restore sequence mirrors the ZX IM2 ISR (asm_im2_push/pop_registers):
//   entry: exx + ex af,af' swaps shadow→main position; push the four regs; exx
//          returns to the C-visible main set for the rest of the handler.
//   exit:  reverse: exx swaps shadow back to main position; pop in LIFO order;
//          ex af,af' + exx restores both halves.
//   The mnemonic is written "ex af,af" (no trailing apostrophe): SDCC's C lexer
//   reads the ' inside an __asm block as an unterminated char literal, but z80asm
//   accepts the no-apostrophe form and emits the identical EX AF,AF' opcode (0x08).
//
// Body: bump the divide-by-six counter; on every sixth tick run the SAME
// portable do_timer_tick() / do_periodic_isr_tasks() the ZX ISR drives.  Kept
// short so the 300 Hz budget (banking.md §3.5) is respected.
static void cpc_fast_isr( void ) {
   __asm
      ; --- save IX, IY (not preserved by CRT dispatcher) ---
      push ix
      push iy
      ; --- save shadow/alternate register set ---
      ; exx swaps shadow regs into main position for pushing.
      ; "ex af,af" (apostrophe omitted: SDCC's C lexer treats the trailing ' in
      ; an __asm block as a char-literal delimiter; z80asm emits opcode 0x08).
      exx
      ex af,af            ; EX AF,AF — shadow AF into main position
      push af
      push bc
      push de
      push hl
      ; exx restores the main register set for C code that follows
      exx
   __endasm;

   if ( ++cpc_isr_div_counter >= CPC_ISR_DIVIDER ) {
      cpc_isr_div_counter = 0;

      // one 50 Hz frame tick — identical semantics to the ZX IM2 ISR body
      do_timer_tick();
      if ( periodic_tasks_enabled )
         do_periodic_isr_tasks();
   }

   __asm
      ; --- restore shadow/alternate register set ---
      ; exx brings shadow regs back to main position for popping
      exx
      pop hl
      pop de
      pop bc
      pop af
      ex af,af            ; EX AF,AF — restore shadow AF
      exx
      ; --- restore IX, IY ---
      pop iy
      pop ix
   __endasm;
}

// Initialize the CPC interrupt path.  No IM2 table / z80 pokes (those are ZX):
// we hand our fast handler to the CRT's IM1 interposer.  cpc_add_fast_isr()
// installs cpc_fast_isr into the CRT 'fast_vectors' table; the CRT's 0x0038
// interposer (CRT_DISABLE_FIRMWARE_ISR=1) calls it at 300 Hz with no firmware.
void init_interrupts( void ) {

   // do not disturb while we wire the ISR
   intrinsic_di();

   // reset the divide-by-six counter
   cpc_isr_div_counter = 0;

   // reset interrupt nesting level (shared interlock; inert on cpc-flat, used
   // by B6 on cpc-banked — banking.md §3.5.1)
   interrupt_nesting_level = 0;

   // ensure periodic tasks do not run yet
   periodic_tasks_enabled = 0;

   // register the 300 Hz fast handler with the +cpc CRT IM1 interposer
   cpc_add_fast_isr( (isr_t) cpc_fast_isr );

   // everything is setup, allow interrupts now
   intrinsic_ei();
}

#else // any other future non-ZX, non-CPC platform

// No-op stub: a platform that is neither ZX nor CPC has no ISR wiring yet.
void init_interrupts( void ) {
}

#endif // PLATFORM_ZX{48,128} / PLATFORM_CPC{464,6128}

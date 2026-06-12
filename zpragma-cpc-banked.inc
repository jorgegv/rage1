////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

// COMPILE TIME CRT CONFIGURATION FOR CPC-BANKED (CPC 6128) BUILD
//
// Phase T3a bring-up: at this phase Makefile-cpc-banked builds a no-banking CPC
// programme (the cpc-hello-banked smoke game) through the +cpc toolchain, exactly
// like cpc-flat. The bank-switch primitive, datasets, codesets and the cpc-banked
// memory map land in Phase B6/B7 (see doc/multiplatform-plan/management/
// cpc-banked-bringup.md). Until then this mirrors zpragma-cpc-flat.inc.
//
// cpc-banked memory map (Shape A, banking.md §3.1.4 / DC3):
//   0x0000-0x3FFF  Page A (RAM0): vectors/ISR + resident engine code (CRT @0x1200)
//   0x4000-0x7FFF  Page B: swap window (RAM1 home: JSP buffers) — Phase B6/B7
//   0x8000-0xBFFF  Page C (RAM2): dataset buffer + home data + stack
//   0xC000-0xFFFF  Page D (RAM3): screen RAM — must NOT hold code/data
// (Shape B — full-page-A dataset buffer, code in page C, CRT_ORG_CODE=0x8000 —
//  is the alternative under experiment per DC3-D; selected via these constants.)

// CRT_ORG_CODE: Shape-A page-A code origin.  Now sourced from
// etc/rage1-config.yml (memory_map.cpc_banked.crt_org_code) and injected by
// Makefile-cpc-banked via -pragma-define:CRT_ORG_CODE (single source of truth);
// NOT set here, as a value here would conflict with the command-line override.

// REGISTER_SP: now sourced from etc/rage1-config.yml
// (memory_map.cpc_banked.register_sp) and injected by Makefile-cpc-banked via
// JSP_CPC_CFLAGS -pragma-define:REGISTER_SP (single source of truth); NOT set
// here, as a value here would conflict with (and override) the command-line value.
#pragma output CRT_STACK_SIZE         = 256

// Disable interrupts at startup (CPC firmware live until RAGE1's CPC HAL takes over).
#pragma output CRT_ENABLE_EIDI        = 1

// Firmware-free IM1 interrupt model (banking.md §3.5): the +cpc CRT installs only
// a do-nothing IM1 stub at 0x0038 (no firmware ISR, so the lower ROM is never
// paged in during an interrupt); RAGE1 then owns IM1 from init_interrupts(),
// poking `jp rage1_cpc_isr` over 0x0038 (engine/src/cpc/rage1_cpc_isr_body.inc).
#pragma output CRT_DISABLE_FIRMWARE_ISR = 1

// Standard no-file-system build (same as the cpc-flat / ZX48 profile).
#pragma output CRT_ENABLE_CLOSE       = 0
#pragma output CRT_ENABLE_RESTART     = 1

#pragma output CLIB_MALLOC_HEAP_SIZE  = 0
#pragma output CLIB_STDIO_HEAP_SIZE   = 0

#pragma output CLIB_FOPEN_MAX         = -1
#pragma output CLIB_OPEN_MAX          = -1

// B7 step 9.4: enable the custom linker memory map (mmap-cpc-banked.inc) so the
// engine's swap-active globals + the dzx0 decompressor land BELOW 0x4000 (page
// A), out of the 0x4000-0x7FFF Gate-Array swap window.  See that file's header
// and doc/multiplatform-plan/management/cpc-banked-bringup.md (step 9.4).
//
// IMPORTANT: set MMAP (UN-prefixed), NOT __MMAP.  crt/classic/crt_rules.inc
// (included by cpc_crt0.asm) derives `defc __MMAP = MMAP` when MMAP is defined,
// so `#pragma output MMAP = -1` yields __MMAP = -1 with no duplicate-symbol
// error.  Setting `#pragma output __MMAP = -1` directly DOES collide (the +cpc
// CRT also defc's __MMAP) — that was the previously-recorded blocker.
#pragma output MMAP                   = -1

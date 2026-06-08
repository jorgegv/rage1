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

// CRT_ORG_CODE: Shape-A page-A code origin. z88dk +cpc default is 0x1200.
#pragma output CRT_ORG_CODE           = 0x1200

// Stack at top of page C, just below screen RAM at 0xC000 (banking.md §3.1.4).
#pragma output REGISTER_SP            = 0xBF00
#pragma output CRT_STACK_SIZE         = 256

// Disable interrupts at startup (CPC firmware live until RAGE1's CPC HAL takes over).
#pragma output CRT_ENABLE_EIDI        = 1

// Firmware-free IM1 interrupt model (banking.md §3.5): the +cpc CRT installs its
// own IM1 interposer at 0x0038 and calls cpc_add_fast_isr()/cpc_add_vsync_isr()
// handlers, so the lower ROM is never paged in during an interrupt.
#pragma output CRT_DISABLE_FIRMWARE_ISR = 1

// Standard no-file-system build (same as the cpc-flat / ZX48 profile).
#pragma output CRT_ENABLE_CLOSE       = 0
#pragma output CRT_ENABLE_RESTART     = 1

#pragma output CLIB_MALLOC_HEAP_SIZE  = 0
#pragma output CLIB_STDIO_HEAP_SIZE   = 0

#pragma output CLIB_FOPEN_MAX         = -1
#pragma output CLIB_OPEN_MAX          = -1

// NOTE: __MMAP = -1 (custom mmap) is intentionally NOT set yet (same as cpc-flat).
// The +cpc CRT defines __MMAP=0 before pragmas; overriding it errors. The +cpc
// CRT's built-in section layout is used; mmap-cpc-banked.inc is a documentation /
// section-check artefact at this phase. A custom-mmap hook is Phase B5/B6 work.
//
// #pragma output __MMAP = -1   <-- blocked (see above)

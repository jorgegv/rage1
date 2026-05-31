////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

// COMPILE TIME CRT CONFIGURATION FOR CPC-FLAT (CPC464/664) BUILD
//
// Memory layout (banking.md §3.1.3):
//   0x0000-0x3FFF  Lower RAM (firmware vectors / ISR / free RAM)
//   0x4000-0xBEFF  C code + data + bss (~32 KB)
//   0xBF00-0xBFFF  Stack (top-down, 256 bytes initial budget)
//   0xC000-0xFFFF  Screen RAM (mode 1, 16 KB) — must NOT be used for code/data
//
// z88dk +cpc default CRT_ORG_CODE is 0x1200. T2-2 uses 0x1200 (inside
// the lower-RAM free range 0x0400-0x3FFF).  The PoC used 0x4000 only
// because it needed to page in the lower ROM for the firmware font;
// the real engine renders from its own charset, so 0x1200 is correct.

// z88dk +cpc default is 0x1200; keep it explicit for clarity.
#pragma output CRT_ORG_CODE           = 0x1200

// Stack at top of usable RAM, just below screen RAM at 0xC000.
// 256 bytes is the initial budget per banking.md §3.1.3; exact size
// is TBD after Phase B4-2 hand-walk of worst-case ISR+library nesting.
#pragma output REGISTER_SP            = 0xBF00
#pragma output CRT_STACK_SIZE         = 256

// Disable interrupts at startup (the CPC firmware is live until RAGE1's
// CPC HAL disables it; EIDI=1 ensures we start with interrupts off while
// the engine initialises hardware).
#pragma output CRT_ENABLE_EIDI        = 1

// G8: firmware-free IM1 interrupt model (banking.md §3.5).  With this set, the
// +cpc CRT installs its OWN IM1 interposer at 0x0038 (no AMSDOS/firmware ISR,
// so the lower ROM is never paged in during an interrupt — avoiding the R2
// lower-ROM-font masking caveat) and calls handlers registered via
// cpc_add_fast_isr() (300 Hz) / cpc_add_vsync_isr() (50 Hz).  RAGE1's CPC ISR
// (engine/src/interrupts.c) registers a fast handler and divides by six to a
// 50 Hz tick.  Without this, cpc_add_*_isr route through firmware tickers that
// page the lower ROM — undesirable for the engine.
#pragma output CRT_DISABLE_FIRMWARE_ISR = 1

// Standard no-file-system build (same as ZX48 profile).
#pragma output CRT_ENABLE_CLOSE       = 0
#pragma output CRT_ENABLE_RESTART     = 1

#pragma output CLIB_MALLOC_HEAP_SIZE  = 0
#pragma output CLIB_STDIO_HEAP_SIZE   = 0

#pragma output CLIB_FOPEN_MAX         = -1
#pragma output CLIB_OPEN_MAX          = -1

// NOTE: __MMAP = -1 (custom mmap) is intentionally NOT set here at Phase T2.
// The +cpc CRT defines __MMAP=0 in crt_rules.inc before pragmas are applied,
// which causes a "duplicate definition" error if we try to override it.
// The +cpc CRT's built-in section layout is used for Phase T2.
//
// Phase T2 uses mmap-cpc-flat.inc as a documentation artefact and for the
// section-check tool; it is NOT fed to the linker via __MMAP=-1 at this phase.
// A proper per-platform mmap hook (e.g. via --custom-crt or a +cpc z80asm
// passthrough) will be investigated for Phase T3/B5.
//
// #pragma output __MMAP = -1   <-- blocked at Phase T2; see above

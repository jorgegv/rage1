////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

// CRT CONFIG FOR THE cpc-banked COLD-BOOT LOADER (B7 step 9.2c/9.3)
//
// The loader is a SEPARATE +cpc CRT program (NOT the engine).  It is a normal
// CRT build specifically so it can reach the AMSDOS firmware CAS routines through
// z88dk's `firmware` interposer (which restores the firmware alt-register/exx
// environment around the call); a --no-crt loader with DIRECT firmware calls
// routes CAS_IN to TAPE instead of disc (empirically validated).  The step-8a PoC
// (a +cpc CRT program + interposer) loaded from disc successfully — this mirrors it.
//
// Placement (the key constraint): the loader must run from an ALWAYS-MAPPED page
// that survives bank streaming.  During streaming the loader selects GA Config
// 4-7, which maps RAM4-7 into the 0x4000-0x7FFF window (page B) — so the loader
// must NOT live in page B (that includes the JSP buffer at 0x5800-0x7FFF, which
// would page itself out).  Page A (RAM0) and page C (RAM2) stay fixed across
// Configs 0/4-7.  We use page C, just ABOVE the 0x8000-0x87FF firmware CAS input
// buffer and below the AMSDOS workspace (~0xA67B): CRT_ORG_CODE = 0x8800.  The
// engine image (GAME.BIN, 0x1200..) and the loader (0x8800..) do not overlap, and
// the engine overwrites this page-C region only later (dataset buffer), after the
// loader has jp'd to 0x1200.
//
// MUST match banking.cpc-banked.loader.loader_org in etc/rage1-config.yml (the
// Makefile reads loader_org from there for the AMSDOS wrap / RUN" entry).

// loader code origin — page C, above the 0x8000 CAS buffer.
#pragma output CRT_ORG_CODE           = 0x8800

// loader stack — well below the AMSDOS workspace (~0xA67B), above the loader code.
#pragma output REGISTER_SP            = 0xA000
#pragma output CRT_STACK_SIZE         = 256

// Interrupts ENABLED at startup: the AMSDOS disc routines rely on the firmware
// 300 Hz tick (motor spin-up / timeouts).  CRT_DISABLE_FIRMWARE_ISR is left at
// the +cpc default (0) so the CRT preserves the firmware ISR (via the interposer
// ISR), unlike the engine (which disables it and installs its own IM1 handler).
#pragma output CRT_ENABLE_EIDI        = 1

#pragma output CRT_ENABLE_CLOSE       = 0
#pragma output CRT_ENABLE_RESTART     = 1

#pragma output CLIB_MALLOC_HEAP_SIZE  = 0
#pragma output CLIB_STDIO_HEAP_SIZE   = 0
#pragma output CLIB_FOPEN_MAX         = -1
#pragma output CLIB_OPEN_MAX          = -1

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
// G8: CPC replacement for engine/src/00asmdata.asm.
//
// On ZX, the timekeeping struct + the asset/interrupt globals MUST live in low
// memory (below the bank-switched window), so they are hand-placed in the
// `code_crt_common` section by engine/src/00asmdata.asm.  That section is a ZX
// CRT construct; under the +cpc CRT it has no mapping and the linker drops it at
// $0000 (colliding with the CPC restart vectors and the 0x0038 IM1 vector — a
// silent corruption).
//
// cpc-flat is a flat 64 KB model with no bank-switched window, so these globals
// have no low-memory constraint: they are ordinary BSS.  We therefore define
// them as plain C globals here and EXCLUDE 00asmdata.asm from the cpc-flat link
// (Makefile-cpc-flat filters it out).  The symbols, types and semantics are
// byte-for-byte the same the engine expects (declared in interrupts.h /
// dataset.h / codeset.h); only the placement mechanism differs.
//
// (cpc-banked re-introduces an always-mapped page-A home for these — Phase B6;
// see banking.md §3.5 / §3.5.1.  This file is the cpc-FLAT definition.)
//

#include "features.h"

#if defined( BUILD_FEATURE_PLATFORM_CPC464 ) || defined( BUILD_FEATURE_PLATFORM_CPC6128 )

#include <stdint.h>

#include "rage1/interrupts.h"
#include "rage1/dataset.h"
#include "rage1/codeset.h"

// Timekeeping structure, updated via the CPC IM1 ISR (interrupts.c).
// Zero-initialised (BSS) — identical to the asm version's all-zero seed.
struct time_s current_time;

// periodic-tasks-enabled flag (gates do_periodic_isr_tasks in the ISR).
uint8_t periodic_tasks_enabled;

// Global asset-table pointers.  On cpc-flat banked_assets aliases home_assets
// (init_datasets()); both are plain pointers here.
struct dataset_assets_s *banked_assets;
struct dataset_assets_s *home_assets;

// Codeset assets pointer (unused on cpc-flat — no codesets — but the symbol
// must exist for the shared engine to link).
struct codeset_assets_s *codeset_assets;

// Interrupt nesting counter (the shared bank-switch interlock; inert on
// cpc-flat, used by B6 on cpc-banked).
uint8_t interrupt_nesting_level;

#endif // PLATFORM_CPC464 || PLATFORM_CPC6128

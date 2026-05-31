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
// Platform-portable arch shim (Phase G7 — gfx.md §1.2 obs 5 & obs 10).
//
// Several engine sources and a few engine headers pulled <arch/spectrum.h>
// (and <arch/zx.h>) in directly, for two ZX-only things:
//   1. the INK_*/PAPER_*/BRIGHT/FLASH colour-attribute macros, used only
//      inside the per-game DEFAULT_BG_ATTR value (e.g.
//      "#define DEFAULT_BG_ATTR ( INK_CYAN | PAPER_BLACK )") that flows
//      through the (ZX-only, inert-on-CPC) attribute layer; and
//   2. transitively, ZX BASIC tokens / hardware helpers that the engine
//      sources do NOT actually reference on the CPC code paths.
//
// On a ZX target this header is a transparent pass-through to
// <arch/spectrum.h>, so the preprocessed output — and therefore the emitted
// code — is BYTE-IDENTICAL to including <arch/spectrum.h> directly.  No ZX
// behaviour changes.
//
// On a CPC target (BUILD_FEATURE_PLATFORM_CPC_*) <arch/spectrum.h> does not
// exist, so we instead provide the INK_*/PAPER_*/BRIGHT/FLASH macros as inert
// values.  Per the two-layer colour model (gfx.md §2.1 / README §5.5) the
// attribute byte these build is NEVER consumed on CPC — colour comes from the
// bitmap layer plus the per-game pen palette — so the values exist purely so
// the ZX-derived DEFAULT_BG_ATTR expression type-checks.  We mirror the ZX
// numeric values for cleanliness; the resulting byte is discarded by the CPC
// gfx backend.
//
// G8 NOTE: when the real CPC backend / asset pipeline (A5) lands, the per-game
// colour story is owned by cpc-renderer.md; these inert macros remain only as
// a source-compatibility shim for the ZX-derived attribute expression.
//

#ifndef _RAGE1_PLATFORM_H
#define _RAGE1_PLATFORM_H

#include "features.h"

#if defined( BUILD_FEATURE_PLATFORM_CPC464 ) || defined( BUILD_FEATURE_PLATFORM_CPC_FLAT )

// CPC: inert ZX colour-attribute macros (two-layer colour model — discarded
// on CPC).  Values mirror <arch/zx/spectrum.h> for parity.
#ifndef INK_BLACK
#define INK_BLACK      0x00
#define INK_BLUE       0x01
#define INK_RED        0x02
#define INK_MAGENTA    0x03
#define INK_GREEN      0x04
#define INK_CYAN       0x05
#define INK_YELLOW     0x06
#define INK_WHITE      0x07

#define PAPER_BLACK    0x00
#define PAPER_BLUE     0x08
#define PAPER_RED      0x10
#define PAPER_MAGENTA  0x18
#define PAPER_GREEN    0x20
#define PAPER_CYAN     0x28
#define PAPER_YELLOW   0x30
#define PAPER_WHITE    0x38

#define BRIGHT         0x40
#define FLASH          0x80
#endif // INK_BLACK

#else

// ZX: transparent pass-through (byte-identical to the historical direct
// include of <arch/spectrum.h>).
#include <arch/spectrum.h>

#endif

#endif // _RAGE1_PLATFORM_H

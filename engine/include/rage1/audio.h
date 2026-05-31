////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _AUDIO_H
#define _AUDIO_H

#include <stdint.h>

#include "features.h"

/////////////////////////////////////////////////////////////////////
// Unified CPC platform predicate.
//
// "Is this any CPC model?" — covers cpc464 today and cpc6128 later.
// Both audio.h and audio_cpc_ay.h key off this SAME predicate so no
// path silently misses a future model. It is the machine-identity
// umbrella (cpc464 / cpc6128), independent of the memory model
// (BUILD_FEATURE_PLATFORM_CPC_FLAT vs a future banked model).
/////////////////////////////////////////////////////////////////////
#if defined( BUILD_FEATURE_PLATFORM_CPC464 ) || \
    defined( BUILD_FEATURE_PLATFORM_CPC6128 )
    #define AUDIO_PLATFORM_IS_CPC
#endif

/////////////////////////////////////////////////////////////////////
// Generic AUDIO API (Phase AU2 of doc/multiplatform-plan/audio.md)
//
// All engine code is encouraged to use these audio_* names.  Each
// backend-specific header (audio_zx_beeper.h, audio_zx_ay.h,
// audio_cpc_ay.h) provides the backend-side declarations and the
// inline static-redirect aliases over today's beeper_* / tracker_*
// symbols (kept callable indefinitely per README §5.6).
//
// Two independent backend axes:
//
//   - Music backend (zero or one per build):
//       BUILD_FEATURE_AUDIO_MUSIC_BACKEND_ZX_AY
//       BUILD_FEATURE_AUDIO_MUSIC_BACKEND_CPC_AY
//
//   - SFX backend(s) (zero, one, or two per build):
//       BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_BEEPER
//       BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_AY
//       BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY
//
// The two ZX SFX backends can coexist (beeper SFX + AY SFX on the
// same build); CPC has only one SFX backend.
/////////////////////////////////////////////////////////////////////

// ----- ZX music backend selection -----
#ifdef BUILD_FEATURE_AUDIO_MUSIC_BACKEND_ZX_AY
    #include "rage1/audio_zx_ay.h"
#endif

// ----- ZX SFX backend selection -----
#ifdef BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_BEEPER
    #include "rage1/audio_zx_beeper.h"
#endif

#ifdef BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_AY
    // audio_sfx_tracker_t is provided by audio_zx_ay.h. When the
    // music backend is also ZX_AY, it's already included above; in
    // the SFX-only AY case (rare), pull it in here too.
    #ifndef BUILD_FEATURE_AUDIO_MUSIC_BACKEND_ZX_AY
        #include "rage1/audio_zx_ay.h"
    #endif
#endif

// ----- CPC audio backend (single include path) -----
//
// audio_cpc_ay.h is the ONE CPC-audio header (the old audio_cpc_stub.h is gone).
// It is included on EVERY CPC build — not only when a CPC AY backend macro is
// set — because the engine calls audio_sfx_beeper_*() unconditionally and the
// CPC has no beeper backend to provide those symbols. The header carries:
//   - the always-present beeper-SFX compat shims (route through CPC SFX HAL),
//   - the music ops      (gated BUILD_FEATURE_AUDIO_MUSIC_BACKEND_CPC_AY),
//   - the AY tracker SFX ops (gated BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY).
#ifdef AUDIO_PLATFORM_IS_CPC
    #include "rage1/audio_cpc_ay.h"
#endif

#endif // _AUDIO_H

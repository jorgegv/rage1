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

// ----- Music backend selection -----
#ifdef BUILD_FEATURE_AUDIO_MUSIC_BACKEND_ZX_AY
    #include "rage1/audio_zx_ay.h"
#endif

#ifdef BUILD_FEATURE_AUDIO_MUSIC_BACKEND_CPC_AY
    #include "rage1/audio_cpc_ay.h"
#endif

// ----- SFX backend selection -----
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

#ifdef BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY
    #ifndef BUILD_FEATURE_AUDIO_MUSIC_BACKEND_CPC_AY
        #include "rage1/audio_cpc_ay.h"
    #endif
#endif

#endif // _AUDIO_H

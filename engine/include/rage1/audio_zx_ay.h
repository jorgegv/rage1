////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _AUDIO_ZX_AY_H
#define _AUDIO_ZX_AY_H

// Phase AU2 (cross-platform plan, doc/multiplatform-plan/audio.md):
// ZX128 AY backend HAL header (Arkos2 or Vortex2 dispatcher).
//
// AU2-1 carves the file shape and exposes the audio_sfx_tracker_t
// type. AU2-2 fills in the inline static-redirect aliases over the
// existing tracker_* symbols. No new translation unit is
// introduced; ZX builds stay byte-identical.
//
// The old tracker_* names remain valid and supported indefinitely
// (per README §5.6 — permanent silent aliases). New code is
// encouraged to use the audio_* names; external games that still
// call tracker_* keep working forever.

#include <stdint.h>

#include "features.h"
#include "rage1/tracker.h"

// SFX index type (0 .. TRACKER_SOUNDFX_NUM_EFFECTS-1). For the
// Vortex2 backend variant, the type is present but the player
// itself does not support SFX, so audio_sfx_tracker_play /
// audio_sfx_tracker_request become no-ops at the backend level.
typedef uint8_t audio_sfx_tracker_t;

// Inline static-redirect HAL aliases are added by AU2-2.

#endif // _AUDIO_ZX_AY_H

////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _AUDIO_ZX_BEEPER_H
#define _AUDIO_ZX_BEEPER_H

// Phase AU2 (cross-platform plan, doc/multiplatform-plan/audio.md):
// ZX beeper SFX backend HAL header.
//
// AU2-1 carves the file shape and exposes the audio_sfx_beeper_t
// type. AU2-2 fills in the inline static-redirect aliases over the
// existing beeper_* symbols. No new translation unit is introduced;
// ZX builds stay byte-identical.
//
// The old beeper_* names remain valid and supported indefinitely
// (per README §5.6 — permanent silent aliases). New code is
// encouraged to use the audio_sfx_beeper_* names; external games
// that still call beeper_* keep working forever.

#include "features.h"
#include "rage1/beeper.h"

// SFX handle type: pointer to a BEEPFX byte stream (sound/bit.h).
typedef void *audio_sfx_beeper_t;

// Inline static-redirect HAL aliases are added by AU2-2.

#endif // _AUDIO_ZX_BEEPER_H

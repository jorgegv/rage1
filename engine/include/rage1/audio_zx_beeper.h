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
// memory.h must be included before beeper.h so that, on 128K builds, the
// banked-call macros (banked_function_defs.h) are visible when the inline
// alias bodies below are parsed — they must expand to banked calls, not
// direct calls to symbols that only exist inside the banked code.
#include "rage1/memory.h"
#include "rage1/beeper.h"

// SFX handle type: pointer to a BEEPFX byte stream (sound/bit.h).
typedef void *audio_sfx_beeper_t;

////////////////////////////////////////////////////////
// HAL contract — inline static-redirect aliases (AU2-2)
////////////////////////////////////////////////////////

// audio_sfx_beeper_init()
//   Initialise the beeper SFX backend.
//   Inline redirect to init_beeper().
//   init_beeper() only exists on 128K builds (on 48K the beeper state is
//   zeroed by regular BSS init), and SDCC emits static-inline bodies even
//   when unreferenced, so the alias is gated to match.
#ifdef BUILD_FEATURE_ZX_TARGET_128
static inline void audio_sfx_beeper_init( void ) {
    init_beeper();
}
#endif

// audio_sfx_beeper_request(sfx)
//   Request that a beeper FX be played at the end of the game loop.
//   Inline redirect to beeper_request_fx().
static inline void audio_sfx_beeper_request( audio_sfx_beeper_t sfx ) {
    beeper_request_fx( sfx );
}

// audio_sfx_beeper_play(sfx)
//   Play a beeper FX immediately (bypasses pending-queue).
//   Inline redirect to beeper_play_fx().
static inline void audio_sfx_beeper_play( audio_sfx_beeper_t sfx ) {
    beeper_play_fx( sfx );
}

// audio_sfx_beeper_play_pending()
//   Drain pending beeper FX requests.
//   Inline redirect to beeper_play_pending_fx().
static inline void audio_sfx_beeper_play_pending( void ) {
    beeper_play_pending_fx();
}

#endif // _AUDIO_ZX_BEEPER_H

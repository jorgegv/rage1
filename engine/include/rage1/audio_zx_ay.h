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

////////////////////////////////////////////////////////
// HAL contract — Music ops (AU2-2 inline aliases)
////////////////////////////////////////////////////////

// audio_music_select_song(song_id) — pick the active song.
static inline void audio_music_select_song( uint8_t song_id ) {
    tracker_select_song( song_id );
}

// audio_music_start() — start playback of the selected song.
static inline void audio_music_start( void ) {
    tracker_start();
}

// audio_music_stop() — stop playback.
static inline void audio_music_stop( void ) {
    tracker_stop();
}

// audio_music_rewind() — rewind the active song to the start.
static inline void audio_music_rewind( void ) {
    tracker_rewind();
}

// audio_music_tick() — ISR-time per-frame service tick.
static inline void audio_music_tick( void ) {
    tracker_do_periodic_tasks();
}

////////////////////////////////////////////////////////
// HAL contract — SFX ops (AY tracker channel)
////////////////////////////////////////////////////////

// audio_sfx_tracker_request(sfx) — queue an AY SFX for the next
// game-loop chokepoint drain. The legacy entry point takes a
// uint16_t for ABI reasons; the HAL type is uint8_t, so we widen
// at the call boundary.
static inline void audio_sfx_tracker_request( audio_sfx_tracker_t sfx ) {
    tracker_request_fx( (uint16_t)sfx );
}

// audio_sfx_tracker_play(sfx) — play an AY SFX immediately.
static inline void audio_sfx_tracker_play( audio_sfx_tracker_t sfx ) {
    tracker_play_fx( sfx );
}

// audio_sfx_tracker_play_pending() — drain queued AY SFX requests.
static inline void audio_sfx_tracker_play_pending( void ) {
    tracker_play_pending_fx();
}

#endif // _AUDIO_ZX_AY_H

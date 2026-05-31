////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _AUDIO_CPC_AY_H
#define _AUDIO_CPC_AY_H

// Phase AU4 (cross-platform plan, doc/multiplatform-plan/audio.md):
// Amstrad CPC AY audio backend HAL header — STUB.
//
// This is the CPC counterpart of audio_zx_ay.h. It carries the full HAL
// contract (music ops, AY-tracker SFX ops, and the beeper-SFX compat shims
// that the engine calls unconditionally) so the whole engine type-checks
// under +cpc. At AU4 the backend is a STUB: every op is a no-op. AU5 fills
// in the real Arkos2-on-CPC bindings (audio_cpc_ay_arkos2.c) using the same
// ply_akg_* player symbols as ZX, provided by the CPC-variant player asm.
//
// Two coexisting roles, mirroring the ZX split:
//
//   - Music backend (gated BUILD_FEATURE_AUDIO_MUSIC_BACKEND_CPC_AY):
//     audio_music_* ops + the audio_sfx_tracker_t type.
//
//   - AY SFX backend (gated BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY):
//     audio_sfx_tracker_* ops.
//
//   - Beeper-SFX compat shims (ALWAYS present on CPC): the engine calls
//     audio_sfx_beeper_*() unconditionally (game_loop.c, flow.c). On ZX those
//     resolve to the always-present beeper backend; on CPC there is no beeper,
//     so we route them through the CPC SFX HAL. At AU4 they are no-ops. This is
//     why this header is included on ALL CPC builds (see audio.h), not only
//     when a CPC AY backend macro is set.

#include <stdint.h>

#include "features.h"

// This header is the single CPC-audio include path. It must only ever be
// reached on a CPC build (audio.h gates it behind the CPC platform predicate).
#if !defined( BUILD_FEATURE_PLATFORM_CPC464 ) && \
    !defined( BUILD_FEATURE_PLATFORM_CPC6128 )
#error "audio_cpc_ay.h included on a non-CPC build — check the CPC platform gating in audio.h"
#endif

////////////////////////////////////////////////////////////////////////////////
// Beeper-SFX compat shims — ALWAYS present on CPC.
//
// The engine calls audio_sfx_beeper_*() unconditionally. The CPC has no
// beeper; these route through the CPC SFX HAL. STUB: no-ops at AU4 (AU5 maps
// them to the Arkos2 SFX channel if a CPC game ever drives beeper-style SFX,
// or they stay no-ops while the AY SFX backend handles all SFX).
////////////////////////////////////////////////////////////////////////////////

// SFX handle type (mirrors audio_zx_beeper.h: pointer to an FX byte stream).
typedef void *audio_sfx_beeper_t;

static inline void audio_sfx_beeper_init( void ) {
    // no-op (CPC stub)
}

static inline void audio_sfx_beeper_request( audio_sfx_beeper_t sfx ) {
    (void) sfx;     // no-op (CPC stub)
}

static inline void audio_sfx_beeper_play( audio_sfx_beeper_t sfx ) {
    (void) sfx;     // no-op (CPC stub)
}

static inline void audio_sfx_beeper_play_pending( void ) {
    // no-op (CPC stub)
}

////////////////////////////////////////////////////////////////////////////////
// Music ops — CPC AY music backend (Arkos2 forced on CPC; no Vortex2).
//
// Gated to match the backend macro so a CPC build with no TRACKER (e.g. the
// synthetic compile-test) does not reference these symbols. STUB: no-ops at
// AU4; AU5 redirects to the ply_akg_* / tracker_* player like the ZX path.
////////////////////////////////////////////////////////////////////////////////

#ifdef BUILD_FEATURE_AUDIO_MUSIC_BACKEND_CPC_AY

// SFX index type (0 .. TRACKER_SOUNDFX_NUM_EFFECTS-1). Same as the ZX AY
// backend so HAL callers are platform-agnostic.
#ifndef _AUDIO_SFX_TRACKER_T_DEFINED
#define _AUDIO_SFX_TRACKER_T_DEFINED
typedef uint8_t audio_sfx_tracker_t;
#endif

// audio_music_init() — initialise the CPC AY music backend.
static inline void audio_music_init( void ) {
    // no-op (CPC stub)
}

// audio_music_select_song(song_id) — pick the active song.
static inline void audio_music_select_song( uint8_t song_id ) {
    (void) song_id;     // no-op (CPC stub)
}

// audio_music_start() — start playback of the selected song.
static inline void audio_music_start( void ) {
    // no-op (CPC stub)
}

// audio_music_stop() — stop playback.
static inline void audio_music_stop( void ) {
    // no-op (CPC stub)
}

// audio_music_rewind() — rewind the active song to the start.
static inline void audio_music_rewind( void ) {
    // no-op (CPC stub)
}

// audio_music_tick() — ISR-time per-frame service tick.
static inline void audio_music_tick( void ) {
    // no-op (CPC stub)
}

#endif // BUILD_FEATURE_AUDIO_MUSIC_BACKEND_CPC_AY

////////////////////////////////////////////////////////////////////////////////
// SFX ops — CPC AY tracker channel.
//
// Gated by BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY (set when the game configures
// a TRACKER FX_CHANNEL). STUB: no-ops at AU4.
////////////////////////////////////////////////////////////////////////////////

#ifdef BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY

// The SFX-only AY case (rare) still needs the SFX index type.
#ifndef _AUDIO_SFX_TRACKER_T_DEFINED
#define _AUDIO_SFX_TRACKER_T_DEFINED
typedef uint8_t audio_sfx_tracker_t;
#endif

// audio_sfx_tracker_init() — initialise the AY SFX channel.
static inline void audio_sfx_tracker_init( void ) {
    // no-op (CPC stub)
}

// audio_sfx_tracker_request(sfx) — queue an AY SFX for the next
// game-loop chokepoint drain.
static inline void audio_sfx_tracker_request( audio_sfx_tracker_t sfx ) {
    (void) sfx;     // no-op (CPC stub)
}

// audio_sfx_tracker_play(sfx) — play an AY SFX immediately.
static inline void audio_sfx_tracker_play( audio_sfx_tracker_t sfx ) {
    (void) sfx;     // no-op (CPC stub)
}

// audio_sfx_tracker_play_pending() — drain queued AY SFX requests.
static inline void audio_sfx_tracker_play_pending( void ) {
    // no-op (CPC stub)
}

#endif // BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY

#endif // _AUDIO_CPC_AY_H

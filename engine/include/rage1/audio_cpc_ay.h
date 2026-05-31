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
// tracker.h declares the generic tracker_* orchestration layer. On CPC-flat
// (no banking) those symbols are real linkable functions provided by
// engine/src/audio_cpc_ay_arkos2.c; the music/SFX HAL ops below alias to them,
// exactly mirroring the ZX path (audio_zx_ay.h -> tracker_*).
#include "rage1/tracker.h"

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
// synthetic compile-test) does not reference these symbols. AU5: these alias
// to the generic tracker_* orchestration layer (provided on CPC-flat by
// engine/src/audio_cpc_ay_arkos2.c), exactly mirroring the ZX path.
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
    init_tracker();
}

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

// audio_music_set_volume(vol) — AU5-4. The Arkos2 AKG player exposes NO fade /
// master-volume primitive (no ply_akg_*_fade symbol exists in the shared
// player asm), so this is a documented no-op on the CPC AY (arkos2) backend.
// A macro (not a static-inline) so it emits no symbol — matching the ZX arkos2
// backend (audio_zx_ay.h).
#define audio_music_set_volume( vol )	( (void)( vol ) )

#endif // BUILD_FEATURE_AUDIO_MUSIC_BACKEND_CPC_AY

////////////////////////////////////////////////////////////////////////////////
// SFX ops — CPC AY tracker channel.
//
// Gated by BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY (set when the game configures
// a TRACKER FX_CHANNEL). AU5-3: these alias to the generic tracker_* SFX layer
// (provided on CPC-flat by engine/src/audio_cpc_ay_arkos2.c), exactly mirroring
// the ZX AY SFX path. The underlying tracker_specific_play_fx() issues
// ply_akg_playsoundeffect( id, TRACKER_SOUNDFX_CHANNEL, 16 - TRACKER_SOUNDFX_VOLUME ).
////////////////////////////////////////////////////////////////////////////////

#ifdef BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY

// The SFX-only AY case (rare) still needs the SFX index type.
#ifndef _AUDIO_SFX_TRACKER_T_DEFINED
#define _AUDIO_SFX_TRACKER_T_DEFINED
typedef uint8_t audio_sfx_tracker_t;
#endif

// audio_sfx_tracker_init() — initialise the AY SFX channel.
static inline void audio_sfx_tracker_init( void ) {
    init_tracker_sound_effects();
}

// audio_sfx_tracker_request(sfx) — queue an AY SFX for the next
// game-loop chokepoint drain. The legacy entry point takes a uint16_t for ABI
// reasons; the HAL type is uint8_t, so we widen at the call boundary.
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

#endif // BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY

#endif // _AUDIO_CPC_AY_H

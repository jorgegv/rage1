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
// Amstrad CPC AY audio backend body — STUB (Phase AU4 of
// doc/multiplatform-plan/audio.md).
//
// This is the CPC counterpart of engine/banked_code/128/audio_zx_ay_arkos2.c.
// At AU4 every backend op is empty (returns immediately): the build plays no
// sound, but every caller type-checks and (eventually) links. AU5 replaces
// these stubs with real Arkos2-on-CPC bindings calling the same ply_akg_*
// player symbols as the ZX path, provided by the CPC-variant player asm.
//
// Like gfx_cpctel.c, this TU lives in engine/src/ (compiled by every build)
// and self-#ifdefs out to an EMPTY translation unit on ZX targets — only a
// CPC build with the matching BUILD_FEATURE_AUDIO_*_BACKEND_CPC_AY macro set
// carries a body. This keeps ZX builds byte-identical.
//

#include <stdint.h>

#include "features.h"

////////////////////////////////////////////////////////////////////////////////
// CPC AY music backend — tracker_specific_* bindings (STUB).
//
// Gated by BUILD_FEATURE_AUDIO_MUSIC_BACKEND_CPC_AY. The HAL music ops in
// audio_cpc_ay.h are static-inline no-ops at AU4, so these tracker_specific_*
// bodies are not yet wired to them; they exist so the C-side backend shape
// matches the ZX Arkos2 backend (engine/banked_code/128/audio_zx_ay_arkos2.c)
// and AU5 can fill them in by copy.
////////////////////////////////////////////////////////////////////////////////

#ifdef BUILD_FEATURE_AUDIO_MUSIC_BACKEND_CPC_AY

void audio_cpc_ay_music_init( void ) {
    // no-op (CPC stub) — AU5: ply_akg_* init
}

void audio_cpc_ay_music_select_song( uint8_t song_id ) {
    (void) song_id;     // no-op (CPC stub) — AU5: ply_akg_init( all_songs[...] )
}

void audio_cpc_ay_music_start( void ) {
    // no-op (CPC stub)
}

void audio_cpc_ay_music_stop( void ) {
    // no-op (CPC stub) — AU5: ply_akg_stop()
}

void audio_cpc_ay_music_rewind( void ) {
    // no-op (CPC stub)
}

void audio_cpc_ay_music_tick( void ) {
    // no-op (CPC stub) — AU5: ply_akg_play()
}

#endif // BUILD_FEATURE_AUDIO_MUSIC_BACKEND_CPC_AY

////////////////////////////////////////////////////////////////////////////////
// CPC AY SFX backend (STUB).
//
// Gated by BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY (set when the game configures
// a TRACKER FX_CHANNEL).
////////////////////////////////////////////////////////////////////////////////

#ifdef BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY

void audio_cpc_ay_sfx_init( void ) {
    // no-op (CPC stub) — AU5: ply_akg_initsoundeffects( all_sound_effects )
}

void audio_cpc_ay_sfx_play( uint8_t effect_id ) {
    (void) effect_id;   // no-op (CPC stub) — AU5: ply_akg_playsoundeffect(...)
}

#endif // BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY

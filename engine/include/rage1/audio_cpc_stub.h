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
// Amstrad CPC audio backend — STUB (Phase G7).
//
// The CPC audio HAL proper is Phase AU4 (audio.md): datagen does not yet emit
// any BUILD_FEATURE_AUDIO_*_BACKEND_* macro for CPC, so on CPC audio.h pulls
// in NO backend header.  But a couple of audio entry points are called
// UNCONDITIONALLY from the engine (not behind a BUILD_FEATURE_AUDIO_* guard) —
// notably audio_sfx_beeper_play_pending() at engine/src/game_loop.c, and
// audio_sfx_beeper_request()/_init() on certain feature paths.  On ZX those
// resolve to the always-present beeper backend; on CPC they would be
// undefined, so the whole engine fails to compile/link under +cpc.
//
// This header provides no-op static-inline stubs for the unconditionally-used
// audio SFX entry points so the engine TYPE-CHECKS under +cpc for the G7
// gfx-stub compile-test.  It is a STUB — no real CPC sound.  AU4 replaces it
// with a real cpctelera/AY backend (audio_cpc_ay.h) and routes these call
// sites through the proper SFX HAL.
//

#ifndef _RAGE1_AUDIO_CPC_STUB_H
#define _RAGE1_AUDIO_CPC_STUB_H

#include "features.h"

// SFX handle type (mirrors audio_zx_beeper.h: pointer to an FX byte stream).
typedef void *audio_sfx_beeper_t;

// No-op SFX stubs (AU4 supplies real CPC bodies).
static inline void audio_sfx_beeper_init( void ) {
}

static inline void audio_sfx_beeper_request( audio_sfx_beeper_t sfx ) {
    (void) sfx;
}

static inline void audio_sfx_beeper_play( audio_sfx_beeper_t sfx ) {
    (void) sfx;
}

static inline void audio_sfx_beeper_play_pending( void ) {
}

#endif // _RAGE1_AUDIO_CPC_STUB_H

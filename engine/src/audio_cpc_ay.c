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
// Amstrad CPC AY audio backend body (Phase AU4/AU5 of
// doc/multiplatform-plan/audio.md).
//
// At AU4 this TU carried no-op STUB bodies (audio_cpc_ay_music_* /
// audio_cpc_ay_sfx_*). AU5 replaced them with REAL Arkos2 bindings, which now
// live in engine/src/audio_cpc_ay_arkos2.c (the CPC counterpart of the ZX
// engine/banked_code/128/audio_zx_ay_arkos2.c). The CPC audio HAL ops in
// rage1/audio_cpc_ay.h alias to the generic tracker_* orchestration layer,
// which that file provides — so the old audio_cpc_ay_music_*/sfx_* stub
// symbols are no longer referenced and have been removed.
//
// This file is intentionally left as an EMPTY translation unit: it is kept in
// place (rather than deleted) so the engine/src/*.c build glob and any external
// reference to the filename stay valid, and as a documentation anchor for the
// AU4->AU5 migration of the CPC audio backend. The always-present beeper-SFX
// compat shims live in rage1/audio_cpc_ay.h; the real Arkos2 bindings live in
// engine/src/audio_cpc_ay_arkos2.c.
//

#include "features.h"

// (empty translation unit — see header comment above)

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

// Phase AU2 stub (cross-platform plan, doc/multiplatform-plan/audio.md).
//
// The CPC AY audio backend HAL contract will be filled in by Phase AU4
// (CPC audio backend skeleton). For now this header exists only as a
// placeholder so the umbrella audio.h can include it conditionally on
// PLATFORM_CPC* without the file being missing.
//
// Per AU2 spec, this stub must trip a hard #error if it is somehow
// reached on a non-CPC build, while staying silent on ZX builds
// (which never include it because BUILD_FEATURE_AUDIO_*_BACKEND_CPC_AY
// is never defined on ZX targets).
//
// Note: BUILD_FEATURE_PLATFORM_CPC* macros do not exist yet — they
// are introduced by the CPC bring-up phases. The guard below uses
// the same naming convention as the rest of the plan so that, once
// those macros land, this stub becomes self-protecting without
// further edits. Until then, the file is only ever included on CPC
// builds (which set the AUDIO_*_BACKEND_CPC_AY macros), and ZX
// builds never reach it.

#include "features.h"

#if !defined(BUILD_FEATURE_PLATFORM_CPC464) && \
    !defined(BUILD_FEATURE_PLATFORM_CPC6128) && \
    ( defined(BUILD_FEATURE_AUDIO_MUSIC_BACKEND_CPC_AY) || \
      defined(BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY) )
#error "audio_cpc_ay.h included on a non-CPC build — check BUILD_FEATURE_AUDIO_*_BACKEND_CPC_AY gating"
#endif

// Phase AU4 will add:
//   #include "rage1/arkos2.h"     // Arkos2 forced on CPC; no Vortex2.
//   typedef uint8_t audio_sfx_tracker_t;
//   void  audio_music_select_song( uint8_t song_id );
//   void  audio_music_start( void );
//   void  audio_music_stop( void );
//   void  audio_music_rewind( void );
//   void  audio_music_tick( void );
//   void  audio_sfx_tracker_play( audio_sfx_tracker_t sfx );
//   void  audio_sfx_tracker_request( audio_sfx_tracker_t sfx );

#endif // _AUDIO_CPC_AY_H

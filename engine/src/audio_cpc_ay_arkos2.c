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
// Amstrad CPC AY audio backend body — REAL Arkos2 bindings (Phase AU5 of
// doc/multiplatform-plan/audio.md).
//
// This is the CPC counterpart of engine/banked_code/128/audio_zx_ay_arkos2.c.
// The tracker_specific_* bodies are BYTE-FOR-BYTE the same ply_akg_* calls as
// the ZX path — the only platform difference is the PSG-output hardware, which
// is selected by the CPC player wrapper (audio_cpc_ay_arkos2_player_asm.inc ->
// PLY_AKG_HARDWARE_CPC) and lives entirely in the shared player asm.
//
// On ZX (128K) the generic tracker_* orchestration layer lives in the banked
// translation unit engine/banked_code/128/audio_zx_ay.c. On CPC-flat there is
// no banking, so this single TU carries BOTH the generic tracker_* orchestration
// AND the Arkos2 tracker_specific_* bindings.
//
// Like gfx_cpctel.c / audio_cpc_ay.c, this TU lives in engine/src/ (compiled by
// every build) and self-#ifdefs out to an EMPTY translation unit unless the CPC
// AY music backend is selected — so ZX builds stay byte-identical.
//

#include <stdint.h>

#include "features.h"

#ifdef BUILD_FEATURE_AUDIO_MUSIC_BACKEND_CPC_AY

#include "rage1/tracker.h"
#include "rage1/arkos2.h"
#include "rage1/game_state.h"

#include "game_data.h"

////////////////////////////////////////////////////////////////////////////////
// AU5-2.1: cold-boot PSG silence.
//
// On a cold CPC boot the PSG is in an undefined state and can leak white-noise
// / tone before the first song is selected. audio_music_init() (below) zeroes
// R7 (mixer: all tone+noise OFF when all bits set... actually R7=0 enables all
// channels) — see the note — and the amplitude registers R8/R9/R10 plus the
// envelope registers R11/R12/R13, so the PSG is silent until a song drives it.
//
// We write the registers through the 8255 PPI exactly like the AT2 player
// PLY_AKG_SENDPSGREGISTERS routine: port A (0xF4xx) = data, port C (0xF6xx) =
// PSG control function (0xF6C0 select-register via the Madram trick to avoid
// the tape relay, 0xF680 write-data, 0xF600 inactive).
//
// NOTE on R7 (mixer): the AY mixer bits are ACTIVE-LOW (bit set = channel
// muted). The intent of AU5-2.1 is no leakage. With the amplitude registers
// R8/R9/R10 forced to 0 the channels are silent regardless of the mixer, so
// the exact R7 value is not load-bearing for silence; we write 0 to all of
// R7..R13 as the spec asks, matching a known, defined PSG state.
//
// cpc_ay_write_reg( reg, value ): write one AY register via the PPI.
// (No apostrophes/quotes in the inline-asm comments below: the SDCC C
//  pre-processor scans __asm blocks and an apostrophe would be read as an
//  unterminated character constant.)
////////////////////////////////////////////////////////////////////////////////

#pragma disable_warning 85      // unreferenced function argument (params used in asm)

// cpc_ay_write_reg( reg, value ): write one AY register via the PPI.
//
// ABI: SDCC + __z88dk_callee PACKS the two uint8_t arguments into a SINGLE
// 16-bit stack word (it does NOT push two separate words): the first arg (reg)
// in the LOW byte (E) and the second arg (value) in the HIGH byte (D). So on
// entry the stack is: SP -> retaddr, then ONE word (E=reg, D=value). The callee
// (us) pops exactly that one arg word plus the return address. Popping a second
// word — as a naive "one stack word per argument" translation would — corrupts
// the stack and crashes on ret (verified against the SDCC .lis codegen, which
// emits a single `ld e,reg / ld d,value / push de` per call).
void cpc_ay_write_reg( uint8_t reg, uint8_t value ) __z88dk_callee __naked {
__asm
    pop  hl                 ; HL = retaddr
    pop  de                 ; E = reg, D = value  (single packed arg word)
    push hl                 ; restore retaddr
    ld   l,e                ; L = reg
    ld   h,d                ; H = value

    ;; select register L on the PSG (PPI port A = 0xF4, function via port C)
    ld   bc,0xf680          ; B=0xF6 (port C), C=0x80 (write-data, scratch)
    ld   e,0xc0
    out  (c),e              ; 0xF6C0 select-register (Madram trick, no relay)
    ld   b,0xf4
    out  (c),l              ; 0xF400 + register number
    ld   b,0xf6
    out  (c),c              ; 0xF680 latch the register number
    out  (c),e              ; 0xF6C0 back to select state

    ;; write value H to the selected register
    ld   b,0xf6
    out  (c),e              ; 0xF6C0 ensure select state
    ld   b,0xf4
    out  (c),h              ; 0xF400 + value
    ld   b,0xf6
    out  (c),c              ; 0xF680 write-data, commit the value
    out  (c),e              ; 0xF6C0 back to inactive
    ret
__endasm;
}

////////////////////////////////////////////////////////////////////////////////
// Generic tracker_* orchestration (CPC-flat copy of the platform-neutral body
// in engine/banked_code/128/audio_zx_ay.c). Drives muted / current_song state
// on top of the tracker_specific_* bindings below.
////////////////////////////////////////////////////////////////////////////////

// muted flag - if 1, sound does not play
uint8_t muted;
uint8_t current_song = 255;	// invalid song

void init_tracker( void ) {
    tracker_specific_init();
    // tracker-independent initialization: sound muted, first song active
    muted = 1;
    tracker_select_song( 0 );
}

void tracker_select_song( uint8_t song_id ) {
    // do nothing if the required song is already the current one
    if ( current_song == song_id )
        return;
    current_song = song_id;

    uint8_t was_muted = muted;
    tracker_stop();
    tracker_specific_select_song( song_id );
    if ( ! was_muted )
        tracker_start();
}

void tracker_start( void ) {
    muted = 0;
    tracker_specific_start();
}

void tracker_stop( void ) {
    muted = 1;
    tracker_specific_stop();
}

void tracker_rewind( void ) {
    uint8_t was_muted = muted;
    tracker_stop();
    tracker_specific_rewind();
    if ( ! was_muted )
        tracker_start();
}

void tracker_do_periodic_tasks( void ) {
    // return immediately if we are muted
    if ( muted ) return;
    tracker_specific_do_periodic_tasks();
}

////////////////////////////////////////////////////////////////////////////////
// Arkos2 tracker_specific_* bindings — IDENTICAL ply_akg_* calls to the ZX
// path (engine/banked_code/128/audio_zx_ay_arkos2.c). The platform-specific
// player asm (CPC variant) provides these symbols.
////////////////////////////////////////////////////////////////////////////////

void tracker_specific_init( void ) {
    // AU5-2.1: silence the PSG on cold boot before any song selection.
    // Zero the mixer/amplitude/envelope registers R7..R13.
    cpc_ay_write_reg(  7, 0 );      // mixer
    cpc_ay_write_reg(  8, 0 );      // amplitude A
    cpc_ay_write_reg(  9, 0 );      // amplitude B
    cpc_ay_write_reg( 10, 0 );      // amplitude C
    cpc_ay_write_reg( 11, 0 );      // envelope period (fine)
    cpc_ay_write_reg( 12, 0 );      // envelope period (coarse)
    cpc_ay_write_reg( 13, 0 );      // envelope shape
}

void tracker_specific_select_song( uint8_t song_id ) {
    ply_akg_init( all_songs[ song_id ], DEFAULT_SUBSONG );
}

void tracker_specific_start( void ) {
    // no special code for Arkos2
}

void tracker_specific_stop( void ) {
    ply_akg_stop();
}

void tracker_specific_rewind( void ) {
    ply_akg_init( all_songs[ current_song ], DEFAULT_SUBSONG );
}

void tracker_specific_do_periodic_tasks( void ) {
    // must be called with ints disabled!
    // if called from ISR, no need for EI/DI pair!
    ply_akg_play();
}

#ifdef BUILD_FEATURE_AUDIO_SFX_TRACKER

/////////////////////////////////////
// Tracker sound effects functions
/////////////////////////////////////

// Generic SFX orchestration (CPC-flat copy of audio_zx_ay.c).

void init_tracker_sound_effects( void ) {
    tracker_specific_init_sound_effects();
}

void tracker_play_fx( uint8_t effect_id ) {
    tracker_specific_play_fx( effect_id );
}

void tracker_play_pending_fx( void ) {
    tracker_specific_play_fx( game_state.tracker_fx );
}

void tracker_request_fx( uint16_t fxid ) {
    game_state.tracker_fx = fxid;
    SET_LOOP_FLAG( F_LOOP_PLAY_TRACKER_FX );
}

// Arkos2 SFX bindings — identical ply_akg_* calls to the ZX path.

void tracker_specific_init_sound_effects( void ) {
    ply_akg_initsoundeffects( all_sound_effects );
}

void tracker_specific_play_fx( uint8_t effect_id ) {
    // ignore if invalid effect id > TRACKER_SOUNDFX_NUM_EFFECTS (NOT zero-based!)
    if ( ( ! effect_id ) || ( effect_id > TRACKER_SOUNDFX_NUM_EFFECTS ) )
        return;
    // volume in arkos fx player is inverted: 0 -> max, 16 -> mute
    ply_akg_playsoundeffect( effect_id, TRACKER_SOUNDFX_CHANNEL, 16 - TRACKER_SOUNDFX_VOLUME );
}

#endif // BUILD_FEATURE_AUDIO_SFX_TRACKER

////////////////////////////////////////////////////////////////////////////////
// Include the asm player (CPC variant). The wrapper sets PLY_AKG_HARDWARE_CPC
// and pulls in the shared C stubs + the shared player asm. Gated the same way
// as the ZX path (BUILD_FEATURE_AUDIO_SFX_TRACKER guards the stubs that expose
// the sound-effect entry points); on a music-only CPC build the stubs/player
// are still required, so the include is OUTSIDE the SFX guard (unlike the ZX
// file, whose 128K banking layout placed it inside). The player asm has no SFX
// dependency at assembly time.
////////////////////////////////////////////////////////////////////////////////

void cpc_arkos2_wrapper( void ) __naked {
__asm
    include "engine/banked_code/audio/audio_cpc_ay_arkos2_player_asm.inc"
__endasm;
}

#endif // BUILD_FEATURE_AUDIO_MUSIC_BACKEND_CPC_AY

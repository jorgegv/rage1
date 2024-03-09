////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _BMFX_H
#define _BMFX_H

#include <stdint.h>

// all BMFX ticks are the same short duration
#define BMFX_TICK_DURATION_MS	2

// maximum number of BMFX sound effects playing simultaneously
#define BMFX_NUM_CHANNELS	3

// a BMFX beep is a given tone, played during a number of ticks
// tone = 0xff -> silence
struct bmfx_beep_s {
    uint8_t tone;
    uint8_t duration_ticks;
};

// a BMFX sound effect is a table of beeps
struct bmfx_sound_effect_s {
    uint8_t num_beeps;
    struct bmfx_beep_s *beep;
};
// the global table with all BMFX sound effects
extern struct bmfx_sound_effect_s bmfx_all_effects[];

// a channel identifies the current fx playing in that channel and its state
struct bmfx_channel_s {
    uint8_t fx_id;
    uint8_t current_beep;
    uint8_t current_beep_ticks;
    struct {
        int active:1;
    } flags;
};

// a structure for the table of active channels
struct active_channels_table_s {
    uint8_t num_active_channels;
    struct bmfx_channel_s *channel_state;
};

// the global table of BMFX channel state
extern struct active_channels_table bmfx_all_channels;

// BMFX initialization
void init_bmfx_sound_effects( void );

// requests that a FX start to be played immediately on the first available channel
void bmfx_request_fx( uint8_t fx_id );

// must be called periodically to keep the BMFX effects playing. Can be called from ISR
void bmfx_play_ticks( void );

#endif // _BMFX_H

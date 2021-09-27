////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _DATASET_H
#define _DATASET_H

#include <stdint.h>

#include "rage1/btile.h"
#include "rage1/sprite.h"
#include "rage1/flow.h"
#include "rage1/map.h"

// Banking settings
#define BANKED_DATASET_BASE_ADDRESS     0x5B00

// The following structure contains pointers to asset tables.  It is
// intended to be generated as the first element in a dataset_N.c file, so
// that it is the first structure in the generated binary.

// If done this way, the structure is located at a predefined known address
// and can be used as the only entry point to access all the assets on the
// same bank (which is what we want)

struct dataset_assets_s {
    // BTiles
    uint8_t				num_btiles;
    struct btile_s			*all_btiles;
    // Sprites
    uint8_t				num_sprite_graphics;
    struct sprite_graphic_data_s	*all_sprite_graphics;
    // Flow rules
    // FIXME: this needs to be upgraded to a 16 bit number - we can easily have more than 255 rules in a game
    uint8_t				num_flow_rules;
    struct flow_rule_s			*all_flow_rules;
    // Map
    uint8_t				num_screens;
    struct map_screen_s			*all_screens;
};

// Global structs that hold the current banked and home asset tables.  They
// must go in low memory, so they are included in lowmem/asmdata.asm
extern struct dataset_assets_s *banked_assets;
extern struct dataset_assets_s *home_assets;

// structure mapping dataset -> (bank number, size, offset) for a given
// dataset
struct dataset_info_s {
    uint8_t	bank_num;	// bank number
    uint16_t	size;		// dataset size
    uint16_t	offset;		// address offset from 0xC000
};

// dataset->bank map structure autogenerated by r1banktool
extern struct dataset_info_s dataset_info[];

// dataset initialization at program start
void init_datasets( void );

// activate a given dataset
void dataset_activate( uint8_t d );

///////////////////////////////////////////////////////
//
// Functions for optimizing access to banked assets
//
///////////////////////////////////////////////////////

// get ptr to the current screen
struct map_screen_s *dataset_get_current_screen_ptr( void );

// get ptr to a given sprite graphic in the home and banked datasets
struct sprite_graphic_data_s *dataset_get_home_sprite_graphic_ptr( uint8_t id);
struct sprite_graphic_data_s *dataset_get_banked_sprite_graphic_ptr( uint8_t id);

#endif // _DATASET_H

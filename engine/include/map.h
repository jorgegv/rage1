////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _MAP_H
#define _MAP_H

#include <stddef.h>
#include <games/sp1.h>
#include <stdint.h>

#include "btile.h"
#include "inventory.h"
#include "hotzone.h"

// Screen functions and definitions
// A screen has a set of btiles , a set of sprites and some hero data
// The btile data is used when drawing the screen
// The sprite data is updated  in the global game state when changing screen

// struct describing a screen
struct map_screen_s {
    struct {
        uint8_t num_btiles;
        struct btile_pos_s *btiles_pos;
    } btile_data;
    struct { 
        uint8_t num_sprites; 
        struct sprite_info_s *sprites;
    } sprite_data;
    struct {
        uint8_t	startup_x,startup_y;
    } hero_data;
    struct {
        uint8_t num_items;
        struct item_location_s *items;
    } item_data;
    struct {
        uint8_t num_hotzones;
        struct hotzone_info_s *hotzones;
    } hotzone_data;
};

// with a generic function to draw a screen passed by pointer we can
// later modify the logic behind maps without touching the map display
// code
void map_draw_screen(struct map_screen_s *s);
uint8_t map_get_item_at_position( struct map_screen_s *s, uint8_t row, uint8_t col );
void map_sprites_reset_all(void);
uint16_t map_count_enemies_all(void);

// utility macros and definitions

#endif // _MAP_H

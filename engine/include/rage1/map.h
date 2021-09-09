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

#include "rage1/btile.h"
#include "rage1/inventory.h"
#include "rage1/hotzone.h"
#include "rage1/flow.h"
#include "rage1/enemy.h"

// Screen functions and definitions
// A screen has a set of btiles , a set of sprites and some hero data
// The btile data is used when drawing the screen
// The sprite data is updated  in the global game state when changing screen

// struct describing a screen
struct map_screen_s {
    // data
    struct {
        uint8_t num_btiles;
        struct btile_pos_s *btiles_pos;
    } btile_data;
    struct { 
        uint8_t num_enemies; 
        struct enemy_info_s *enemies;
    } enemy_data;
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
    struct {
        struct {
            struct flow_rule_table_s enter_screen;
            struct flow_rule_table_s exit_screen;
            struct flow_rule_table_s game_loop;
        } rule_tables;
    } flow_data;
    struct {
        uint8_t btile_num;
        uint8_t probability;
        struct sp1_Rect box;
    } background_data;
    struct {
        uint16_t flags;
    } state_data;
};

// struct for mapping a screen in the global map to a screen in a given dataset
// the index for this array is the global screen number
struct screen_dataset_map_s {
    uint8_t	dataset_num;
    uint8_t	dataset_screen_num;
};
extern struct screen_dataset_map_s screen_dataset_map[];

// with a generic function to draw a screen passed by pointer we can
// later modify the logic behind maps without touching the map display
// code
void map_draw_screen(struct map_screen_s *s);
struct item_location_s *map_get_item_location_at_position( struct map_screen_s *s, uint8_t row, uint8_t col );
void map_sprites_reset_all(void);
uint16_t map_count_enemies_all(void);
void map_enter_screen( struct map_screen_s *s );
void map_exit_screen( struct map_screen_s *s );
void map_allocate_sprites( struct map_screen_s *m );
void map_free_sprites( struct map_screen_s *s );

// utility macros and definitions
// screen flags macros and definitions
#define GET_SCREEN_FLAG(s,f)	( (s).state_data.flags & (f) )
#define SET_SCREEN_FLAG(s,f)	( (s).state_data.flags |= (f) )
#define RESET_SCREEN_FLAG(s,f)	( (s).state_data.flags &= ~(f) )

#endif // _MAP_H

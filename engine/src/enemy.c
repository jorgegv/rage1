////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include "rage1/game_state.h"
#include "rage1/sprite.h"
#include "rage1/enemy.h"
#include "rage1/screen.h"
#include "rage1/map.h"
#include "rage1/debug.h"
#include "rage1/util.h"

#include "game_data.h"

void enemy_reset_position_all( uint8_t num_enemies, struct enemy_info_s *enemies ) {
    static struct enemy_info_s *e;
    static struct sprite_graphic_data_s *g;
    static uint8_t n;

    n = num_enemies;
    while( n-- ) {
        e = &enemies[n];		// eficiency matters ;-)
        if ( ! IS_ENEMY_ACTIVE(*e) )	// skip if not active
            continue;

        g = &all_sprite_graphics[ e->num_graphic ];

        // reset enemy state to initial values - update xmax and ymax also
        e->animation.current.sequence_counter = e->animation.current.frame_delay_counter = 0;
        e->position.x = e->movement.data.linear.initx;
        e->position.y = e->movement.data.linear.inity;
        e->movement.data.linear.dx = e->movement.data.linear.initdx;
        e->movement.data.linear.dy = e->movement.data.linear.initdy;

        // adjust xmax, ymax and move enemy to initial position
        e->position.xmax = e->position.x + g->width - 1;
        e->position.ymax = e->position.y + g->height - 1;
        sp1_MoveSprPix( e->sprite, &game_area, g->frame_data.frames[0], e->position.x, e->position.y );
    }
}

void enemy_animate_and_move_all( uint8_t num_enemies, struct enemy_info_s *enemies ) {
    static struct enemy_info_s *e;
    static struct sprite_animation_data_s *anim;
    static struct position_data_s *pos;
    static struct enemy_movement_data_s *move;
    static struct sprite_graphic_data_s *g;
    static uint8_t n;

    n = num_enemies;
    while( n-- ) {
        e = &enemies[n];		// efficiency matters ;-)
        if ( ! IS_ENEMY_ACTIVE(*e) )	// skip if not active
            continue;

        g = &all_sprite_graphics[ e->num_graphic ];

        // animate sprite
        anim = &e->animation;
        if ( ++anim->current.frame_delay_counter == anim->delay_data.frame_delay ) {
            anim->current.frame_delay_counter = 0;
            if ( ++anim->current.sequence_counter == g->sequence_data.sequences[ anim->current.sequence ].num_elements ) {
                anim->current.sequence_counter = 0;
            }
        }

        // set new sprite position according to movement rules
        pos = &e->position;
        move = &e->movement;
        switch ( move->type ) {
            case ENEMY_MOVE_LINEAR:
                if ( ++move->delay_counter == move->delay ) {
                    move->delay_counter = 0;
                    pos->x += move->data.linear.dx;
                    if (
                            ( pos->x >= move->data.linear.xmax ) ||
                            ( pos->x <= move->data.linear.xmin ) ||
                            ( ENEMY_MUST_BOUNCE(*e) && (
                                ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y ), PIXEL_TO_CELL_COORD( pos->x + g->width ) ) == TT_OBSTACLE ) ||
                                ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y ), PIXEL_TO_CELL_COORD( pos->x - 1 ) ) == TT_OBSTACLE ) ||
                                ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y + g->height - 1), PIXEL_TO_CELL_COORD( pos->x + g->width ) ) == TT_OBSTACLE ) ||
                                ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y + g->height - 1), PIXEL_TO_CELL_COORD( pos->x - 1 ) ) == TT_OBSTACLE )
                            ) )
                        ) { // then
                        move->data.linear.dx = -move->data.linear.dx;
                    }
                    pos->y += move->data.linear.dy;
                    if (
                            ( pos->y >= move->data.linear.ymax ) ||
                            ( pos->y <= move->data.linear.ymin ) ||
                            ( ENEMY_MUST_BOUNCE(*e) && (
                                ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y + g->height ), PIXEL_TO_CELL_COORD( pos->x ) ) == TT_OBSTACLE ) ||
                                ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y - 1 ), PIXEL_TO_CELL_COORD( pos->x ) ) == TT_OBSTACLE ) ||
                                ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y + g->height ), PIXEL_TO_CELL_COORD( pos->x + g->width - 1) ) == TT_OBSTACLE ) ||
                                ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y - 1), PIXEL_TO_CELL_COORD( pos->x + g->width - 1 ) ) == TT_OBSTACLE )
                            ) )
                        ) { // then
                        move->data.linear.dy = -move->data.linear.dy;
                    }
                }
                break;
            default:
                break;
        }

        // adjust xmax, ymax and move sprite to new position
        pos->xmax = pos->x + g->width - 1;
        pos->ymax = pos->y + g->height - 1;
        sp1_MoveSprPix( e->sprite, &game_area,
            g->frame_data.frames[ g->sequence_data.sequences[ anim->current.sequence ].frame_numbers[ anim->current.sequence_counter ] ],
            pos->x, pos->y );
    }
}

void enemy_move_offscreen_all( uint8_t num_enemies, struct enemy_info_s *enemies ) {
    static uint8_t i;
    i = num_enemies;
    while ( i-- ) sprite_move_offscreen( enemies[i].sprite );
}


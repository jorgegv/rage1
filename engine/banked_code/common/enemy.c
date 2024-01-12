////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include "features.h"

#include "rage1/game_state.h"
#include "rage1/sprite.h"
#include "rage1/enemy.h"
#include "rage1/screen.h"
#include "rage1/map.h"
#include "rage1/debug.h"
#include "rage1/util.h"
#include "rage1/dataset.h"
#include "rage1/animation.h"

#include "game_data.h"

#include "rage1/banked.h"

void enemy_animate_and_move( uint8_t num_enemies, struct enemy_info_s *enemies ) {
    struct enemy_info_s *e;
    struct animation_data_s *anim;
    struct position_data_s *pos;
    struct enemy_movement_data_s *move;
    struct sprite_graphic_data_s *g;
    uint8_t n;

    n = num_enemies;
    while( n-- ) {
        e = &enemies[n];		// efficiency matters ;-)
        if ( ! IS_ENEMY_ACTIVE( game_state.current_screen_asset_state_table_ptr[ e->state_index ].asset_state ) )	// skip if not active
            continue;

        g = dataset_get_banked_sprite_ptr( e->num_graphic );
        anim = &e->animation;

        // Sprite may need update either because of animation, movement, or
        // both.  We only set F_ENEMY_NEEDS_REDRAW if it really needs it -
        // there are lots of cases where we are just waiting!

        // animate sprite

        // optimization: only animate if the sprite has frames > 1; quickly skip if not
        if ( g->frame_data.num_frames > 1 )
            // animation_sequence_tick returns tryu if the frame has changed, 0 otherwise
            // so only update the sprite if frame has changed
            if ( animation_sequence_tick( anim, g->sequence_data.sequences[ anim->current.sequence ].num_frames ) )
                SET_ENEMY_FLAG( game_state.current_screen_asset_state_table_ptr[ e->state_index ].asset_state, F_ENEMY_NEEDS_REDRAW );

        // set new sprite position according to movement rules
        pos = &e->position;
        move = &e->movement;
        switch ( move->type ) {
            case ENEMY_MOVE_LINEAR:
                // optimization: only do the move if dx or dy are != 0
                if ( move->data.linear.dx || move->data.linear.dy ) {
                    if ( ++move->delay_counter == move->delay ) {
                        move->delay_counter = 0;

                        // optimization: only calculate horizontal movement if dx != 0
                        if ( move->data.linear.dx ) {
                            pos->x.part.integer += move->data.linear.dx;
                            pos->xmax = pos->x.part.integer + g->width - 1;
                            if (
                                    ( pos->x.part.integer >= move->data.linear.xmax ) ||
                                    ( pos->x.part.integer <= move->data.linear.xmin ) ||
                                    ( ENEMY_MOVE_MUST_BOUNCE( *move ) && (
                                        ( GET_TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y.part.integer ), PIXEL_TO_CELL_COORD( pos->x.part.integer + g->width ) ) == TT_OBSTACLE ) ||
                                        ( GET_TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y.part.integer ), PIXEL_TO_CELL_COORD( pos->x.part.integer - 1 ) ) == TT_OBSTACLE ) ||
                                        ( GET_TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y.part.integer + g->height - 1), PIXEL_TO_CELL_COORD( pos->x.part.integer + g->width ) ) == TT_OBSTACLE ) ||
                                        ( GET_TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y.part.integer + g->height - 1), PIXEL_TO_CELL_COORD( pos->x.part.integer - 1 ) ) == TT_OBSTACLE )
                                    ) )
                                ) { // then
                                move->data.linear.dx = -move->data.linear.dx;
                                // adjust animation sequence if the enemy is configured for it
                                // sequence_a if dx > 0, sequence_b if dx < 0
                                if ( ENEMY_MOVE_CHANGES_SEQUENCE_HORIZ( *move ) ) {
                                    animation_set_sequence( anim, 
                                        move->data.linear.dx > 0 ?
                                        move->data.linear.sequence_a :
                                        move->data.linear.sequence_b
                                    );
                                }
                            }
                            SET_ENEMY_FLAG( game_state.current_screen_asset_state_table_ptr[ e->state_index ].asset_state, F_ENEMY_NEEDS_REDRAW );
                        }

                        // optimization: only calculate vertical movement if dy != 0
                        if ( move->data.linear.dy ) {
                            pos->y.part.integer += move->data.linear.dy;
                            pos->ymax = pos->y.part.integer + g->height - 1;
                            if (
                                    ( pos->y.part.integer >= move->data.linear.ymax ) ||
                                    ( pos->y.part.integer <= move->data.linear.ymin ) ||
                                    ( ENEMY_MOVE_MUST_BOUNCE( *move ) && (
                                        ( GET_TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y.part.integer + g->height ), PIXEL_TO_CELL_COORD( pos->x.part.integer ) ) == TT_OBSTACLE ) ||
                                        ( GET_TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y.part.integer - 1 ), PIXEL_TO_CELL_COORD( pos->x.part.integer ) ) == TT_OBSTACLE ) ||
                                        ( GET_TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y.part.integer + g->height ), PIXEL_TO_CELL_COORD( pos->x.part.integer + g->width - 1) ) == TT_OBSTACLE ) ||
                                        ( GET_TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y.part.integer - 1), PIXEL_TO_CELL_COORD( pos->x.part.integer + g->width - 1 ) ) == TT_OBSTACLE )
                                    ) )
                                ) { // then
                                move->data.linear.dy = -move->data.linear.dy;
                                // adjust animation sequence if the enemy is configured for it
                                // sequence_a if dy > 0, sequence_b if dy < 0
                                if ( ENEMY_MOVE_CHANGES_SEQUENCE_VERT( *move ) ) {
                                    animation_set_sequence( anim, 
                                        move->data.linear.dy > 0 ?
                                        move->data.linear.sequence_a :
                                        move->data.linear.sequence_b
                                    );
                                }
                            SET_ENEMY_FLAG( game_state.current_screen_asset_state_table_ptr[ e->state_index ].asset_state, F_ENEMY_NEEDS_REDRAW );
                            }
                        }
                    }
                }
                break;
            default:
                break;
        }
    }
}

void enemy_animate_and_move_all( void ) {
    enemy_animate_and_move(
        game_state.current_screen_ptr->enemy_data.num_enemies, 
        game_state.current_screen_ptr->enemy_data.enemies
    );
}


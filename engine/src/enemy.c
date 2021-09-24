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
    struct enemy_info_s *e;
    struct sprite_graphic_data_s *g;
    uint8_t n;

    n = num_enemies;
    while( n-- ) {
        e = &enemies[n];		// eficiency matters ;-)
        if ( ! IS_ENEMY_ACTIVE( all_screen_asset_state_tables[ game_state.current_screen ][ e->state_index ].asset_state ) )	// skip if not active
            continue;

        g = &banked_assets->all_sprite_graphics[ e->num_graphic ];

        // reset enemy state to initial values

        // animation
        // e->animation.current.sequence is already assigned at data definition
        e->animation.current.sequence_counter = 0;					// initial frame index
        e->animation.current.frame_delay_counter = e->animation.delay_data.frame_delay;	// initial frame delay counter
        e->animation.current.sequence_delay_counter = 0;				// initial sequence delay counter
        // position - update also xmax and ymax
        e->position.x = e->movement.data.linear.initx;
        e->position.y = e->movement.data.linear.inity;
        e->position.xmax = e->position.x + g->width - 1;
        e->position.ymax = e->position.y + g->height - 1;
        // movement
        e->movement.data.linear.dx = e->movement.data.linear.initdx;
        e->movement.data.linear.dy = e->movement.data.linear.initdy;

        // move enemy to initial position
        sp1_MoveSprPix( e->sprite, &game_area, g->frame_data.frames[0], e->position.x, e->position.y );
    }
}

void enemy_animate_and_move_all( uint8_t num_enemies, struct enemy_info_s *enemies ) {
    struct enemy_info_s *e;
    struct sprite_animation_data_s *anim;
    struct position_data_s *pos;
    struct enemy_movement_data_s *move;
    struct sprite_graphic_data_s *g;
    uint8_t n;

    n = num_enemies;
    while( n-- ) {
        e = &enemies[n];		// efficiency matters ;-)
        if ( ! IS_ENEMY_ACTIVE( all_screen_asset_state_tables[ game_state.current_screen ][ e->state_index ].asset_state ) )	// skip if not active
            continue;

        g = &banked_assets->all_sprite_graphics[ e->num_graphic ];

        // animate sprite
        // animation can be in 2 states: animating frames or waiting for the next sequence run
        // logic: if sequence_delay_counter is 0, we are animating frames, so do the frame_delay_counter logic
        // if it is != 0, we are waiting to the next sequence run, so do the sequence_delay_counter logic
        // the animation is constantly switching from counting with sequence_delay_counter to counting with frame_delay_counter and back
        anim = &e->animation;

        // optimization: only animate if the sprite has frames > 1; quickly skip if not
        if ( g->frame_data.num_frames > 1 ) {
            if ( anim->current.sequence_delay_counter ) {
                // sequence_delay_counter is active, animation is waiting for next cycle
                if ( ! --anim->current.sequence_delay_counter ) {
                    // if it reaches 0, we have finished the wait period, so
                    // reload the frame_delay_counter so that on the next
                    // iteration we do the frame animation logic, and reset
                    // animation to initial frame index
                    anim->current.frame_delay_counter = anim->delay_data.frame_delay;
                    anim->current.sequence_counter = 0;
                }
            } else {
                // sequence_delay_counter is 0, so frame_delay_counter must be
                // active, animation is animating frames
                if ( ! --anim->current.frame_delay_counter ) {
                    // if it reaches 0, we have finished wait period between
                    // animation frames, get next frame if possible

                    // reload frame_delay_counter.  sequence_counter holds the
                    // current frame index into the sequence
                    anim->current.frame_delay_counter = anim->delay_data.frame_delay;

                    // check for the next frame
                    if ( ++anim->current.sequence_counter == g->sequence_data.sequences[ anim->current.sequence ].num_elements ) {
                        // there were no more frames, so restart sequence and go to sequence_delay loop
                        anim->current.sequence_delay_counter = anim->delay_data.sequence_delay;
                        anim->current.sequence_counter = 0;	// initial frame index
                    }
                }
            }
        }

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
                            pos->x += move->data.linear.dx;
                            pos->xmax = pos->x + g->width - 1;
                            if (
                                    ( pos->x >= move->data.linear.xmax ) ||
                                    ( pos->x <= move->data.linear.xmin ) ||
                                    ( ENEMY_MOVE_MUST_BOUNCE( *move ) && (
                                        ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y ), PIXEL_TO_CELL_COORD( pos->x + g->width ) ) == TT_OBSTACLE ) ||
                                        ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y ), PIXEL_TO_CELL_COORD( pos->x - 1 ) ) == TT_OBSTACLE ) ||
                                        ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y + g->height - 1), PIXEL_TO_CELL_COORD( pos->x + g->width ) ) == TT_OBSTACLE ) ||
                                        ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y + g->height - 1), PIXEL_TO_CELL_COORD( pos->x - 1 ) ) == TT_OBSTACLE )
                                    ) )
                                ) { // then
                                move->data.linear.dx = -move->data.linear.dx;
                                // adjust animation sequence if the enemy is configured for it
                                // sequence_a if dx > 0, sequence_b if dx < 0
                                if ( ENEMY_MOVE_CHANGES_SEQUENCE_HORIZ( *move ) ) {
                                    anim->current.sequence = ( move->data.linear.dx > 0 ?
                                        move->data.linear.sequence_a :
                                        move->data.linear.sequence_b );
                                    // always reset the sequence frame index
                                    anim->current.sequence_counter = 0;
                                }
                            }
                        }

                        // optimization: only calculate vertical movement if dy != 0
                        if ( move->data.linear.dy ) {
                            pos->y += move->data.linear.dy;
                            pos->ymax = pos->y + g->height - 1;
                            if (
                                    ( pos->y >= move->data.linear.ymax ) ||
                                    ( pos->y <= move->data.linear.ymin ) ||
                                    ( ENEMY_MOVE_MUST_BOUNCE( *move ) && (
                                        ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y + g->height ), PIXEL_TO_CELL_COORD( pos->x ) ) == TT_OBSTACLE ) ||
                                        ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y - 1 ), PIXEL_TO_CELL_COORD( pos->x ) ) == TT_OBSTACLE ) ||
                                        ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y + g->height ), PIXEL_TO_CELL_COORD( pos->x + g->width - 1) ) == TT_OBSTACLE ) ||
                                        ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y - 1), PIXEL_TO_CELL_COORD( pos->x + g->width - 1 ) ) == TT_OBSTACLE )
                                    ) )
                                ) { // then
                                move->data.linear.dy = -move->data.linear.dy;
                                // adjust animation sequence if the enemy is configured for it
                                // sequence_a if dy > 0, sequence_b if dy < 0
                                if ( ENEMY_MOVE_CHANGES_SEQUENCE_VERT( *move ) ) {
                                    anim->current.sequence = ( move->data.linear.dy > 0 ?
                                        move->data.linear.sequence_a :
                                        move->data.linear.sequence_b );
                                    // always reset the sequence frame index
                                    anim->current.sequence_counter = 0;
                                }
                            }
                        }
                    }
                }
                break;
            default:
                break;
        }

        // move/animate sprite into new position
        // sprite may need update either because of animation, movement, or both
        sp1_MoveSprPix( e->sprite, &game_area,
            g->frame_data.frames[ g->sequence_data.sequences[ anim->current.sequence ].frame_numbers[ anim->current.sequence_counter ] ],
            pos->x, pos->y );
    }
}

void enemy_move_offscreen_all( uint8_t num_enemies, struct enemy_info_s *enemies ) {
    uint8_t i;
    i = num_enemies;
    while ( i-- ) sprite_move_offscreen( enemies[i].sprite );
}


////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

// hero.c

#include <games/sp1.h>
#include <input.h>
#include <arch/spectrum.h>

#include "rage1/hero.h"
#include "rage1/game_state.h"
#include "rage1/btile.h"
#include "rage1/screen.h"
#include "rage1/sprite.h"
#include "rage1/debug.h"
#include "rage1/interrupts.h"
#include "rage1/bullet.h"
#include "rage1/hotzone.h"
#include "rage1/util.h"
#include "rage1/dataset.h"

#include "game_data.h"

#include "rage1/banked.h"

// auxiliary functions for hero_can_move_in_direction()
uint8_t hero_can_move_vertical( uint8_t x, uint8_t r, uint8_t c ) {
    uint8_t i;
    for ( i = PIXEL_TO_CELL_COORD( x ) ; i <= c ; i++ )
        if ( GET_TILE_TYPE_AT( r, i ) == TT_OBSTACLE )
            return 0;
    return 1;
}

uint8_t hero_can_move_horizontal( uint8_t y, uint8_t r, uint8_t c ) {
    uint8_t i;
    for ( i = PIXEL_TO_CELL_COORD( y ) ; i <= r ; i++ )
        if ( GET_TILE_TYPE_AT( i, c ) == TT_OBSTACLE )
            return 0;
    return 1;
}

uint8_t hero_can_move_in_direction( uint8_t direction ) {
    struct hero_info_s *h;
    uint8_t x,y,dx,dy,r,c;

    h = &game_state.hero;
    x = h->position.x;
    y = h->position.y;
    dx = h->movement.dx;
    dy = h->movement.dy;

    // hero can move in one direction if there are no obstacles in the new position
    switch (direction ) {
        case MOVE_UP:
            if ( y <= HERO_MOVE_YMIN )
                return 0;
            r = PIXEL_TO_CELL_COORD( y - dy );
            c = PIXEL_TO_CELL_COORD( x + HERO_SPRITE_WIDTH - 1 );
            return hero_can_move_vertical( x, r, c );
            break;
        case MOVE_DOWN:
            if ( y >= HERO_MOVE_YMAX )
                return 0;
            r = PIXEL_TO_CELL_COORD( y + HERO_SPRITE_HEIGHT - 1 + dy );
            c = PIXEL_TO_CELL_COORD( x + HERO_SPRITE_WIDTH - 1 );
            return hero_can_move_vertical( x, r, c );
            break;
        case MOVE_LEFT:
            if ( x <= HERO_MOVE_XMIN )
                return 0;
            r = PIXEL_TO_CELL_COORD( y + HERO_SPRITE_HEIGHT - 1 );
            c = PIXEL_TO_CELL_COORD( x - dx );
            return hero_can_move_horizontal( y, r, c );
            break;
        case MOVE_RIGHT:
            if ( x >= HERO_MOVE_XMAX )
                return 0;
            r = PIXEL_TO_CELL_COORD( y + HERO_SPRITE_HEIGHT - 1 );
            c = PIXEL_TO_CELL_COORD( x + HERO_SPRITE_WIDTH - 1 + dx );
            return hero_can_move_horizontal( y, r, c );
            break;
    }
    // should not reach this
    return 0;
}

void hero_animate_and_move( void ) {
    struct hero_info_s *h;
    struct hero_animation_data_s *anim;
    struct position_data_s *pos;
    struct hero_movement_data_s *move;
    uint8_t controller;
    uint8_t newx,newy,x,y,oldx,oldy;
    uint8_t *animation_frame;
    uint8_t allowed;
    uint8_t steady_frame;

    h = &game_state.hero;	// efficiency matters ;-)
    if ( ! IS_HERO_ALIVE( game_state.hero ) )	// skip if not alive
        return;

    // cache some pointers for eficiency
    anim = &h->animation;
    move = &h->movement;

    // get controller movement state
    controller = game_state.controller.state & MOVE_ALL;

    if ( controller == MOVE_NONE ) {
        if ( ! IS_HERO_STEADY( game_state.hero ) ) {

            steady_frame = 0;	// default value

            if ( move->last_direction & MOVE_UP )
                steady_frame = HERO_SPRITE_STEADY_FRAME_UP;

            if ( move->last_direction & MOVE_DOWN )
                steady_frame = HERO_SPRITE_STEADY_FRAME_DOWN;

            if ( move->last_direction & MOVE_LEFT )
                steady_frame = HERO_SPRITE_STEADY_FRAME_LEFT;

            if ( move->last_direction & MOVE_RIGHT )
                steady_frame = HERO_SPRITE_STEADY_FRAME_RIGHT;

            anim->current_frame = 0;
            anim->last_frame_ptr = home_assets->all_sprite_graphics[ HERO_SPRITE_ID ].frame_data.frames[ steady_frame ];
            SET_LOOP_FLAG( F_LOOP_REDRAW_HERO );
            SET_HERO_FLAG( game_state.hero, F_HERO_STEADY );
        }
        return;
    }

    // if we reach here, some movement was requested, so reset the steady flag
    RESET_HERO_FLAG( game_state.hero, F_HERO_STEADY );

    // cache some pointers for eficiency
    pos = &h->position;

    // initialize preconditions
    oldx = x = pos->x;
    oldy = y = pos->y;

    // operate on the hero following controller state
    if ( controller & MOVE_UP ) {
        // reset animation in case of direction change
        if ( controller != move->last_direction ) {
            anim->current_frame = 0;
            anim->current_sequence = anim->sequence_up;
        }
        // check if can move to new coordinate
        newy = pos->y - move->dy;
        if ( newy <= CELL_TO_PIXEL_COORD( GAME_AREA_TOP ) )
            pos->y = CELL_TO_PIXEL_COORD( GAME_AREA_TOP );
        else
            if ( hero_can_move_in_direction( MOVE_UP ) )
                pos->y = newy;
    }
    if ( controller & MOVE_DOWN ) {
        if ( controller != move->last_direction ) {
            anim->current_frame = 0;
            anim->current_sequence = anim->sequence_down;
        }
        newy = pos->y + move->dy;
        // coordinate of the bottommost pixel
        allowed = CELL_TO_PIXEL_COORD( GAME_AREA_BOTTOM + 1 ) - 1 - HERO_SPRITE_HEIGHT;
        if ( newy >= allowed )
            pos->y = allowed;
        else
            if ( hero_can_move_in_direction( MOVE_DOWN ) )
                pos->y = newy;
    }
    if ( controller & MOVE_LEFT ) {
        if ( controller != move->last_direction ) {
            anim->current_frame = 0;
            anim->current_sequence = anim->sequence_left;
        }
        newx = pos->x - move->dx;
        if ( newx <= CELL_TO_PIXEL_COORD( GAME_AREA_LEFT ) )
            pos->x = CELL_TO_PIXEL_COORD( GAME_AREA_LEFT );
        else
            if ( hero_can_move_in_direction( MOVE_LEFT ) )
                pos->x = newx;
    }
    if ( controller & MOVE_RIGHT ) {
        if ( controller != move->last_direction ) {
            anim->current_frame = 0;
            anim->current_sequence = anim->sequence_right;
        }
        newx = pos->x + move->dx;
        // coordinate of the rightmost pixel
        allowed = CELL_TO_PIXEL_COORD( GAME_AREA_RIGHT + 1 ) - 1 - HERO_SPRITE_WIDTH;
        if ( newx >= allowed )
            pos->x = allowed;
        else
            if ( hero_can_move_in_direction( MOVE_RIGHT ) )
                pos->x = newx;
    }

    // update last movement direction
    move->last_direction = controller;

    // set pointer to animation frame
    animation_frame = home_assets->all_sprite_graphics[ HERO_SPRITE_ID ].frame_data.frames[
        home_assets->all_sprite_graphics[ HERO_SPRITE_ID ].sequence_data.sequences[ anim->current_sequence ].frame_numbers[ anim->current_frame ]
        ];

    // animate hero
    if ( ++anim->delay_counter == anim->delay ) {
        anim->delay_counter = 0;
        if ( ++anim->current_frame == home_assets->all_sprite_graphics[ HERO_SPRITE_ID ].sequence_data.sequences[ anim->current_sequence ].num_frames ) {
            anim->current_frame = 0;
        }
    }

    // if position has changed, adjust xmax, ymax and move sprite to new
    // position
    if ( ( oldx != pos->x ) || ( oldy != pos->y ) ) {
        pos->xmax = pos->x + HERO_SPRITE_WIDTH - 1;
        pos->ymax = pos->y + HERO_SPRITE_HEIGHT - 1;
        anim->last_frame_ptr = animation_frame;
        SET_LOOP_FLAG( F_LOOP_REDRAW_HERO );
    }
}


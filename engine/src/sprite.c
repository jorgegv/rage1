////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include "game_state.h"
#include "sprite.h"
#include "screen.h"
#include "game_data.h"
#include "map.h"
#include "debug.h"
#include "util.h"

void sprite_reset_position_all( uint8_t num_sprites, struct sprite_info_s *sprites ) {
    static struct sprite_info_s *s;
    static uint8_t n;

    n = num_sprites;
    while( n-- ) {
        s = &sprites[n];		// eficiency matters ;-)
        if ( ! IS_SPRITE_ACTIVE(*s) )	// skip if not active
            continue;

        // reset sprite state to initial values - update xmax and ymax also
        s->animation.current_frame = s->animation.delay_counter = 0;
        s->position.x = s->movement.data.linear.initx;
        s->position.y = s->movement.data.linear.inity;
        s->movement.data.linear.dx = s->movement.data.linear.initdx;
        s->movement.data.linear.dy = s->movement.data.linear.initdy;

        // adjust xmax, ymax and move sprite to initial position
        s->position.xmax = s->position.x + s->width - 1;
        s->position.ymax = s->position.y + s->height - 1;
        sp1_MoveSprPix( s->sprite, &game_area, s->animation.frames[0], s->position.x, s->position.y );
    }
}

void sprite_animate_and_move_all( uint8_t num_sprites, struct sprite_info_s *sprites ) {
    static struct sprite_info_s *s;
    static struct sprite_animation_data_s *anim;
    static struct sprite_position_data_s *pos;
    static struct sprite_movement_data_s *move;
    static uint8_t n;

    n = num_sprites;
    while( n-- ) {
        s = &sprites[n];		// efficiency matters ;-)
        if ( ! IS_SPRITE_ACTIVE(*s) )	// skip if not active
            continue;

        // animate sprite
        anim = &s->animation;
        if ( ++anim->delay_counter == anim->delay ) {
            anim->delay_counter = 0;
            if ( ++anim->current_frame == anim->num_frames ) {
                anim->current_frame = 0;
            }
        }

        // set new sprite position according to movement rules
        pos = &s->position;
        move = &s->movement;
        switch ( move->type ) {
            case SPRITE_MOVE_LINEAR:
                if ( ++move->delay_counter == move->delay ) {
                    move->delay_counter = 0;
                    pos->x += move->data.linear.dx;
                    if (
                            ( pos->x >= move->data.linear.xmax ) ||
                            ( pos->x <= move->data.linear.xmin ) ||
                            ( SPRITE_MUST_BOUNCE(*s) && (
                                ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y ), PIXEL_TO_CELL_COORD( pos->x + s->width ) ) == TT_OBSTACLE ) ||
                                ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y ), PIXEL_TO_CELL_COORD( pos->x - 1 ) ) == TT_OBSTACLE ) ||
                                ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y + s->height - 1), PIXEL_TO_CELL_COORD( pos->x + s->width ) ) == TT_OBSTACLE ) ||
                                ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y + s->height - 1), PIXEL_TO_CELL_COORD( pos->x - 1 ) ) == TT_OBSTACLE )
                            ) )
                        ) { // then
                        move->data.linear.dx = -move->data.linear.dx;
                    }
                    pos->y += move->data.linear.dy;
                    if (
                            ( pos->y >= move->data.linear.ymax ) ||
                            ( pos->y <= move->data.linear.ymin ) ||
                            ( SPRITE_MUST_BOUNCE(*s) && (
                                ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y + s->height ), PIXEL_TO_CELL_COORD( pos->x ) ) == TT_OBSTACLE ) ||
                                ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y - 1 ), PIXEL_TO_CELL_COORD( pos->x ) ) == TT_OBSTACLE ) ||
                                ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y + s->height ), PIXEL_TO_CELL_COORD( pos->x + s->width - 1) ) == TT_OBSTACLE ) ||
                                ( TILE_TYPE_AT( PIXEL_TO_CELL_COORD( pos->y - 1), PIXEL_TO_CELL_COORD( pos->x + s->width - 1 ) ) == TT_OBSTACLE )
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
        pos->xmax = pos->x + s->width - 1;
        pos->ymax = pos->y + s->height - 1;
        sp1_MoveSprPix( s->sprite, &game_area, anim->frames[anim->current_frame], pos->x, pos->y );
    }
}

void sprite_move_offscreen( struct sp1_ss *s ) {
    sp1_MoveSprAbs( s, &full_screen, NULL, OFF_SCREEN_ROW, OFF_SCREEN_COLUMN, 0, 0 );
}

void sprite_move_offscreen_all( uint8_t num_sprites, struct sprite_info_s *sprites ) {
    static uint8_t i;
    i = num_sprites;
    while ( i-- ) sprite_move_offscreen( sprites[i].sprite );
}
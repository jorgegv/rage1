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

#include "rage1.h"

void init_hero(void) {
    init_hero_sprites();
    init_bullet_sprites();
}

// resets hero position after being killed
void hero_reset_position(void) {
    static struct hero_info_s *h;
    static struct hero_animation_data_s *anim;

    h = &game_state.hero;
    anim = &h->animation;

    // set initial position and move it there - update xmax and ymax also
    h->position.x = map[ game_state.current_screen ].hero_data.startup_x;
    h->position.y = map[ game_state.current_screen ].hero_data.startup_y;

    // adjust xmax, ymax and move sprite to initial position
    h->position.xmax = h->position.x + h->width - 1;
    h->position.ymax = h->position.y + h->height - 1;
    sp1_MoveSprPix( h->sprite, &game_area, anim->frames_right[0], h->position.x, h->position.y );
}

// resets hero state at game startup
void hero_reset_all(void) {
    static struct hero_info_s *h;

    h = &game_state.hero;

    // bulk copy from static data. Sprite ptr gets trashed
    memcpy( h, &hero_startup_data, sizeof( hero_startup_data ) );
    // ...but we saved it in initialization, so restore it
    h->sprite = hero_sprite;

    // set flags
    SET_HERO_FLAG( *h, F_HERO_ALIVE );

    // reset position
    hero_reset_position();
}

uint8_t hero_can_move_in_direction( uint8_t direction ) {
    static struct hero_info_s *h;
    static uint8_t x,y,dx,dy,i,r,c;

    h = &game_state.hero;
    x = h->position.x;
    y = h->position.y;
    dx = h->movement.dx;
    dy = h->movement.dy;

    // hero can move in one direction if there are no obstacles in the new position
    switch (direction ) {
        case MOVE_UP:
            r = PIXEL_TO_CELL_COORD( y - dy );
            c = PIXEL_TO_CELL_COORD( x + h->width - 1 );
            for ( i = PIXEL_TO_CELL_COORD( x ) ; i <= c ; i++ )
                if ( TILE_TYPE_AT( r, i ) == TT_OBSTACLE )
                    return 0;
            return 1;
            break;
        case MOVE_DOWN:
            r = PIXEL_TO_CELL_COORD( y + h->height - 1 + dy );
            c = PIXEL_TO_CELL_COORD( x + h->width - 1 );
            for ( i = PIXEL_TO_CELL_COORD( x ) ; i <= c ; i++ )
                if ( TILE_TYPE_AT( r, i ) == TT_OBSTACLE )
                    return 0;
            return 1;
            break;
        case MOVE_LEFT:
            r = PIXEL_TO_CELL_COORD( y + h->height - 1 );
            c = PIXEL_TO_CELL_COORD( x - dx );
            for ( i = PIXEL_TO_CELL_COORD( y ) ; i <= r ; i++ )
                if ( TILE_TYPE_AT( i, c ) == TT_OBSTACLE )
                    return 0;
            return 1;
            break;
        case MOVE_RIGHT:
            r = PIXEL_TO_CELL_COORD( y + h->height - 1 );
            c = PIXEL_TO_CELL_COORD( x + h->width - 1 + dx );
            for ( i = PIXEL_TO_CELL_COORD( y ) ; i <= r ; i++ )
                if ( TILE_TYPE_AT( i, c ) == TT_OBSTACLE )
                    return 0;
            return 1;
            break;
    }
    // should not reach this
    return 0;
}

void hero_animate_and_move( void ) {
    static struct hero_info_s *h;
    static struct hero_animation_data_s *anim;
    static struct sprite_position_data_s *pos;
    static struct hero_movement_data_s *move;
    static uint8_t controller;
    static uint8_t newx,newy,x,y,oldx,oldy;
    static uint8_t *animation_frame;
    static uint8_t allowed;


    h = &game_state.hero;	// efficiency matters ;-)
    if ( ! IS_HERO_ALIVE(*h) )	// skip if not alive
        return;

    move = &h->movement;	// for efficiency
    controller = game_state.controller.state;

    // do nothing if no move
    if ( ( controller & MOVE_ALL ) == MOVE_NONE )
        return;

    // cache some pointers for eficiency
    anim = &h->animation;
    pos = &h->position;

    // initialize preconditions
    oldx = x = pos->x;
    oldy = y = pos->y;

    // operate on the hero following controller state
    // isolate only movements for checking
    // only allow single direction moves
    switch ( controller & MOVE_ALL ) {
        case MOVE_UP:
            // reset animation in case of direction change
            if ( move->last_direction != MOVE_UP ) {
                anim->current_frame = 0;
                move->last_direction = MOVE_UP;
            }
            // check if can move to new coordinate
            newy = pos->y - move->dy;
            if ( newy <= CELL_TO_PIXEL_COORD( GAME_AREA_TOP ) )
                pos->y = CELL_TO_PIXEL_COORD( GAME_AREA_TOP );
            else 
                if ( hero_can_move_in_direction( MOVE_UP ) )
                    pos->y = newy;
            // set pointer to animation frame
            animation_frame = anim->frames_up[ anim->current_frame ];
            break;
        // remaining cases are managed in the same way
        case MOVE_DOWN:
            if ( move->last_direction != MOVE_DOWN ) {
                anim->current_frame = 0;
                move->last_direction = MOVE_DOWN;
            }
            newy = pos->y + move->dy;
            // coordinate of the bottommost pixel
            allowed = CELL_TO_PIXEL_COORD( GAME_AREA_BOTTOM + 1 ) - 1 - h->height;
            if ( newy >= allowed )
                pos->y = allowed;
            else
                if ( hero_can_move_in_direction( MOVE_DOWN ) )
                    pos->y = newy;
            animation_frame = anim->frames_down[ anim->current_frame ];
            break;
        case MOVE_LEFT:
            if ( move->last_direction != MOVE_LEFT ) {
                anim->current_frame = 0;
                move->last_direction = MOVE_LEFT;
            }
            newx = pos->x - move->dx;
            if ( newx <= CELL_TO_PIXEL_COORD( GAME_AREA_LEFT ) )
                pos->x = CELL_TO_PIXEL_COORD( GAME_AREA_LEFT );
            else
                if ( hero_can_move_in_direction( MOVE_LEFT ) )
                    pos->x = newx;
            animation_frame = anim->frames_left[ anim->current_frame ];
            break;
        case MOVE_RIGHT:
            if ( move->last_direction != MOVE_RIGHT ) {
                anim->current_frame = 0;
                move->last_direction = MOVE_RIGHT;
            }
            newx = pos->x + move->dx;
            // coordinate of the rightmost pixel
            allowed = CELL_TO_PIXEL_COORD( GAME_AREA_RIGHT + 1 ) - 1 - h->width;
            if ( newx >= allowed )
                pos->x = allowed;
            else
                if ( hero_can_move_in_direction( MOVE_RIGHT ) )
                    pos->x = newx;
            animation_frame = anim->frames_right[ anim->current_frame ];
            break;
        default:	// reset movement direction
            break;            
    }

    // animate hero
    if ( ++anim->delay_counter == anim->delay ) {
        anim->delay_counter = 0;
        if ( ++anim->current_frame == anim->num_frames ) {
            anim->current_frame = 0;
        }
    }

    // if position has changed, adjust xmax, ymax and move sprite to new
    // position
    if ( ( oldx != pos->x ) || ( oldy != pos->y ) ) {
        pos->xmax = pos->x + h->width - 1;
        pos->ymax = pos->y + h->height - 1;
        sp1_MoveSprPix( h->sprite, &game_area, animation_frame, pos->x, pos->y );
    }
}

void hero_shoot_bullet( void ) {

    // ignore the shot if we are in the "reloading" phase
    if ( game_state.bullet.reloading-- )
        return;

    // add a new bullet and load the "reload" counter
    bullet_add();
    game_state.bullet.reloading = game_state.bullet.reload_delay;

}

void hero_pickup_items(void) {
    static struct sp1_ss *s;
    static uint8_t i,j,cols,r,c,item;

    s = game_state.hero.sprite;

    // run all chars and search for items
    cols = s->width;	// SP1 units: chars (_not_ pixels!)

    i = s->height;		// same comment as above!
    while ( i-- ) {
        r = s->row + i;
        j = cols;
        while ( j-- ) {
            c = s->col + j;
            if ( TILE_TYPE_AT( r, c ) == TT_ITEM ) {
                item = map_get_item_at_position( &map[ game_state.current_screen ], r, c );
                // add item to inventory
                inventory_add_item( &game_state.inventory, item );
                // mark the item as inactive
                RESET_ITEM_FLAG( all_items[ item ], F_ITEM_ACTIVE );
                // remove item from screen
                btile_remove( r, c, all_items[ item ].btile );
                // update inventory on screen (show)
                inventory_show();
                // play pickup sound
                beep_fx( SOUND_ITEM_GRABBED );
            }
        }
    }
}

// printing context
struct sp1_pss lives_display_ctx = {
   &lives_area,				// bounds
   SP1_PSSFLAG_INVALIDATE,		// flags
   0,0,					// initial position x,y
   0, DEFAULT_BG_ATTR,			// attr mask and attribute
   0,0					// RESERVED
};

void hero_update_lives_display(void) {
    static uint8_t col;
    static uint8_t n;

    // clear the area
    sp1_ClearRectInv( &lives_area, DEFAULT_BG_ATTR, ' ', SP1_RFLAG_TILE | SP1_RFLAG_COLOUR );

    // draw one tile per live
    col = LIVES_AREA_LEFT;
    n = game_state.hero.num_lives;
    while ( n-- )
        btile_draw( LIVES_AREA_TOP, col++, game_state.hero.lives_tile, TT_DECORATION, &lives_area );
}

void hero_check_if_inside_hotzones(void) {
    static uint8_t i;
    static struct hotzone_info_s *hz;

    i = map[ game_state.current_screen ].hotzone_data.num_hotzones;
    while ( i-- ) {
        hz = &map[ game_state.current_screen ].hotzone_data.hotzones[ i ];
        if ( GET_HOTZONE_FLAG( *hz, F_HOTZONE_ACTIVE ) &&
            hotzone_is_inside( hz,
                game_state.hero.position.x + game_state.hero.width / 2,
                game_state.hero.position.y + game_state.hero.height / 2
            ) ) {
            switch ( hz->type ) {
                case HZ_TYPE_WARP:
                    game_state.hero.position.x = hz->destination_screen.hero_x;
                    game_state.hero.position.y = hz->destination_screen.hero_y;
                    game_state_goto_screen( hz->destination_screen.screen_num );
                    return;
                    break;
                case HZ_TYPE_END_OF_GAME:
                    SET_LOOP_FLAG( F_LOOP_INSIDE_EXIT_ZONE );
                    return;
                    break;
                default:
                    break;
            }
        }
    }
}

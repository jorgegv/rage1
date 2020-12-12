////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is ublished under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include "collision.h"
#include "sprite.h"
#include "game_state.h"
#include "debug.h"
#include "bullet.h"
#include "screen.h"
#include "beeper.h"

#define COLLISION_TOLERANCE	2

uint8_t collision_check( struct sprite_position_data_s *a,struct sprite_position_data_s *b ) {
    if ( a->xmax - COLLISION_TOLERANCE < b->x + COLLISION_TOLERANCE    ) return 0;
    if ( a->x + COLLISION_TOLERANCE    > b->xmax - COLLISION_TOLERANCE ) return 0;
    if ( a->ymax - COLLISION_TOLERANCE < b->y + COLLISION_TOLERANCE    ) return 0;
    if ( a->y + COLLISION_TOLERANCE    > b->ymax - COLLISION_TOLERANCE ) return 0;
    return 1;
}

void collision_check_hero_with_sprites(void) {
    static struct sprite_position_data_s *hero_pos,*sprite_pos;
    static struct sprite_info_s *s;
    static uint8_t i;
    struct map_screen_s *sc;

    hero_pos = &game_state.hero.position;
    sc = &map[game_state.current_screen];

    i = sc->sprite_data.num_sprites;
    while ( i-- ) {
        s = &sc->sprite_data.sprites[ i ];

        if ( IS_SPRITE_ACTIVE( *s ) ) {
            sprite_pos = &s->position;
            if ( collision_check( hero_pos, sprite_pos ) ) {
                SET_GAME_FLAG( F_GAME_PLAYER_DIED );
                return;
            }
        }
    }
}

void collision_check_bullets_with_sprites( void ) {
    static struct bullet_state_data_s *b;
    static struct sprite_info_s *s;
    static uint8_t si,bi;
    struct map_screen_s *sc;

    sc = &map[game_state.current_screen];

    bi = game_state.bullet.num_bullets;
    while ( bi-- ) {
        b = &game_state.bullet.bullets[ bi ];
        if ( IS_BULLET_ACTIVE( *b ) ) {
            si = sc->sprite_data.num_sprites;
            while ( si-- ) {
                s = &sc->sprite_data.sprites[ si ];
                if ( IS_SPRITE_ACTIVE( *s ) ) {
                    if ( collision_check( &b->position, &s->position ) ) {
                        // set bullet inactive and move away
                        RESET_BULLET_FLAG( *b, F_BULLET_ACTIVE );
                        sprite_move_offscreen( b->sprite );
                        // set sprite inactive and move away
                        RESET_SPRITE_FLAG( *s, F_SPRITE_ACTIVE );
                        sprite_move_offscreen( s->sprite );
                        // TO DO: increment score, etc.
                        if ( ! --game_state.enemies_alive )
                            SET_GAME_FLAG( F_GAME_ALL_ENEMIES_KILLED );
                        beep_fx( SOUND_ENEMY_KILLED );
                    }
                }
            }
        }
    }
}

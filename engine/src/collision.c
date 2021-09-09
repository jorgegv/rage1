////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include "rage1/collision.h"
#include "rage1/sprite.h"
#include "rage1/game_state.h"
#include "rage1/debug.h"
#include "rage1/bullet.h"
#include "rage1/screen.h"
#include "rage1/beeper.h"
#include "rage1/enemy.h"

#define COLLISION_TOLERANCE	2

uint8_t collision_check( struct position_data_s *a,struct position_data_s *b ) {
    if ( a->xmax - COLLISION_TOLERANCE < b->x + COLLISION_TOLERANCE    ) return 0;
    if ( a->x + COLLISION_TOLERANCE    > b->xmax - COLLISION_TOLERANCE ) return 0;
    if ( a->ymax - COLLISION_TOLERANCE < b->y + COLLISION_TOLERANCE    ) return 0;
    if ( a->y + COLLISION_TOLERANCE    > b->ymax - COLLISION_TOLERANCE ) return 0;
    return 1;
}

void collision_check_hero_with_sprites(void) {
    struct position_data_s *hero_pos,*enemy_pos;
    struct enemy_info_s *s;
    uint8_t i;
    struct map_screen_s *sc;

    hero_pos = &game_state.hero.position;
    sc = &banked_assets->all_screens[game_state.current_screen];

    i = sc->enemy_data.num_enemies;
    while ( i-- ) {
        s = &sc->enemy_data.enemies[ i ];

        if ( IS_ENEMY_ACTIVE( *s ) ) {
            enemy_pos = &s->position;
            if ( collision_check( hero_pos, enemy_pos ) ) {
                SET_LOOP_FLAG( F_LOOP_HERO_HIT );
                return;
            }
        }
    }
}

void collision_check_bullets_with_sprites( void ) {
    struct bullet_state_data_s *b;
    struct enemy_info_s *s;
    uint8_t si,bi;
    struct map_screen_s *sc;

    sc = &banked_assets->all_screens[game_state.current_screen];

    bi = game_state.bullet.num_bullets;
    while ( bi-- ) {
        b = &game_state.bullet.bullets[ bi ];
        if ( IS_BULLET_ACTIVE( *b ) ) {
            si = sc->enemy_data.num_enemies;
            while ( si-- ) {
                s = &sc->enemy_data.enemies[ si ];
                if ( IS_ENEMY_ACTIVE( *s ) ) {
                    if ( collision_check( &b->position, &s->position ) ) {
                        // set bullet inactive and move away
                        RESET_BULLET_FLAG( *b, F_BULLET_ACTIVE );
                        sprite_move_offscreen( b->sprite );
                        // set sprite inactive and move away
                        RESET_ENEMY_FLAG( *s, F_ENEMY_ACTIVE );
                        sprite_move_offscreen( s->sprite );
                        // TO DO: increment score, etc.
                        if ( ! --game_state.enemies_alive )
                            SET_GAME_FLAG( F_GAME_ALL_ENEMIES_KILLED );
                        ++game_state.enemies_killed;
                        SET_LOOP_FLAG( F_LOOP_ENEMY_HIT );
                        beep_fx( SOUND_ENEMY_KILLED );
                    }
                }
            }
        }
    }
}

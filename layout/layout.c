// zcc +zx -compiler=sdcc -clib=sdcc_iy -I../engine/include -I../build/generated layout.c -o layout -create-app

#include <stdio.h>
#include <stdint.h>
#include <arch/spectrum.h>

#include "rage1/game_state.h"

#include "game_data.h"

#define offset_of(a,b) ( (uint8_t *)(&(a.b)) - (uint8_t *)(&(a)) )

struct game_state_s game_state;

void lprintc( uint8_t c ) __z88dk_fastcall __naked {
        __asm

        push hl			;; save L (c)

        ld a,3			;; open channel 3 (printer)
        call 0x1601		;; ROM_OPEN_CHANNEL

        pop hl
        ld a,l			;; char to print in A

        cp  10			;; is it CR?
        jr  nz,NoLF
        ld      a,13		;; replace with ZX CR

.NoLF
        ld      iy,23610	;; restore the right iy value, 
        set 1,(iy+1)		;; Set "printer in use" flag
        rst 16			;; print char
        res 1,(iy+1)		;; Reset "printer in use" flag

        ret

        __endasm;
}

void lputs( char *txt ) {
    while( *txt )
        lprintc( *txt++ );
    lprintc( '\n' );
}

char line_buf[1024];

void lprintf( char *fmt, uint16_t data ) {
    char *txt = line_buf;
    sprintf( line_buf, fmt, data );
    while( *txt )
        lprintc( *txt++ );
}

#define DEF(a,b)	lputs( "def " #a ":" #b )
#define PB(a,b)		lprintf( "pb " #a "+%d:" #a "." #b "\n", offset_of( a, b ) )
#define PW(a,b)		lprintf( "pw " #a "+%d:" #a "." #b "\n", offset_of( a, b ) )

void main( void ) {
    uint8_t i;

    zx_cls( INK_BLACK | PAPER_WHITE );
    puts( "Generating struct layout data...\n" );
    puts( "If this does program does not" );
    puts( "finish with 0:OK message, please");
    puts( "increment the SLEEP variable in" );
    puts( "script run_and_kill.sh and run" );
    puts( "'make' again.\n" );
    puts( "Generated file: output.txt\n" );
    puts( "Please wait until this window" );
    puts( "disappears\n" );

    DEF( game_state, _game_state );

    PB( game_state, current_screen );

    DEF( warp_next_screen, game_state.warp_next_screen );
    PB( game_state, warp_next_screen.num_screen );
    PB( game_state, warp_next_screen.hero_x );
    PB( game_state, warp_next_screen.hero_y );

    PW( game_state, current_screen_ptr );

    PW( game_state, current_screen_asset_state_table_ptr );

    PB( game_state, active_dataset );

    DEF( hero, game_state.hero );
    PW( game_state, hero.sprite );
    PB( game_state, hero.num_graphic );
#ifdef BUILD_FEATURE_HERO_ADVANCED_DAMAGE_MODE
    PB( game_state, hero.damage_mode.lives_max );
    PB( game_state, hero.damage_mode.health_max );
    PB( game_state, hero.damage_mode.enemy_damage );
    PB( game_state, hero.damage_mode.immunity_period );
#endif
    PB( game_state, hero.animation.sequence_up );
    PB( game_state, hero.animation.sequence_down );
    PB( game_state, hero.animation.sequence_left );
    PB( game_state, hero.animation.sequence_right );
    PB( game_state, hero.animation.delay );
    PB( game_state, hero.animation.current_sequence );
    PB( game_state, hero.animation.current_frame );
    PB( game_state, hero.animation.delay_counter );
    PW( game_state, hero.animation.last_frame_ptr );
    PB( game_state, hero.animation.steady_frame_up );
    PB( game_state, hero.animation.steady_frame_down );
    PB( game_state, hero.animation.steady_frame_left );
    PB( game_state, hero.animation.steady_frame_right );
    PB( game_state, hero.position.x.part.fraction );
    PB( game_state, hero.position.x.part.integer );
    PB( game_state, hero.position.y.part.fraction );
    PB( game_state, hero.position.y.part.integer );
    PB( game_state, hero.position.xmax );
    PB( game_state, hero.position.ymax );
    PB( game_state, hero.movement.last_direction );
    PB( game_state, hero.movement.dx.part.fraction );
    PB( game_state, hero.movement.dx.part.integer );
    PB( game_state, hero.movement.dy.part.fraction );
    PB( game_state, hero.movement.dy.part.integer );
    PB( game_state, hero.health.num_lives );
    PB( game_state, hero.health.health_amount );
    PB( game_state, hero.health.immunity_timer );
    PB( game_state, hero.flags );

    DEF( bullet, game_state.bullet );
    PB( game_state, bullet.width );
    PB( game_state, bullet.height );
    PW( game_state, bullet.frames );
    DEF( bullet_frames, bullet.frames );
    PB( game_state, bullet.movement.dx );
    PB( game_state, bullet.movement.dy );
    PB( game_state, bullet.movement.delay );
    PB( game_state, bullet.bullets );
    DEF( bullets, bullet.bullets );
    PB( game_state, bullet.active_bullets );
    PB( game_state, bullet.reload_delay );
    PB( game_state, bullet.reloading );
#ifndef BUILD_FEATURE_HERO_WEAPON_AUTOFIRE
    PB( game_state, bullet.firing );
#endif

    PB( game_state, flags );

    PB( game_state, loop_flags );

    PB( game_state, game_events );

    PB( game_state, user_flags );

    DEF( controller, game_state.controller );
    PB( game_state, controller.type );
    PW( game_state, controller.keys.fire);
    PW( game_state, controller.keys.right);
    PW( game_state, controller.keys.left);
    PW( game_state, controller.keys.down);
    PW( game_state, controller.keys.up);
    PB( game_state, controller.state );

    DEF( inventory, game_state.inventory );
    PW( game_state, inventory.owned_items );

    PW( game_state, enemies_alive );

    PW( game_state, enemies_killed );

    PW( game_state, beeper_fx );

    PW( game_state, tracker_fx );

#ifdef BUILD_FEATURE_GAME_TIME
    PW( game_state, game_time );
#endif

#ifdef BUILD_FEATURE_CUSTOM_STATE_DATA
    lprintf( "## CUSTOM_STATE_DATA_SIZE = %d\n", CUSTOM_STATE_DATA_SIZE );
    for ( i=0; i < CUSTOM_STATE_DATA_SIZE; i++ )
        PB( game_state, custom_data[i] );
#endif
}

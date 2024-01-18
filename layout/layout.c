// zcc +zx -compiler=sdcc -clib=sdcc_iy -I../engine/include -I../build/generated layout.c -o layout -create-app

#include <stdio.h>
#include <stdint.h>

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

#define PR_OFF(a,b)	lprintf( #a "." #b " = 0x%04x\n", offset_of( a, b ) )

void main( void ) {

    PR_OFF( game_state, current_screen );

    PR_OFF( game_state, warp_next_screen );
    PR_OFF( game_state, warp_next_screen.num_screen );
    PR_OFF( game_state, warp_next_screen.hero_x );
    PR_OFF( game_state, warp_next_screen.hero_y );

    PR_OFF( game_state, current_screen_ptr );

    PR_OFF( game_state, current_screen_asset_state_table_ptr );

    PR_OFF( game_state, active_dataset );

    PR_OFF( game_state, hero );

    PR_OFF( game_state, bullet );

    PR_OFF( game_state, flags );

    PR_OFF( game_state, loop_flags );

    PR_OFF( game_state, game_events );

    PR_OFF( game_state, user_flags );

    PR_OFF( game_state, controller );

    PR_OFF( game_state, inventory );

    PR_OFF( game_state, enemies_alive );

    PR_OFF( game_state, enemies_killed );

    PR_OFF( game_state, beeper_fx );

    PR_OFF( game_state, tracker_fx );

#ifdef BUILD_FEATURE_GAME_TIME
    PR_OFF( game_state, game_time );
#endif

#ifdef BUILD_FEATURE_CUSTOM_STATE_DATA
    PR_OFF( game_state, custom_data );
#endif
}

#include "rage1/debug.h"
#include "rage1/game_state.h"

void my_hero_display_health( void ) {
    debug_out( "\nH:" ); debug_out( i8toa( game_state.hero.health.health_amount ) );
}

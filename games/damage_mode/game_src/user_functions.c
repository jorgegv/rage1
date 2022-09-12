#include "rage1/debug.h"
#include "rage1/game_state.h"
#include "rage1/map.h"

uint8_t canary[6] = { 1,2,3,4,5,6 };
void my_user_init(void) {
    canary[0] = 'C';
    canary[1] = 'a';
    canary[2] = 'N';
    canary[3] = 'a';
    canary[4] = 'R';
    canary[5] = 'y';
}

void my_user_game_init(void) {
    canary[0] = 'S';
    canary[1] = 'p';
    canary[2] = 'A';
    canary[3] = 'r';
    canary[4] = 'O';
    canary[5] = 'w';
}

void my_user_game_loop(void) {
//   debug_out( "\nDBG:" ); debug_out( itohex( debug_flags ) );
//   debug_out( "\nDBG:" ); debug_out( i8toa( game_state.hero.num_graphic ) );
//   debug_out("\n");
//   debug_out("G"); debug_out(itohex(game_state.flags));
//   debug_out(" U"); debug_out(itohex(game_state.user_flags));
//   debug_out(" HZ"); debug_out(itohex(map[game_state.current_screen].hotzone_data.hotzones[1].flags));
//   debug_out(" L"); debug_out(itohex(game_state.loop_flags));
//   debug_out(" I"); debug_out(itohex(game_state.inventory.owned_items));
//   debug_out(" H"); debug_out(i8toa(game_state.hero.num_lives));
}


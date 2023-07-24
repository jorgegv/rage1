#include <rage1/controller.h>
#include <rage1/game_state.h>

// when the menu screen exits, the controller must have been selected
// see controller.h for options
void my_menu_screen(void) {
    game_state.controller.type = CTRL_TYPE_KEYBOARD;
}

#include <rage1/controller.h>
#include <rage1/game_state.h>

// minimal_audio_cpc menu screen (Phase AU5, cpc464).
//
// Identical to the games/minimal_cpc menu: select the keyboard as the
// controller and return, so the engine's check_controller() reads the keyboard
// (Q/A/O/P + Space) via the real CPC input HAL (engine/src/input.c CPC branch +
// engine/src/cpc/cpct_keyboard.asm) and drives the hero.  Without this MENU
// game-function the controller type stays CTRL_TYPE_UNDEFINED and the hero
// never moves (input_state_read() returns INPUT_STATE_NONE).
void my_menu_screen(void) {
    game_state.controller.type = CTRL_TYPE_KEYBOARD;
}

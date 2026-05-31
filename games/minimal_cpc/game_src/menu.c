#include <rage1/controller.h>
#include <rage1/game_state.h>

// minimal_cpc menu screen (Phase IN6, cpc464).
//
// The cpc464 analogue of the deferred cpc6128 controller-select overlay
// (IN6-4/5/6 are Phase 5 — README §5.12).  Trivial: select the keyboard as the
// controller and return, so the engine's check_controller() reads the keyboard
// (Q/A/O/P + Space) via the real CPC input HAL (engine/src/input.c CPC branch +
// engine/src/cpc/cpct_keyboard.asm) and drives the hero.
void my_menu_screen(void) {
    game_state.controller.type = CTRL_TYPE_KEYBOARD;
}

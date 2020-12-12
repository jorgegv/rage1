# Game Design

## High level pseudocode

* Build time: select minimal "gaming" CRT0

* Program initialization
  * Initialize memory allocation
  * Initialize SP1 library
  * Initialize IM2 interrupts

* Menu Screen
  * Display menu screen
  * Play music
  * Select controller (Keyboard, Kempston, Sinclair)
  * Go to Play Screen

* Play Screen
  * Set initial game variables and flags
  * Display play screen
  * Invalidate whole screen before starting main play loop
  * Execute main play loop
    * Check for special conditions in current screen
      * Check if life is 0, go to Game Over Screen
      * Check if goals have been accomplished, go to Final Screen
      * Check for screen change needed
    * Move sprites in current screen
    * Read input from controller
    * Move main character depending on controller results
      * Move character if moved and able to move
      * Start fire sequence if fired
    * Check collisions for elements in current screen
      * Player with tiles
      * Player with enemies
      * Fire with tiles
      * Fire with enemies
    * Redraw screen

* Game Over Screen
  * Display Game Over box and wait for keypress
  * Go to Menu Screen

* Final Screen
  * Display ending screen and animation sequence
  * Go to Menu Screen

## Design Notes

* Sprites in screens:
  * Have flag ACTIVE
  * Only move/show sprite if ACTIVE=1
  * Have different MOVEMENT types (movement type will have the same name,
  UPPERcase for macros and lowercase for union in struct sprite_movement_data_s)

* BTiles:
  * Have flag ACTIVE
  * Only show btile if ACTIVE=1

* Character movement:
  * Check if it can move to next position based on tile type for new position
  * Character is defined with 4 sprites, one for each movement direction
  * Each of the movement sprites maybe animated the same way as other sprites

* Collision detection:
  * Rectangle intersection

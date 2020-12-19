# Tasks

## General:

- [x] Parameterize general game variables into game.gdata file and generate
  data for it instead of hardcoding:
  - [x] num lives
  - [x] initial screen
  - [x] default ink and paper settings for background
  - [x] sounds for different events
  - [x] general game functions: menu, intro, game_end, game_over
- [ ] Allow 128K games w/ memory bank switching, etc.
- [ ] Add sound/music support for 128K chipset
- [ ] Add support for platform games in lateral view (i.e. gravity and floor
  detection support)

## Game loop

- [x] End of game: all enemies killed, all items collected, inside "exit
  zone" -> goto end screen.
- [x] Game over and End of Game detection:
  - [x] Add lives management and game over detection
  - [x] Add all items collected and end of game detection
  - [x] Add inside EXIT hotzone  and end of game detection
  - [x] Add all enemies killed and end of game detection
  - [x] Informative text box: used for end of game and game over screens
- [x] Game over: lives = 0 -> menu
- [ ] Refactor special conditions into engine (like La Churrera by Mojon Twins), with
  different conditions to be checked:
  - [ ] When: enter screen; exit screen; every game_loop cycle
  - [ ] Conditions: all items grabbed, all enemies killed, hot zone,...
  - [ ] Actions: end of game,...


## Inventory:

- [x] Add collectable items to the game and logic to pick them up, inventory, etc.
- [x] Add item detection and grabbing in hero movement code
- [x] Refactor btile type from btile definition (btile.gdata) to btile
  placement screen (screen.gdata).  This also makes more sense regarding
  items (type TT_ITEM).  You define _what_ a tile is in a Screen.  Tiles are
  then "generic graphics" that can be used for several purposes
  (decorations, items), the same as sprites can be used for enemies and
  bullets.
- [x] Tile: new tile type: TT_ITEM
- [x] Add Inventory struct
- [x] Add inventory display in main game screen
- [x] Refactor: Change item btiles table to a global item table with all
  item details (description, btile, etc.) and records in Screen with
  pointers to items and location on that screen.  Global information about
  items belongs in a global table, not dispersed among screens.  This will
  make inventory display easier.  Also, this is in line with the
  refactorization of btile type from btile definiton into btile placement in
  screens.

## Sprites:

- [x] Movement: make sprites bounce on obstacles
- [ ] Add LOAD type sprite for beter performance
- [x] Add collision detection between hero and sprites
- [x] Add collision detection between sprites and bullets
- [ ] Add sprite Z-planes in GDATA files
- [x] Remove global cache for sprites in game_state, it is not needed and
  makes screen and sprite handling more cumbersome.

## Hero:

- [x] Add fire capability
- [x] Fire: fix bug with multiple simultaneous shots
- [x] Fire: remove hardcoded screen limits, replace with GAME_AREA constants
- [x] Fire: make bullet disappear with obstacles
- [x] Fire: fix hardcoded bullet sizes in bullet_add
- [x] Fire: fix bug: active bullets remain on screen after player dies
- [ ] Fire: add animation to bullets
- [x] Fix movement: extend checks for obstacles to complete sprite borders
  (only corners are checked, which works fine for 16x16 sprites)

## Map:

- [x] Add exit/enter screen logic
- [x] Make dynamic map with hot zones and pointers: a screen has several hot
  zones (zones that switch to other screens).  Each hot-zone has the index
  to destination screen and hero position in destination screen.  Hot zones
  should be no more than, let's say 5?  they must be checked in every
  game_loop cycle for the current screen.  This removes old rectangular map
  limitations.  Hot-zone types: HZ_TYPE_WARP (jump to other screen),
  HZ_TYPE_END_OF_GAME (end of game)
- [x] New map handling: global screen table (array).  Screen indexes are not
  row,col but just index into global table.  Enters and exits from one
  screen to another just reference destination screen by index.  Global
  game_state just contains current_screen as an index into global screen
  table.

## Sound:

- [x] Add sound to sprite-player collision (hero death)
- [x] Add sound to sprite-bullet collision
- [x] Add sound when hero shoots a bullet
- [x] Add sound when hero grabs an item
- [x] Add sound to game-over
- [x] Add sound to end-of-game
- [x] Make test program with beeper.asm to test the different sounds (1 key =
  1 sound, 1...0 keys and more)
- [ ] Refactor sound generation and just include the player.  Include sounds
  in .gdata files, so that only used sounds are generated and included in
  the final game

## Enhancements:

- [x] Add consistency checks in datagen.pl: (branch: datagen_consistency_checks)
  - [x] Sprite names referenced in Screens exist
  - [x] Item names referenced in Screens exist
  - [x] Btiles referenced in Screens exist
  - [x] Hotzone: origin_screen.hotzone.destination_coords do not over lap with
    destination_screen.hotzone (to avoid loops and automatic screen switches)
  - [x] Only one Hero instance
  - [x] Only one Game instance
- [ ] Add support for multiple simultaneous heroes (multiplayer)

## Optimizations

- [x] Optimize precalculations in hero movement
- [x] Execute all optimizations in OPTIMIZATIONS.md:
  - [x] Replace all "for" incrementing loops  with "while" decrementing loops
  - [x] Review local -> static vars in all modules

## Bugs:

- [x] Bullet: obstacle detection: review checks, bullets go through some
  objects depending on position.
- [x] Fix inventory and lives display not disappearing when returning to
  main menu after GAME OVER condition
- [x] Sprite: killed sprites are not reactivated in a new game after game
  over.
- [x] Bullet: in-flight bullets keep on-screen after game-over
- [x] Sprite: moving sprites off-screen hangs

## Documentation

- [x] Prepare README.md for publication in GitHub
- [x] Document global game structure and each of the submodules.
  - [x] DESIGN.md
  - [x] DATAGEN.md (review)
  - [x] FLOWGEN.md
  - [x] OPTIMIZATIONS.md
  - [x] REQUIREMENTS.md
  - [x] USAGE.md
- [x] Document optimization techniques: while-dec loops instead of for-inc;
  optimize loop checks for variables that keep constant during loop; use
  static local vars instead of stack vars.

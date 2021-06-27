# RAGE1 ChangeLog

## 0.3.0 (2021-06-27)

### New features

- flowgen: enable setting/resetting flags for one screen from a different
  one

- tools: added new memmap.pl tool for better memory map output from game.map

- Makefile: made new-game target generate a really minimal game which you
  can start expanding right away without deleting anything


### Graphics

- hero: refactored sprite animation to single sprite with multiple sequences

- enemy: added dual animation sequence, changing when bouncing horizontally
  or vertically

### Fixes and optimizations

- game: remove game functions runtime checks, instead #defined them and
  removed game_config structure

- interrupts: optimized ISR code

- enemy: optimized animation and redrawing sequence

### Documentation

- doc: Addec RECIPES.md for commonly used game behaviours and how to do them
  with RAGE1

- doc: Added complete memory bank design, linking issues analysis and
  solution, and possible design for a paged minimal memory manager.  This is
  very important, it lays the way to games with fully working 128K RAM

## 0.2.0 (2021-04-27)

### New features

- Game scripting system: Flowgen tool, with dozens of checks and actions
  already defined, easily extensible

- Support for BeepFX sound effect definitions

- `SCREEN_DATA` Datagen directives for drawing a map screen with its tiles
  in text mode, similar to `PIXELS` directive for Tiles and Sprites (see
  `game_data/map/Screen03.gdata` for an example)

- Quickstart and WIndows installation instructions

### General

- Customizable game functions (menu, intro, game start, game loop, game end)

- Configurable screen areas (Game, Lives, Inventory, Debug)

### Graphics

- Sprites with multiple animation sequences

- Tiles can be hidden/shown dynamically

- `BACKGROUND` elements in screens, with `PROBABILITY`

- Datagen support for fully reading pixels _and_ attribute data from PNG
  files alone for sprites and tiles (added ZX-Spectrump GIMP palette for
  easier integration)

- Support for `HMIRROR` and `VMIRROR` directives in sprite defitions, so
  that you only need to draw animations once, then mirror them for different
  movement directions

### Fixes and optimizations

- Sprite drawing optimizations

- Differentiated between "enemy" code and "sprite" code (at last! :-)

## 0.1.0 (2020-12-12)

- Initial public release

- Basic game definition:
  - Datagen tool and GDATA data format
  - Tile, sprite, hero and game definition in GDATA format
  - Graphics data format defined by inline directives (`PIXELS`, `MASK`), or
  loaded from PNG files

- Basic game functionality:
  - Tile placement
  - Sprite movement
  - Collision detection
  - Shooting
  - Item grabbing
  - Global game loop and game state management

- Working but extremely simple test game

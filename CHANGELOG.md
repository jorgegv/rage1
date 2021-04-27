# RAGE1 ChangeLog

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

## Graphics

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

- Working but extrenely simple test game

# RAGE1 ChangeLog

## 0.6.0 (XXXX-XX-XX) - WORK IN PROGRESS

- WIP: The all wanted TUTORIAL is still in the works!  Sorry for moving this
  here from 0.5.0 release :-)

## 0.5.0 (2022-12-11)

NEWS: RAGE1 is being used to develop the game "Cesare the Somnambule", by
Team Moritz! "Cesare" is a game based around the classic film "The cabinet of Dr.
Caligari", so stay tuned!

Plus, this RAGE1 version has _loads_ of new features for your adventure games!

### New Tools

- MAPGEN: a new tool that can directly use your complete game map in PNG
  format (all screens together!), and together with your BTILE files (also
  PNG) automatically generate the needed GDATA files with all the map
  definitions (tiles, items, hotzones, flow rules, etc.).

  It can even detect and generate the switching hotzones between screens, so
  that navigation of the hero around the map is fully automatic.  This means
  that you can go from drawing the map in a graphics editor to seeing your
  hero moving around in a single step!

  You can see MAPGEN example use with sample maps in
  [MAPGEN.md](doc/MAPGEN.md)!

- BTILEGEN: an auxiliary tool that creates your BTILE definitions from your
  PNG tile files and a small trivial metadata file (TILEDEF)

### New Features and Gameplay Options

- The game can now have a Loading Screen, just provide the image in .SCR or
  .PNG format and you are all done

- Support for using a custom character set in .CH8 format.  You can choose
  to replace the whole 96 chars (32-127), or just a range of them (e.g. 
  numbers and capitals) for less memory usage

- Support for adding arbitrary raw data as binary blobs: the data can be
  stored in raw form (ready to use) or ZX0-compressed, and accessed via a
  regular C byte array as needed

- Support for CRUMBS: a new type of item that can be grabbed by the hero
  multiple times (think the dots in PacMan, or the coins in Super Mario
  Bros)

- New configurable Damage Mode for the hero: you can select the "enemy
  touches you once and you die" model (Manic Miner), or the "enemy touches
  you once and you are invulnerable for a while, but the second time you're
  dead" model (Ghosts'n Globlins), or the "enemy touches you and your energy
  goes down until you die" model (Phantomas)...  your choice!

- New in-game timer and associated GAME_TIME checks for FLOW rules.  This
  allows for executing FLOW actions and make certain events happen depending
  on the elapsed time since the game was started (e.g.  Knight-Lore night
  and day).

- 128K music and sound effects are ready!  The almighty Arkos Tracker 2 has
  been integrated into RAGE1 - this allows your game to have an in-game
  soundtrack playing while the game is running, and also sound effects are
  supported!  Of course, your game needs to be compiled in 128 mode, but you
  already know that, right?

- New in-game event system: some events are generated internally by the game
  (e.g.  the hero was hit, a buller was shot, an enemy was killed...) and
  now you can configure a special FLOW rule table to react to them in an
  efficient way.  Since it is configured with normal FLOW rules, you get all
  the FLOW actions available to react to the events (play sounds, switch
  soundtracks, set screen flags, enable tiles, etc.).  As a test-drive, all
  sounds from demo games have been migrated to the new event system.  More
  info on the available events can be found in `doc/GAME-EVENTS.md`

- New HARMFUL btiles: decorations that kill you if you step over them (or
  take energy from you if using advanced Damage mode for your hero).

- New ANIMATED btiles: decorations can now also have animations, which are
  configured in the same way as sprite animations. Animated btiles go
  specially well with HARMFUL btiles, so that your player know that some
  background that moves may harm te hero!

- The hero shooting system is now optional!  You can design games where you
  don't need weapons, or where the weapon is acquired during the game.  You
  can even disable or enable it based in game conditions specified as usual
  FLOW rules.  Of course, if your game does not use weapons at all, a whole
  bunch of code is not included (thanks, conditional compilation!) and you
  have a lot more space for graphics, screens, rules, enemies, etc.

### Enhancements, Fixes and Optimizations

- The hero can now move diagonally!

- When using 128K mode, one of the non-contended memory banks has been
  reserved for engine code, so that we have additional 16K for features. 
  Some of the most heavy engine functions have been moved into the
  additional bank, leaving more low-memory free for home bank assets. This
  is transparent to the game developer.

- Add multiple test games (including `minimal`) for testing different
  features: we have reached the point where if all features are configured
  in a single test game, the game does not fit in memory :-)

- Bullets can now have different graphics depending on the direction they
  are shot.  If you shoot balls, this does not matter very much, but it
  makes a difference if you shoot knives!

- A very powerful data analyzer and deduplicator has been included with
  DATAGEN.  You, game developer, do not need any more to take care of where
  your repeated tiles are and manage them manually for efficiency.  Just
  define all your btiles and DATAGEN will compress them all and find
  repeated tiles and byte sequences so that the space used by them is
  minimized!

### Documentation

- Of course, all the previous features and tools have been thoroughly
  documented in the associated files (DATAGEN, MAPGEN, etc.)

## 0.4.0 (2021-09-01)

### New features

- Support for 48K/128K mode with just a single `ZX_TARGET` configuration
  parameter! Compiling for 128K is as easy as setting `ZX_TARGET` to 128.

  Compilation for 128K target makes full use of the spare 5 RAM banks with
  your game data and handles automatic bank switching.  Game screens and
  assets are compressed (ZX0 - Thanks Einar Saukas!  :-) ) and located in
  different datasets and paged in and out as needed during the game.

### Fixes and optimizations

- A huge rewrite was needed for supporting 128K build

- You can't optimize what you can't measure: new tools added to aid in
  spotting optimization opportunities and measuring the results of code
  refactoring

- Heavy code size optimizations: new packed tile type map which occupies 75%
  less memory than the original implementation, and several other
  refactorings that helped reduce global memory usage for the test game in
  around 15%.

- New internal framework for conditional feature compilation: only features
  that are used in your game should be compiled in the final binary.  For
  now, only flow rules, checks and actions are using this framework, but
  more features will use it in the future for still more savings.

- New tool and script for easier FUSE debugging

### Documentation

- Documented design of 48K/128K mode architecture in
  [BANKING-DESIGN.md](doc/BANKING-DESIGN.md), and updated
  [USAGE-OVERVIEW.md](doc/USAGE-OVERVIEW.md) with new instructions

- [DATAGEN](doc/DATAGEN.md) syntax updates for the new 128K mode and
  functionalities

- Updated [OPTIMIZATIONS.md](doc/OPTIMIZATIONS.md) with the new techniques
  and tips used during the heavy optimization work done in this release

- New document [FUSE-DEBUG.md](doc/FUSE-DEBUG.md) with details for better
  debugging with FUSE emulator

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

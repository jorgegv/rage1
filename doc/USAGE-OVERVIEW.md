# How to build a game with RAGE1

## General view

The goal of this engine is to describe your game by creating data files
under `game_data` directory, and some glue or specific code under
`game_src`.

After that you will run the tools: DATAGEN tool to generate he game data,
FLOWGEN tool to compile the game script; and finally compile the whole game.

If you use the standard file and directory structure, the Makefile is
already set to do this, and you can build your full game with just a `make
build` command.

Files under `engine` directory are the engine source files and are not
intended to be modified if you are creating a game (unless you want to
contribute to the engine, of course!)

There is a minimal test game included with the engine, which is intended for
testing all engine features.  I recommend to go through the files under
`game_data` directory and understand the main components.  If in doubt,
check the game source and data, it's pretty well explained (I think :-).

## Game Entities

* GAME_CONFIG: general game configuration: number of lives, sound effects
  assigment, etc.

* BTILES: short for Big Tiles, they are graphic entities for static things
  (things that do not move): decorations, obstacles, inventory items, etc. 
  They are just a convenient way of associating several standard
  SP1 tiles (which are 8x8 pixel UDGs). You use BTILES for defining the
  screens in the game map, for example.

* SPRITES: sprites are graphic entities for enemies, hero, bullets, and in
  general, moving things.  The sprites just define the graphic part: size,
  pixel data, masks, animation frames, etc.  Assignment to the higher level
  objects is done elsewhere.  I.e.  you just define the look and feel here,
  not the behaviour.

* HERO: game hero configuration is done in this object.  Just one Hero
  object per game as of now, but multiplayer is on the works :-)

* HOTZONES: they are screen zones that make something happen when the hero
  touches them (e.g.  finish the game, or jump to another screen).  Mainly
  used for implementing the navigation between screens in the game map; you
  can define the destination screen and coordinates.

* MAP: the map is the set of game screens.  You define a screen as a
  composition of btiles, items, enemies, hotzones, etc.  The hotzones are
  specially important, since they define the way of exiting one screen and
  entering another one.  The map is NOT a rectangular array or screens, but
  it can be whatever shape you want.  You just need to correctly arrange the
  hotzones for going from one screen to the next.

  Since the screens are freely interconnected by hotzones, there is no "map"
  data structure as such,  just a bunch of interconnected screens.  You are
  responsible for checking that all the map is correctly connected.  The
  tools make some limited checks on the Hotzones (e.g.  that the destination
  of a hotzone is not another hotzone on the destination screen, which would
  make double switches, loops, etc.)

## Game Data (.gdata) files

Game Data to be processed by DATAGEN and FLOWGEN lives under `game_data`
directory.  Files here must have the `.gdata` extension to be processed by
the tools.

The entities mentioned above can be configured with GDATA files under
`game_data` directory.  They are spread over several directories for
tidyness.

The detailed reference for the syntax of GDATA files can be found in the
DATAGEN.md document.

## General game flow

You can easily follow the game menu and play loop logic starting in
`engine/src/main.c`.  The function names are pretty self-explanatory and the
code is well commented.

## Custom source code

Custom code can be defined in .c and .asm files under directory `game_src`. 
The Makefile is prepared to compile anything in that directory and add it to
your main program.  This can be used to include the Game Functions in
GAME_CONFIG structure, for example.


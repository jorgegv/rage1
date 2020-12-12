# How to build a game with RAGE1

The goal is to only generate data files under game_data directory, then run
the tools: DATAGEN tool to generate he game data, FLOWGEN tool to compile
the game script; and finally compile the whole game.  If you use the
standard file and directory structure, the Makefile is already set to do
this.

* *NOTE:* FLOWGEN is still a work in progress!

Files under `engine` directory are the engine source files and are not
intended to be modified if you are creating a game (unless you want to
contribute to the engine, of course!)

There is a minimal test game included with the engine, which is intended to
showcase (and develop/test, of course!) the main engine features.  I
recommend to go through the files under game_data/ directory and understand
the main components.  If in doubt, check the game source and data, it's
pretty well explained (I think :-).

Game Data to be processed by DATAGEN and FLOWGEN lives under game_data/
directory.  Files here must have the .gdata extension to be processed by the
tools.

Several types of entities can be configured with GDATA files under
game_data/ directory:

* GAME_CONFIG: general game configuration: number of lives, sound effects
  assigment, etc.

* SPRITES: sprites are used for enemies, hero and bullets.  The sprites just
  define the graphic part: size, pixel data, masks, animation frames, etc. 
  Assignment to the higher level objects is done elsewhere.  I.e.  you just
  define the look and feel here, not the behaviour.

* HERO: game hero configuration is done in this object.  Just one Hero
  object per game as of now, but multiplayer is on the works :-)

* BTILES: short for Big Tiles, they are just that: sets of several standard
  8x8 pixel SP1 tiles.  Useful for designing and inserting big graphic
  objects in screens, shown as decorations, obstacles, items, etc. and
  easily reusing them.

* MAP: game screens are defined here. You define a screen as a composition
  of btiles, items, enemies, hotzones, etc.

You can easily follow the game menu and play loop logic starting in
engine/src/main.c.  The function names are pretty self-explanatory.

Custom code can be defined in .c and .asm files under game_src. The Makefile
is prepared to compile anything in that directoru and add it to your main
program. This can be used to include the Game Functions in GAME_CONFIG
structure, for example.


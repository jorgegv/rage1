# Datagen

A utility to generate tiles, sprite, screen definitions, etc. from game
data text description files. Data files must have a .gdata extension.

## GDATA file syntax

* GDATA files are text files.
* Comments start with // and go through end of line
* Blank lines and white space are ignored
* Element names must be unique in their class.  Names can contain only
  [A-Z][a-z][0-9]_ 
* Each element definition begins with a BEGIN_xxxx line and ends with an
  END_xxxx line, being xxxx the type of the element being defined (see below
  for details for each element type)

### BTILE data

* Btiles are internally composed by 8x8 pixel SP1 tiles, but this is handled
  transparently for you by the engine.
* Btile sizes are specified as ROWS anc COLS of character cells (8x8 pixel
  cells)
* Pixel data can also be obtained from a PNG file, see below for details
* There must be ROWS x COLS ATTR lines
* Pixels and attributes are specified in left to right, top to bottom order.

Example `BTILE` definition:

```
BEGIN_BTILE
        NAME    Rock01
        ROWS    2
        COLS    2

        PIXELS  ....######..############..##....
        PIXELS  ############..################..
        PIXELS  ##############..############....
        PIXELS  ############..##..####..######..
        PIXELS  ..############################..
        PIXELS  ################..############..
        PIXELS  ##########..################....
        PIXELS  ######....##################....
        PIXELS  ####..############..##..######..
        PIXELS  ####################....####....
        PIXELS  ..####################..##..##..
        PIXELS  ############..##########..##....
        PIXELS  ####..########....############..
        PIXELS  ############..####..####..####..
        PIXELS  ..########..################....
        PIXELS  ................................

	// or...
        PNG_PIXELS      FILE=game_data/png/btile.png XPOS=8 YPOS=8 WIDTH=16 HEIGHT=16 BGCOLOR=ffffff FGCOLOR=000000

        ATTR    INK_YELLOW | PAPER_BLACK | BRIGHT
        ATTR    INK_YELLOW | PAPER_BLACK
        ATTR    INK_YELLOW | PAPER_BLACK
        ATTR    INK_YELLOW | PAPER_BLACK
END_BTILE
```

`BTILE` attributes:

* `NAME`: the name of the btile
* `ROWS`: number of character rows
* `COLS`: number of character columns
* `PIXELS`: pixel data.  Data must be COLS x 8 pixels (=bits) long.  Paper
  pixels must be specified as `..`, and ink pixels with `##`.  Yes, double
  characters :-). There must be ROWS x 8 PIXELS lines in the Btile definition.
* `PNG_PIXELS`: instead of PIXELS lines, pixel data can be extracted from a
  PNG image. Arguments for this attribute are specified as `ARG=value` pairs
  separated by spacs in the same PNG_PIXELS line. Possible arguments:
  * `FILE`: the PNG file where pixels are extracted from. File name relative
  to the repository top directory level.
  * `XPOS`, `YPOS`: pixel coordinates of the top left rectangle of pixels
  * `WIDTH`, `HEIGHT`: pixels dimensions of the rectangle of pixels
  * `BGCOLOR`: color in the PNG that will be considered as ink pixels
  * `FGCOLOR`: color that will be considered as paper pixels
* `ATTR`: specified the attributes for each of the character cells of the
  Btile. Standard z88dk ATTR definitions must be used (found in spectrum.h)

### SPRITE data

* Sprites are defined in the same way as Btiles. The new component is MASK,
  which sets the sprite mask when moving over the background.

* At the moment, Sprites are defined of type MASK. More types TBD.

Example `SPRITE` definition:

```
// Test sprite
BEGIN_SPRITE
	NAME	Ghost01
	ROWS	2
	COLS	2
//	TYPE	MASK

	FRAMES	2

	PIXELS	............######..............
	PIXELS	........##############..........
	PIXELS	....######################......
	PIXELS	....######################......
	PIXELS	..######....######....######....
	PIXELS	..####..####..##..####..####....
	PIXELS	######..##....##..##....######..
	PIXELS	######..##....##..##....######..
	PIXELS	########....######....########..
	PIXELS	##############################..
	PIXELS	######..######..######..######..
	PIXELS	####..##..##..##..##..##..####..
	PIXELS	##########..######..##########..
	PIXELS	##############################..
	PIXELS	######..######..######..######..
	PIXELS	..##......##......##......##....

	MASK	############......##############
	MASK	########..............##########
	MASK	####......................######
	MASK	####......................######
	MASK	##..........................####
	MASK	##..........................####
	MASK	..............................##
	MASK	..............................##
	MASK	..............................##
	MASK	..............................##
	MASK	..............................##
	MASK	..............................##
	MASK	..............................##
	MASK	..............................##
	MASK	......##......##......##......##
	MASK	##..######..######..######..####

	PIXELS	............######..............
	PIXELS	........##############..........
	PIXELS	....######################......
	PIXELS	....######################......
	PIXELS	..######....######....######....
	PIXELS	..####..####..##..####..####....
	PIXELS	######....##..##....##..######..
	PIXELS	######....##..##....##..######..
	PIXELS	########....######....########..
	PIXELS	##############################..
	PIXELS	######..######..######..######..
	PIXELS	####..##..##..##..##..##..####..
	PIXELS	##########..######..##########..
	PIXELS	##############################..
	PIXELS	######..######..######..######..
	PIXELS	..##......##......##......##....

	MASK	############......##############
	MASK	########..............##########
	MASK	####......................######
	MASK	####......................######
	MASK	##..........................####
	MASK	##..........................####
	MASK	..............................##
	MASK	..............................##
	MASK	..............................##
	MASK	..............................##
	MASK	..............................##
	MASK	..............................##
	MASK	..............................##
	MASK	..............................##
	MASK	......##......##......##......##
	MASK	##..######..######..######..####

	// or also...
        // frame 1
        PNG_PIXELS      FILE=game_data/png/sprite.png XPOS=8 YPOS=8 WIDTH=16 HEIGHT=16 FGCOLOR=000000
        PNG_MASK        FILE=game_data/png/sprite.png XPOS=8 YPOS=8 WIDTH=16 HEIGHT=16 MASKCOLOR=ff0000

        // frame 2
        PNG_PIXELS      FILE=game_data/png/sprite.png XPOS=24 YPOS=8 WIDTH=16 HEIGHT=16 FGCOLOR=000000
        PNG_MASK        FILE=game_data/png/sprite.png XPOS=24 YPOS=8 WIDTH=16 HEIGHT=16 MASKCOLOR=ff0000

END_SPRITE
```

`SPRITE` attributes:

* `NAME`, `ROWS`,`COLS`,`PIXELS`: these attributes are defined exactly the
  same way as in Btiles.
* `FRAMES`: sprites can be animated, this is used to specify the number of
  animation frames that will be defined. There should be enough data and
  mask pixels for all frames
* `PNG_PIXELS`: as in Btiles, selects pixel data from a PNG image.  The
  BGCOLOR argument is not used, only the FGCOLOR is used to select ink
  pixels.
* `PNG_MASK`: analogous to PNG_PIXELS, but selects sprite mask data instead.
  The new argument MASKCOLOR is used to specify the color that will be used
  as the mask.

A common arrangement for sprite graphics in PNG files is to draw the sprite
in B/W (#000000, #ffffff), and the mask in red (#ff0000)

Also, there is no need for a separate PNG for each sprite. You can define
all sprites and tiles in the same PNG file, and select pixel and mask data
for each of them by using coordinates in the PNG_PIXELS and PNG_MASK lines.

### SCREEN data

* Screens are where the game takes place. The hero (or heroes) move and can
  do things in it in order for the game to progress

* A map is composed of screens.  Screens can contain Btiles (decoration,
  obstacles), enemies (sprites), etc.

* Map geometry is not fixed, it must be defined by using hot zones.  The
  generated code is just a linear array of screen definitions, with the
  associated names and data


Example `SCREEN` definition:

```
BEGIN_SCREEN
	NAME		Screen01

	OBSTACLE	NAME=Tree01	ROW=8 COL=4
	OBSTACLE	NAME=Rock01	ROW=10 COL=12

	// Decoration for a hotzone must defined separately
	DECORATION	NAME=Stairs	ROW=16 COL=10
	HOTZONE				ROW=17 COL=11 WIDTH=1 HEIGHT=2 TYPE=WARP DEST_SCREEN=Screen02 DEST_HERO_X=100 DEST_HERO_Y=136 ACTIVE=1

	SPRITE  	NAME=Ghost01	MOVEMENT=LINEAR XMIN=8 YMIN=8 XMAX=233 YMAX=8 INITX=70 INITY=8 DX=2 DY=0 SPEED_DELAY=1 ANIMATION_DELAY=25 BOUNCE=1

	HERO		STARTUP_XPOS=20 STARTUP_YPOS=20

	ITEM		NAME=Heart	ROW=3 COL=6 ITEM_ID=0
END_SCREEN
```

`SCREEN` attributes:

* `NAME`: the name of the screen, used for referencing it from other
  elements
* `OBSTACLE`: places an element on the screen. The Hero can not go through
this element (=obstacle) but s/he must move around. Arguments:
  * `NAME`: the Btile that will be used to draw this obstacle
  * `ROW`, `COL`: position of the obstacle on the screen
* `DECORATION`: places a decoration on the screen. The hero can go over it.
  Arguments are the same as for OBSTACLEs.
* `HOTZONE`: a zone on the screen where something happens when the hero goes
  over it.  HOTZONEs are only definitions, not graphic elements, i.e.  they
  only define coordinate checks and actions to be done when inside.  If you
  want the hotzone to be decorated, you need to define a DECORATION that
  overlaps the HOTZONE (see the example). It suports the following
  arguments:
  * `ROW`,`COL`: top left position of the hot zone in char cells coordinates
  * `WIDTH`,`HEIGHT`: width and height of the hot zone in char cell
  coordinates
  * `ACTIVE`: 1 if this hotzone is active, 0 if not. Hot zones can be
  activated and deactivated during the game, this setting defined the
  initial state.
  * `TYPE`: the action the hot zone will do when the hero touches it. It can
  have the following values:
    * `END_OF_GAME`: the game jumps instantly to the end-of-game function (see
      GAME_CONFIG definition)
    * `WARP`: switches screen to another one. When this type is used, the
    following additional arguments must be specified.
  * `DEST_SCREEN`: name of the destination screen to warp to
  * `DEST_HERO_X`, `DEST_HERO_Y`: position of the hero on the destination
  screen after warping
* `HERO`: defines hero properties in this screen. Arguments:
  * `STARTUP_XPOS`,`STARTP_YPOS`: startup hero coordinates in this screen,
    of this is the initial screen.
* `ITEM`: positions an inventory item on the screen. Arguments:
  * `NAME`: the Btile that will be used to draw the item
  * `ROW`,`COL`: top left position of the item, in char cell coordinates
  * `ITEM_ID`: item ID in the game inventory
* `SPRITE`: defines an enemy on the screen (this element should probably be
    named ENEMY, I know, the name is a bit misleading :-( ). Arguments:
  * `NAME`: the name of the sprite to be used for this enemy
  * `MOVEMENT`: how the enemy moves. For the moment, this can be only
  `LINEAR`, and the following arguments refer to this movement type.
  * `XMIN`,`YMIN`,`XMAX`,`YMAX`: bounds for the enemy movement, in pixel
  coords. The sprite will never move outside this rectangle.
  * `BOUNCE`: 1 if the enemy bounces against obstacles, 0 if it goes through
  them. Enemies _always_ bounce against their bounding rectangles
  (XMIN,YMIN,XMAX,YMAX).
  * `INITX`,`INITY`: initial position for the sprite in pixel coords
  * `DX`,`DY`: coordinate increments when moving. Can be signed for defining
  the movement direction.
  * `SPEED_DELAY`: delay between different positions of the enemy (defines
  the speed of the enemy). Specified in 1/50s (screen frames)
  * `ANIMATION_DELAY`: delay between different sprites frames to be used for drawing
  the enemy, specified in 1/50s (screen frames)

### HERO data

* This element contains the definitions for the game hero.
* At the moment, only one `HERO` element can be defined per game.

Example `HERO` definition:

```
BEGIN_HERO
        NAME            Jorge
        SPRITE_UP       JorgeUp
        SPRITE_DOWN     JorgeDown
        SPRITE_LEFT     JorgeLeft
        SPRITE_RIGHT    JorgeRight
        ANIMATION_DELAY 6
        HSTEP           1
        VSTEP           1
        LIVES           NUM_LIVES=3 BTILE=Live
        BULLET          SPRITE=Bullet01 DX=3 DY=3 DELAY=0 MAX_BULLETS=4 RELOAD_DELAY=3
END_HERO
```

`HERO` attributes:

* `NAME`: a name for the hero
* `SPRITE_UP, SPRITE_DOWN, SPRITE_LEFT, SPRITE_RIGHT`: the sprites to use
  when moving in each of the four directions. These sprites can also have
  their own animation frames. The names used must match previous SPRITE
  graphic definitions
* `ANIMATION_DELAY`: delay between hero animation frames, in 1/50s (screen
  frames)
* `HSTEP`, `VSTEP`: movement increments for the hero
* `LIVES`: number of lives
* `BULLET`: configures firing. Arguments;
  * `SPRITE`: sprite to use for the bullet. Must match a graphic sprite
    definition
  * `DX`,`DY`: horizontal and vertical increments for moving bullets, in
    pixels
  * `DELAY`: delay between bullet positions (defines the speed of the
    bullet). In 1/50s (screen frames)
  * `MAX_BULLETS`: maximum number of bullets than can be active at the same
    time
  * `RELOAD_DELAY`: minimum deay between shots, in 1/50s

### GAME_CONFIG data

* This element contains miscelaneous game configuration which is related to
  the game itself, and not to any oher specific elements.

Example `GAME_CONFIG` definition:

```
BEGIN_GAME_CONFIG
        NAME            TestGame
        SCREEN          INITIAL=1
        DEFAULT_BG_ATTR INK_CYAN | PAPER_BLACK
        SOUND           ENEMY_KILLED=2
        SOUND           BULLET_SHOT=9
        SOUND           HERO_DIED=7
        SOUND           ITEM_GRABBED=1
        SOUND           CONTROLLER_SELECTED=5
        SOUND           GAME_WON=6
        SOUND           GAME_OVER=10
        GAME_FUNCTIONS  MENU=my_menu_screen INTRO=my_intro_screen GAME_END=my_game_end_screen GAME_OVER=my_game_over_screen
END_GAME_CONFIG
```

`GAME_CONFIG` attributes:

* `NAME`: the name of the game (Imagine :-)
* `SCREEN`: screen related settings. Arguments:
  * `INITIAL`: sets the initial screen for the game
* `DEFAULT_BG_ATTR`: default background attributes, defined as OR'ed
  constantes defined in spectrum.h
* `SOUND`: assigns a sound to a given game event. Sound IDs are indexes into
  the sound effects table (see beeper.asm). Arguments (events):
  * `ENEMY_KILLED`: hero kills an enemy
  * `BULLET_SHOT`: hero shoots
  * `HERO_DIED`: hero dies
  * `ITEM_GRABBED`: hero grabs an item
  * `CONTROLLER_SELECTED`: controller is selected in main menu
  * `GAME_WON`: game is ended successfully
  * `GAME_OVER`: game is over because lives=0
* `GAME_FUNCTIONS`: defines the names of special game functions. These
  functions must be included in sources under `game_src` directory. All
  these functions take and return no arguments, and must work over the
  global `game_state` variable. Arguments:
  * `MENU`: the main menu, must end with the correct controller selected
  * `INTRO`: intro screen, shown just after the menu and before beginning
  gameplay
  * `GAME_END`: this function will run when the game is ended successfully,
  i.e. the hero has completed the game objectives
  * `GAME_OVER`: this runs when the hero has lost all of his/her lives
  without completing the game objectives
  * `USER_INIT`: this function runs once when the game has just finished
  loading. It is a one-time initialization.
  * `USER_GAME_INIT`: this function runs once when a new gameplay is
  started.
  * `USER_GAME_LOOP`: this function runs once in every game loop. Use with
  care, this function can hurt performance badly!
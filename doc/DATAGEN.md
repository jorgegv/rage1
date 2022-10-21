# DATAGEN

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
	DATASET	home

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

        ATTR    INK_YELLOW | PAPER_BLACK | BRIGHT
        ATTR    INK_YELLOW | PAPER_BLACK
        ATTR    INK_YELLOW | PAPER_BLACK
        ATTR    INK_YELLOW | PAPER_BLACK

	// ...or load both pixels and attrs from PNG
        PNG_DATA      FILE=game_data/png/btile.png XPOS=8 YPOS=8 WIDTH=16 HEIGHT=16

END_BTILE
```

`BTILE` attributes:

* `NAME`: the name of the btile
* `DATASET`: the btile will be automatically copied into any dataset that
  contains screens using this btile.  Additionally, the btile will be copied
  to the dataset specified in this attribute. This is useful for btiles used
  in the menu screen, since they must be in the `home` dataset.
* `ROWS`: number of character rows
* `COLS`: number of character columns
* `PIXELS`: pixel data.  Data must be COLS x 8 pixels (=bits) long.  Paper
  pixels must be specified as `..`, and ink pixels with `##`.  Yes, double
  characters :-). There must be ROWS x 8 PIXELS lines in the Btile definition.
* `ATTR`: specified the attributes for each of the character cells of the
  Btile. Standard z88dk ATTR definitions must be used (found in spectrum.h)
* `PNG_DATA`: instead of PIXELS and ATTR lines, pixel and attribute data can
  be extracted from a PNG image.  Arguments for this attribute are specified
  as `ARG=value` pairs separated by spacs in the same PNG_DATA line. 
  Possible arguments:

  * `FILE`: the PNG file where pixels are extracted from. File name relative
  to the repository top directory level.
  * `XPOS`, `YPOS`: pixel coordinates of the top left rectangle of pixels
  * `WIDTH`, `HEIGHT`: pixels dimensions of the rectangle of pixels
  * Attributes for the tile will be automatically assigned from the 2 colors
  used in each 8x8 cell.  If more than 2 colors are detected in a cell,
  warnings will be issued.  Also, if one of the 2 colors is black (#000000)
  it will be preferred as the background color.
  * For best results, you can use the ZX-Spectrum palette definition for
  GIMP and use it for coloring your PNG file with the tiles.
  * `HMIRROR`, `VMIRROR`: if these arguments exist and are set to 1, a
  horizontal or vertical mirror will be applied to the pixels and mask. 
  This is very useful for defining multiple sprites from one graphic asset,
  going in all direction or the other.

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
        PNG_DATA        FILE=game_data/png/sprite.png XPOS=8 YPOS=8 WIDTH=16 HEIGHT=16 FGCOLOR=000000
        PNG_MASK        FILE=game_data/png/sprite.png XPOS=8 YPOS=8 WIDTH=16 HEIGHT=16 MASKCOLOR=ff0000

        // frame 2
        PNG_DATA        FILE=game_data/png/sprite.png XPOS=24 YPOS=8 WIDTH=16 HEIGHT=16 FGCOLOR=000000
        PNG_MASK        FILE=game_data/png/sprite.png XPOS=24 YPOS=8 WIDTH=16 HEIGHT=16 MASKCOLOR=ff0000

END_SPRITE
```

`SPRITE` attributes:

* `NAME`, `ROWS`,`COLS`,`PIXELS`: these attributes are defined exactly the
  same way as in Btiles.
* `FRAMES`: sprites can be animated, this is used to specify the number of
  animation frames that will be defined. There should be enough data and
  mask pixels for all frames
* `PNG_DATA`: as in Btiles, selects pixel data from a PNG image.  The
  BGCOLOR argument is not used, only the FGCOLOR is used to select ink
  pixels. `HMIRROR` and `VMIRROR` can be used.
* `PNG_MASK`: analogous to PNG_DATA, but selects sprite mask data instead.
  The new argument MASKCOLOR is used to specify the color that will be used
  as the mask. `HMIRROR` and `VMIRROR` can be used.
* `COLOR`: The color of the sprite. Must be an INK_* Spectrum constant
* `SEQUENCE`: (optional) defines an animation sequence for a sprite. 
  Sequences can be changed at different times during the sprite lifecycle. 
  More than one sequence can be defined.  There is always a default 'Main'
  sequence (even if it onoy has one frame), with all frames in order. This
  name is reserved, and no 'Main' sequence should be defined in user data.
  Arguments:
  * `NAME`: the name for the sequence
  * `FRAMES`: the sequence of frames, comma separated (no spaces). Frames
  are numbered starting at 0 (e.g. FRAMES=0,1,2,3)

A common arrangement for sprite graphics in PNG files is to draw the sprite
in B/W (#000000, #ffffff), and the mask in red (#ff0000)

Also, there is no need for a separate PNG for each sprite. You can define
all sprites and tiles in the same PNG file, and select pixel and mask data
for each of them by using coordinates in the PNG_DATA and PNG_MASK lines.

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
	DATASET		0
	TITLE		"The Cavern"

	OBSTACLE	NAME=Tree01	ROW=8 COL=4
	OBSTACLE	NAME=Rock01	ROW=10 COL=12

	// Decoration for a hotzone must defined separately
	DECORATION	NAME=Stairs	ROW=16 COL=10
	HOTZONE		NAME=Stairs	ROW=17 COL=11 WIDTH=1 HEIGHT=2 ACTIVE=1

	ENEMY  		NAME=Ghost1	SPRITE=Ghost01 MOVEMENT=LINEAR XMIN=8 YMIN=8 XMAX=233 YMAX=8 INITX=70 INITY=8 DX=2 DY=0 SPEED_DELAY=1 ANIMATION_DELAY=25 BOUNCE=1 SEQUENCE_A=Left SEQUENCE_B=Right INITIAL_SEQUENCE=Right CHANGE_SEQUENCE_HORIZ=1

	HERO		STARTUP_XPOS=20 STARTUP_YPOS=20

	ITEM		NAME=Heart	ROW=3 COL=6 ITEM_ID=0

	CRUMB		NAME=Crumb01	TYPE=RedPill ROW=5 COL=6
	CRUMB		NAME=Crumb02	TYPE=RedPill ROW=10 COL=10

	BACKGROUND	BTILE=Back01	ROW=1 COL=1 WIDTH=30 HEIGHT=22 PROBABILITY=140

	DEFINE		GRAPH=II	TYPE=OBSTACLE   BTILE=Ice01
	SCREEN_DATA	"    (2 x GAME_AREA_WIDTH spaces)    "
	... ( GAME_AREA_HEIGHT x  SCREEN_DATA lines)

END_SCREEN
```

`SCREEN` attributes:

* `NAME`: the name of the screen, used for referencing it from other
  elements
* `DATASET`: the number of the dataset where the screen should go.  It can
be an integer number starting at 0, or the special name `home`. If no
dataset is defined for a screen, the default value `home` is used.
* `TITLE`: an optional title for the screen that can be used in the game.
The title must be enclosed between double quotes ("")
* `OBSTACLE`: places an element on the screen. The Hero can not go through
this element (=obstacle) but s/he must move around. Arguments:
  * `NAME`: the Btile that will be used to draw this obstacle
  * `ROW`, `COL`: position of the obstacle on the screen
  * `ACTIVE`: 1 if this obstacle is active, 0 if not. Obstacles can be
  activated and deactivated during the game, this setting defines the
  initial state.
  * `CAN_CHANGE_STATE`: 1 if it can change state, 0 if not. If it is ommited,
  its state will not change during the game.
* `DECORATION`: places a decoration on the screen. The hero can go over it.
  Arguments are the same as for OBSTACLEs.
* `HARMFUL`: places a harmful decoration on the screen.  The hero gets
  killed/harmed if s/he goes over it.  Arguments are the same as for
  OBSTACLEs.
* `HOTZONE`: a zone on the screen where something happens when the hero goes
  over it.  HOTZONEs are only definitions, not graphic elements, i.e.  they
  only define coordinate checks and actions to be done when inside.  If you
  want the hotzone to be decorated, you need to define a DECORATION that
  overlaps the HOTZONE (see the example). It suports the following
  arguments:
  * `ROW`,`COL`,`WIDTH`,`HEIGHT`: top-left position and width and height of
  the hot zone in char cells units
  * `X`,`Y`,`PIX_WIDTH`,`PIX_HEIGHT`: top-left position and width and height of
  the hot zone in pixel units. If both char and pixel specifications are
  used (they shouldn't!), the pixel-based ones are used
  * `ACTIVE`: 1 if this hotzone is active, 0 if not. Hot zones can be
  activated and deactivated during the game, this setting defined the
  initial state.
  * `CAN_CHANGE_STATE`: 1 if it can change state, 0 if not. If it is ommited,
  its state will not change during the game.
* `HERO`: defines hero properties in this screen. Arguments:
  * `STARTUP_XPOS`,`STARTUP_YPOS`: startup hero coordinates in this screen,
    of this is the initial screen.
* `ITEM`: positions an inventory item on the screen. Arguments:
  * `NAME`: the name of the item
  * `BTILE`: the Btile that will be used to draw the item
  * `ROW`,`COL`: top left position of the item, in char cell coordinates
* `CRUMB`: positions a crumb on the screen. Arguments:
  * `NAME`: the name of the crumb
  * `TYPE`: the crumb type, must have been defined in `GAME_CONFIG` section
  * `ROW`,`COL`: top left position of the crumb, in char cell coordinates
* `ENEMY`: defines an enemy on the screen. Arguments:
  * `NAME`: a name for this enemy.  It is _not_ needed that it matches the
    sprite name
  * `SPRITE`: the name of the sprite to be used for this enemy
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
    * `SEQUENCE_A`: (optional) name of the first animation sequence. If not
    specified, 'Main' is assumed
    * `SEQUENCE_B`: (optional) name of the second animation sequence. If not
    specified, 'Main' is assumed
    * `INITIAL_SEQUENCE`: (optional) name of the initial animation sequence.
    If not specified, 'Main' is assumed
    * `SEQUENCE_DELAY`: (optional) delay between animation sequence runs
    (screen frames)
    * `CHANGE_SEQUENCE_HORIZ`: (optional) if this flag is 1, the enemy sprite
    will switch from animation sequence A to B and viceversa when bouncing
    horizontally: sequence A for incrementing X, sequence B for decrementing X
    * `CHANGE_SEQUENCE_VERT`: (optional) if this flag is 1, the enemy sprite
    will switch from animation sequence A to B and viceversa when bouncing
    vertically: sequence A for incrementing Y, sequence B for decrementing Y

`CHANGE_SEQUENCE_HORIZ` and `CHANGE_SEQUENCE_VERT` animations should be
used separately and never together in the same enemy.

* `BACKGROUND`: defines a background as a rectangle of repeated tiles.
Arguments:
  * `BTILE`: the name of the BTILE which will be repeated
  * `ROW`,`COL`: top-left corner of the rectangle that will be filled with
  btiles
  * `WIDTH`,`HEIGHT`: width and height in char cells of the rectangle to be
  filled
  * `PROBABILITY`: a value in 0-255 which maps to the probability [0..1]
  that each filling btile is generated. Useful for generating randomized
  backgrounds: stars, grass, water, etc.
* `SCREEN_DATA`: optional lines of digraphs characters, enclosed by quotes (").
A text representation of the screen map, with the different btiles
(obstacles and decorations) drawn by 2-char sequences. See
`game_data/map/Screen03.gdata` for an example). Only OBSTACLEs and
DECORATIONs can be drawn with this method. The remaining elements (ITEMs,
HOTZONEs, etc.) must be specified with the previous commands. There must be
GAME_AREA.HEIGHT lines, and the strings must be GAME_AREA.WIDTH * 2
characters long.
* `DEFINE`: define a graph for using it in SCREEN_DATA lines. Arguments:
  * `GRAPH`: 2-char repsesentation of each character cell for the BTILE
  * `BTILE`: the btile name for this graph
  * `TYPE`: OBSTACLE or DECORATION

*Special Note:*

The order in which the elements are placed on the screen is the following:

- If SCREEN_DATA lines exist, SCREEN_DATA elements are generated.  There
  must be exactly GAME_AREA_HEIGHT lines, and each line must be 2 x
  GAME_AREA_WIDTH characters long (not counting the enclosing quotes).

- Remaining elements are positioned over the previous ones if there are any.

### HERO data

* This element contains the definitions for the game hero.
* At the moment, only one `HERO` element can be defined per game.

Example `HERO` definition:

```
BEGIN_HERO
        NAME            Jorge
	SPRITE		Jorge
        SEQUENCE_UP     JorgeUp
        SEQUENCE_DOWN   JorgeDown
        SEQUENCE_LEFT   JorgeLeft
        SEQUENCE_RIGHT  JorgeRight
        STEADY_FRAMES   LEFT=5 RIGHT=7 UP=8 DOWN=9
        ANIMATION_DELAY 6
        HSTEP           1
        VSTEP           1
        LIVES           NUM_LIVES=3 BTILE=Live
	DAMAGE_MODE	ENEMY_DAMAGE=1 HEALTH_MAX=2 IMMUNITY_PERIOD=100 HEALTH_DISPLAY_FUNCTION=my_hero_display_health
        BULLET          SPRITE=Bullet01 SPRITE_FRAME_UP=0 SPRITE_FRAME_DOWN=1 SPRITE_FRAME_LEFT=2 SPRITE_FRAME_RIGHT=3 DX=3 DY=3 DELAY=0 MAX_BULLETS=4 RELOAD_DELAY=3
END_HERO
```

`HERO` attributes:

* `NAME`: a name for the hero
* `SPRITE`: the sprite to use when moving in each of the four directions. 
  The sprite can also have its own animation sequences.  The names used must
  match previous SPRITE graphic definitions
* `SEQUENCE_UP, SEQUENCE_DOWN, SEQUENCE_LEFT, SEQUENCE_RIGHT`: the names of
  the animation sequences that will be used for the four directions.
* `STEADY_FRAMES`: the sprite frame numbers to be used when the hero is in a
  steady position after having moved in a given direction.
* `ANIMATION_DELAY`: delay between hero animation frames, in 1/50s (screen
  frames)
* `HSTEP`, `VSTEP`: movement increments for the hero
* `LIVES`: number of lives
* `DAMAGE_MODE`: defines advanced configuration for the hero lives system.
  This setting is optional; if it is not specified, the simple schema of N
  lives and "enemy touch kills one life" is implemented.  Arguments:
  * `HEALTH_MAX`: (optional) health counter for each life, defaults to 1
  * `ENEMY_DAMAGE`: (optional) damage inflicted to hero health by 1 enemy
  impact, defaults to 1
  * `IMMUNITY_PERIOD`: (optional) period after an enemy impact during which
  the hero is immune to enemies (in frames - 1/50 s).  Defaults to 0.
  * `HEALTH_DISPLAY_FUNCTION`: (optional) the function to call when the
  health display neeeds to be updated (e.g. when a hit has been received).
  You must provide this function in some file in the `game_src` directory.
  The function must match the prototype `void my_function( void )`.
* `BULLET`: configures firing. Arguments;
  * `SPRITE`: sprite to use for the bullet. Must match a graphic sprite
    definition. Currently it _has_ to be a 1x1 cell sprite.
  * `DX`,`DY`: horizontal and vertical increments for moving bullets, in
    pixels
  * `DELAY`: delay between bullet positions (defines the speed of the
    bullet). In 1/50s (screen frames)
  * `MAX_BULLETS`: maximum number of bullets than can be active at the same
    time
  * `RELOAD_DELAY`: minimum deay between shots, in 1/50s
  * `SPRITE_FRAME_UP`, `SPRITE_FRAME_DOWN`, `SPRITE_FRAME_LEFT`,
  `SPRITE_FRAME_RIGHT`: (optional) sprite frames to use when shooting in
  each direction.  If any of them is not specified, default is 0.  This
  means that if you don't need to have different bullet graphics for
  different directions, just don't specify these and the bullets will all
  use frame 0 of the given sprite

### GAME_CONFIG data

* This element contains miscelaneous game configuration which is related to
  the game itself, and not to any oher specific elements.

Example `GAME_CONFIG` definition:

```
BEGIN_GAME_CONFIG
        NAME            TestGame
	ZX_TARGET	48
	LOADING_SCREEN	PNG=loadscreen.png WAIT_ANY_KEY=1
	CUSTOM_CHARSET	FILE=character_data.ch8 RANGE=32-90
        SCREEN          INITIAL=1
        DEFAULT_BG_ATTR INK_CYAN | PAPER_BLACK
        SOUND           ENEMY_KILLED=2
        SOUND           BULLET_SHOT=9
        SOUND           HERO_DIED=7
        SOUND           ITEM_GRABBED=1
        SOUND           CONTROLLER_SELECTED=5
        SOUND           GAME_WON=6
        SOUND           GAME_OVER=10
        GAME_FUNCTION   TYPE=MENU NAME=my_menu_screen FILE=my_menu_screen.c CODESET=1
        GAME_AREA       TOP=1 LEFT=1 BOTTOM=21 RIGHT=30
        LIVES_AREA      TOP=23 LEFT=1 BOTTOM=23 RIGHT=10
        INVENTORY_AREA  TOP=23 LEFT=21 BOTTOM=23 RIGHT=30
        DEBUG_AREA      TOP=0 LEFT=1 BOTTOM=0 RIGHT=15
	TITLE_AREA	TOP=23 LEFT=10 BOTTOM=23 RIGHT=19
	BINARY_DATA     FILE=game_data/png/loading_screen.scr SYMBOL=binary_stored_screen COMPRESS=1 CODESET=0
	CRUMB_TYPE	NAME=RedPill BTILE=RedPill ACTION_FUNCTION=redpill_grabbed FILE=crumb_functions.c CODESET=1
        TRACKER         TYPE=arkos2 IN_GAME_SONG=in_game_song FX_CHANNEL=0 FX_VOLUME=10
        TRACKER_SONG    NAME=menu_song FILE=game_data/music/music1.aks
        TRACKER_SONG    NAME=in_game_song FILE=game_data/music/music2.aks
	TRACKER_FXTABLE	FILE=game_data/music/soundfx.aks
END_GAME_CONFIG
```

`GAME_CONFIG` attributes:

* `NAME`: the name of the game (Imagine :-)
* `ZX_TARGET`: set this to `48` or `128` to compile in those modes. `128`
  mode includes automatic memory banking of assets.
* `LOADING_SCREEN`: allows to specify a 256x192 PNG/SCR image which will be used
  as a loading screen. One of `PNG` or `SCR` is mandatory, and only one can
  be specified. Arguments:
  * `PNG`: The specified PNG will be converted to ZX format (SCR) and used
  for the SCREEN$ block
  * `SCR`: The specified SCR file (exactly 6912 bytes long) will be used
  as-is for the SCREEN$ block
  * `WAIT_ANY_KEY`: (optional) if set to 1, the game will stop just after
  loading and wait for a keypress (so that the loading screen can be enjoyed
  :-) ). If not set or set to 0, game will start right after loading.
* `CUSTOM_CHARSET`: allows to specify a custom character set for the game.
  Arguments:
  * `FILE`: the file with character data, 8 bytes per character.  It must be
  exactly 768 bytes long (CH8 format)
  * `RANGE`: (optional) two integer values seperated by a dash (e.g. 
  32-90).  Restricts the character range that will be replaced by the custom
  character set.  Only the data for the replaced chars will be included in
  the final game, so this is a way for reducing memory usage for the font if
  you are not using all characters in your game texts.
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
* `GAME_FUNCTION`: defines a special game function. These
  functions must be included in sources under `game_src` directory. All
  these functions take and return no arguments, and must work over the
  global `game_state` variable. Arguments:
  * `TYPE`: the type of function. Possible values:
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
  * `NAME`: the function name. Must follow C function naming conventions
  * `FILE`: (optional) the file name where the function is. If not
    specified, the name of the file will be assumed the same as the function
    name, plus a `.c` extension
  * `CODESET`: (optional) the codeset where the function must reside. If not
    specified, or we are compiling for 48K model, all GAME_FUNCTIONs will go
    into lowmem area
* `GAME_AREA`, `LIVES_ARES`, `INVENTORY_AREA`, `DEBUG_AREA`, `TITLE_AREA`:
definitions for the different screen areas used by the game.  All of then
accept the following aguments:
  * `TOP`, `LEFT`, `BOTTOM`, `RIGHT`: (values are obvious)
* `BINARY_DATA`: allows to include pieces of binary data from a given file
in your game.  Useful for embedding data that can be generated with external
tools.  More than one instance of `BINARY_DATA` can be specified, for
including different data pieces.  Arguments:
  * `FILE`: mandatory, specifies the file that contains the raw data that
    will be included in the game.
  * `OFFSET` and `SIZE`: optional, both specify the initial offset and size
    in bytes of the binary data that will be extracted from the file.  Ie
    they are not specified, the whole file is included
  * `SYMBOL`: mandatory, it specifies the name of the C symbol that your
    data will be made known as inside the program (that is, the variable
    name).  This symbol is declared as a byte array ( `uint8_t
    my_symbol_name[]` )
  * `CODESET`: optional, if using 128K mode it indicates the CODESET where
    the data will be loaded.  If not specified, the data block will be
    loaded in the home bank, and so it will be available from any function
    in your game.  If it is specified, the data will be available only from
    the functions that live in the same CODESET as the data. If compiling in
    48K mode, this setting is ignored and the data goes into the the main
    codeset.
  * `COMPRESS`: optional, if set to 1 the data will be stored compressed in
    the generated variable, ready to decompress with one of the ZX0
    decompression functions.

* `CRUMB_TYPE`: defines a new CRUMB type which may later be used in `SCREEN`
  definitions.  Arguments:
  * `NAME`: mandatory, specifies the name of the crumb type
  * `BTILE`: mandatory, specifies the BTILE that will be used to draw crumbs
    of this type
  * `ACTION_FUNCTION`: (optional) specifies an additional function that will
    be called every time a crumb of this type is grabbed by the hero.  The
    function receives as a parameter a pointer to the `struct
    crumb_location_s` data structure that the hero walked over.
  * `FILE`: (optional) the file name where the function is.  If not
    specified, the name of the file will be assumed the same as the function
    name, plus a `.c` extension
  * `CODESET`: (optional) the codeset where the function must reside.  If
    not specified, or we are compiling for 48K model, it will go into lowmem
    area

* `TRACKER`: enables a music tracker in your game. Currently Arkos Tracker 2
  is the supported player, but other trackers can be easily integrated (open
  an issue if you need another one!). Arguments:
  * `TYPE`: (optional) currently only `arkos2` value is supported, and
    specified by default
  * `IN_GAME_SONG`: (optional) the song that will be played during the game.
    The supplied name must be that of a song defined with a `TRACKER_SONG`
    directive (see below).
  * `FX_CHANNEL`: (optional) channel to be used for sound effects. Only 0,1
    or 2 can be specified
  * `FX_VOLUME`: (optional) volume to use for sound effects. Range is 0-16
    (low to high), and default value is 16

* `TRACKER_SONG`: specifies a tracker song to be used for the game.  More
  than one song may be included.  Arkos files (`.aks`) can be used directly,
  provided that you configure your Arkos Tracker 2 directory so that RAGE1
  can use the proper conversion tools.  Arguments:
  * `NAME`: the name of the song. It must be a valid C identifier (in short:
  letters, numbers and `_`)
  * `FILE`: the path of the song file

* `TRACKER_FXTABLE`: specifies a tracker sound effects table to be used for
  the game, in Arkos 2 format (`.aks`). Again, make sure you configure
  correctly your Arkos Tracker 2 directory. Arguments:
  * `FILE`: the path of the sound FX file

# FLOWGEN

Flowgen was a separate utility for compiling game scripts into code that can
be included in your game.  FLOWGEN functionality has been integrated into
DATAGEN.  The description of the data format and rules below still applies.

Code generated by Flowgen is intended to be run from the check_game_flags()
function which is part of the main game loop.

## Basic design

* All code generated by Flowgen is configured with rules based on the
  pattern WHEN-CHECK-DO

* All rules are assigned to one or more map_screens (from now on, "screens")

* Only the rules for the current screen are executed, for performance
  reasons

* Each screen has its own lists of rules that are executed at different
  moments in the game loop. Think of these lists as "hooks" for each screen
  to be called at certain times.

* For optimizing rule storage, there is a global rule table where each rule
  is defined but with no screen information. Then, each screen has
  several tables of pointers to rules to be executed at each moment. The
  different moments are identified by the WHEN clauses in the rules

* When a new "WHEN" moment is identified (that is: when we identify a new
  condition in the game loop where it would be interesting to execute
  hooks), we should define a new table in the flow_rules element of the
  map_screen_s struct (see below for the places already identified).

* The code at different points in the game loop only activates and
  deactivates game flags

* These game flags are processed and acted upon in check_game_flags()
  function. Most processing must take place here. There may be some reactions
  that may be executed at the place of detection (?)

* Before executing check_game_flags(), the function run_flow_rules() should
  be executed. This function checks and executes the FLOWGEN rules, it is
  the main loop of the scripting engine, and all FLOWGEN code is executed
  here

* A separate field `user_flags`, analogous to `game_flags`, exists in
  `game_state` structure. This user flags can be manipulated through FLOWGEN
  rules

* An additional field `loop_flags` exists in `game_state` structure.  This
  field contains flags for checks that are run during each iteration of the
  game loop, and that must be processed later in the same loop run.  All
  loop flags are reset at the beginning of each run of the game loop.

* FLOWGEN rules can check game flags and loop flags (but can not modify
  them), and can check and modify user flags.

* FLOW VAR IDs are 0-255. VAR values can also be 0-255.

## Rule design

All rules follow the pattern:

`[WHEN_TO_RUN] [WHAT_TO_CHECK] [ACTION_TO_EXECUTE]`

* WHEN_TO_RUN: the point where the rule is checked and action executed if
check is successful. Options: 
  - [x] ENTER_SCREEN
  - [x] EXIT_SCREEN
  - [x] GAME_LOOP

* WHAT_TO_CHECK: the condition to check. Options:
  - [x] GAME_FLAG_IS_SET <flag>
  - [x] GAME_FLAG_IS_RESET <flag>
  - [x] LOOP_FLAG_IS_SET <flag>
  - [x] LOOP_FLAG_IS_RESET <flag>
  - [x] USER_FLAG_IS_SET <flag>
  - [x] USER_FLAG_IS_RESET <flag>
  - [x] ITEM_IS_OWNED <item_id> - item_id = 2^ITEM_NUMBER (in GDATA file)
  - [x] LIVES_EQUAL <value>
  - [x] LIVES_MORE_THAN <value>
  - [x] LIVES_LESS_THAN <value>
  - [x] ENEMIES_ALIVE_EQUAL <value>
  - [x] ENEMIES_ALIVE_MORE_THAN <value>
  - [x] ENEMIES_ALIVE_LESS_THAN <value>
  - [x] ENEMIES_KILLED_EQUAL <value>
  - [x] ENEMIES_KILLED_MORE_THAN <value>
  - [x] ENEMIES_KILLED_LESS_THAN <value>
  - [x] CALL_CUSTOM_FUNCTION <function_name> - function prototype: `uint8_t my_custom_check(void)`
  - [x] HERO_OVER_HOTZONE <hotzone_name>
  - [x] SCREEN_FLAG_IS_SET <flag>
  - [x] SCREEN_FLAG_IS_RESET <flag>
  - [x] FLOW_VAR_EQUAL VAR_ID=<id> VALUE=<value>
  - [x] FLOW_VAR_MORE_THAN VAR_ID=<id> VALUE=<value>
  - [x] FLOW_VAR_LESS_THAN VAR_ID=<id> VALUE=<value>
  - [x] GAME_TIME_EQUAL <value> - value: seconds since game start
  - [x] GAME_TIME_MORE_THAN <value> - value: seconds since game start
  - [x] GAME_TIME_LESS_THAN <value> - value: seconds since game start

* ACTION_TO_EXECUTE:
  - [x] SET_USER_FLAG <flag>
  - [x] RESET_USER_FLAG <flag>
  - [x] INC_LIVES <num_lives>
  - [x] PLAY_SOUND <fxid> - IDs are the ones available in sound.h for bit_beepfx
  - [x] ENABLE_TILE <tile_name>
  - [x] DISABLE_TILE <tile_name>
  - [x] ENABLE_HOTZONE <hotzone_name>
  - [x] DISABLE_HOTZONE <hotzone_name>
  - [x] CALL_CUSTOM_FUNCTION <function_name> - function prototype: `void my_custom_action(void)`
  - [x] END_OF_GAME
  - [x] WARP_TO_SCREEN DEST_SCREEN=<screen_name> [DEST_HERO_X=<xxx>] [DEST_HERO_Y=<yyy>]
  - [x] ADD_TO_INVENTORY <item_id> - item_id = 2^ITEM_NUMBER (in GDATA file)
  - [x] REMOVE_FROM_INVENTORY <item_id> - item_id = 2^ITEM_NUMBER (in GDATA file)
  - [x] SET_SCREEN_FLAG SCREEN=<screen_name> FLAG=<flag>
  - [x] RESET_SCREEN_FLAG SCREEN=<screen_name> FLAG=<flag>
  - [x] FLOW_VAR_STORE VAR_ID=<id> VALUE=<value>
  - [x] FLOW_VAR_INC VAR_ID=<id>
  - [x] FLOW_VAR_ADD VAR_ID=<id> VALUE=<value>
  - [x] FLOW_VAR_DEC VAR_ID=<id>
  - [x] FLOW_VAR_SUB VAR_ID=<id> VALUE=<value>
  - [x] TRACKER_SELECT_SONG <song_name>
  - [x] TRACKER_MUSIC_STOP
  - [x] TRACKER_MUSIC_START
  - [x] TRACKER_PLAY_FX  <fxid> - The number of the effect in your FX sound track (starts at 1!)

A rule may have no CHECK directives, in which case its DO actions will
always be run at proper moment specified in the WHEN directive. This can be
used for e.g. running a custom function on each game loop iteration, or
doing something specific on entering/exiting a screen (e.g. setting an
ULAplus palette, or selecting a specific music track)

## FLOWGEN Gdata file syntax

The data files for FLOWGEN rules are also in GDATA format.

Example FLOWGEN data file:

```
BEGIN_RULE
        SCREEN  Screen01
        WHEN    GAME_LOOP
        CHECK   LOOP_FLAG_IS_SET F_LOOP_ENEMY_HIT
	(...)
        DO      SET_USER_FLAG 0x0001
        DO      INC_LIVES 0x0001
END_RULE
```

Syntax:

* `BEGIN_RULE` and `END_RULE`: start and end of a rule definition

* `SCREEN`: mandatory. Specifies what screen this rule must be run on. If
  the rule is assigned to the special screen `__EVENTS__` then it is
  assigned to the global game events rule table

* `WHEN`: mandatory, except if screen is `__EVENTS__`.  Specifies when this
  rule must be run.  See previous section for valid values.  For
  `GAME_LOOP`: the rule will be checked on every iteration of the game loop,
  so be careful with rules in this table, they may heavily affect game
  performance.  When the rule is assigned to the `__EVENTS__` special name,
  the `WHEN` clause is ignored if present

* `CHECK`: specifies a condition to be checked.  See previous section for
  valid values.  There must be at least one `CHECK` and there may be more
  than one.  All the checks will be run in order and their results ANDed to
  get the final check result. Short circuit evaluation is used here, so put
  first the rules that are more likely to give a false result

* `DO`: specifies an action to be run if all the `CHECK` conditions in this
  rule are true. There must be at least one `DO` and there may be more than
  one. All the actions will be executed in order.

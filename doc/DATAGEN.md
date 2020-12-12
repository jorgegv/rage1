# Datagen

A utility to generate tiles, sprite, screen definitions, etc. from a game
data text description file. Data files have a .gmap extension.

## Data text file syntax

~~~
// This is a comment

// tile 1
BEGIN_BTILE
	NAME	xxxx
	ROWS	m
	COLS	n
	PIXELS	..####....######..##
	...
	ATTR	INK_GREEN | PAPER_BLACK | BRIGHT | FLASH
	...
	TYPE	TT_DECORATION | TT_OBSTACLE | ...
END_BTILE
...

// Sprite 1
BEGIN_SPRITE
	NAME	xxxx
	ROWS	m
	COLS	n
	PIXELS	..####....######..##
	...
	MASK	##....####......##..
	...
	ATTR	INK_GREEN | PAPER_BLACK | BRIGHT | FLASH
	...
END_SPRITE

// screen 1
BEGIN_SCREEN
	NAME	xxxx
	BTILE	btile_name row col
	...
	SPRITE	sprite_name LINEAR xmin ymin xmax ymax dx dy
	SPRITE	sprite_name MOVES IN_CIRCLES centerx centery radius numpos
	...
END_SCREEN
...
~~~

## Concepts

* Comments start with // and go through end of line

* Blank lines and white space are ignored

* A map is composed of screens.  Screens can contain Btiles (decoration,
  obstacles), sprites, etc.

* Map geometry is not defined, it must be defined elsewhere.  The tool just
  generates a linear array of Btiles and a linear array of screen
  definitions, with the provided names.

* Element names must be unique in their class.  Names can contain only
  [A-Z][a-z][0-9]_

## Notes on Btiles

* Btile sizes are specified as rows anc cols (8x8 cells)

* Btiles are internally composed by 8x8 pixel SP1 tiles, but this is handled
  transparently for you by the engine.

* Pixel data in PIXELS lines must be COLS*8 characters (=bits) long. '..'
  must be used for paper pixels, '##' must be used for ink pixels. Yes,
  double characters :-)

* There must be ROWS x COLS ATTR lines

* Pixels and attributes are specified in left to right, top to bottom order.

## Notes on Screens

* In BTILE lines, only previously defined BTILEs can be referenced

## Notes on Sprites

* Sprites are defined in the same way as Btiles. The new component is MASK,
  which sets the sprite mask when moving over the background.

* At the moment, Sprites are defined of type MASK. More types TBD.

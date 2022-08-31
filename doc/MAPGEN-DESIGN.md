# MAPGEN Design

## BTILE matching

The main map will be processed in 8x8 cells.

At the start, a dictionary of BTILEs is created so that they can be
identified quickly when processing the main map:

- The BTILES are read from the PNG and TILEDEF files

- A hash for the top-left 8x8 cell of a BTILE is generated for easier searching

- Each BTILE has a list of the hashes of its cells (direct index)

- Each hash has a list of the BTILEs that have that cell at its top-left (reverse index)

After all BTILEs have been read and processed, the main map is processed:

- The main map dimensions must be a multiple of the R*8 and C*8 values
  (cells to pixels).  This is checked at the beginning and the main map is
  rejected if it does not meets this requirement

- The main map is processed in 8x8 cells and hashes for each of the cells
  are calculated and stored for each position in the map.

- The map is then processed in blocks of R x C cells (map screens)

- Inside each of those blocks: for each cell, the cell hash is matched
  against the BTILE hash reverse index, and all candidate BTILEs for
  that cell are found.

- With this method, BTILEs can be identified and their names and positions
  added to the list of BTILES for the current screen

- Also, a flag for "successfully identified" cells should be noted, so that
  at the end of the process, if all cells have been identified, the screen
  can be considered a success, and otherwise report that some of the BTILEs
  could not be identified. Similar code to that of the SCREEN definition
  with digraphs, etc.

## HOTZONE identification

- The main map will be processed by pixels (hotzones are specified in pixel
  coords)

- When a Hotzone overlaps 2 different screens, oit will be considered a
  screen-switching hotzone, and additional FLOW rules will be generated that
  make screen switching automatic

- For screen-switching hotzones to work correctly, it is needed to specify
  the top-left coordinates (in cells) of the game area, and also the
  dimensions of the hero sprite (in pixels). All these parameters must be
  passed as CLI options

### User-defined Hotzone identification

- Hotzones are drawn on the main map as solid rectangles of a given color
  (default green: 00FF00)

- The matching routine finds the rectangles.

- If a Hotzone is fully inside a given screen, it is defined in the GDATA
  file for that screen with the proper dimensions and position. It is up to
  the game developer to write the FLOW rules needed to do something when the
  hero walks over that Hotzone. These rules are trivial, just look at the
  source for the example game.

- If a Hotzone overlaps 2 screens, it is assumed to be a screen-switching
  In this case, the hotzone is split into two separate hotzones, one for
  each screen. Also, in addition to the definition of both hotzones inside
  each screen (as usual), FLOW rules are generated for the screen switches
  to be triggered when the hero walks over them.

### Automatic Hotzone generation

- Optionally, it can be required that the MAPGEN tool generates the
  screen-switching hotzones automatically

- These zones are matched as rectangles at the vertical and horizontal
  borders between screens, and must have a given background color.  That is,
  the algorithm searches for "holes" of background color that communicate
  pairs of screens and automatically defines a hotzone that overlaps the two
  screens so that it is identified as a screen-switching hotzone later.

- The width of automatically generated hotzones (either horizontal or
  vertical) can be specified with a CLI option and by default it's 8 pixels.

- The background color can also be specified with a CLI option and it's
  black (000000) by default.

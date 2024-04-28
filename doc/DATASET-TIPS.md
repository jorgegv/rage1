# DATASET TIPS

Some optimization tips and techniques about the design of your screens and
their placement in DATASETs follow, in order to allow for the maximum number
of screens possible.

- Try to repeat tiles (up to your creativity) if possible, and group
  together screens that share the most tiles, in the same DATASET. Tile
  sharing allows for more screens, since they are only stored once for all
  screens in the same DATASET.

- If your game has several screens grouped by "stages" (whatever that mean),
  try to separate the tiles in different tilesets for each stage, and on
  each screen use only tiles beloging to that tileset.  This will allow for
  better tile sharing (as indicated in the previous point).

- On the other hand, you can allow for full creativity, using tiles from all
  your tilesets in any of your screens, but then you will have some amount
  of duplicated tiles between tilesets (i.e. the same tile can be found in
  more than one DATASET). This will also reduce the number of possible
  screens.

- For this last case, RAGE1 has the `dsopt.pl` tool that analyzes your map
  files taking into account all of the tiles used on each screen, and then
  groups the screens N at a time generating datasets that share the most
  tiles between each of their screens.

- So in general: if you want lots of screens, try to repeat tiles, and to
  group together screens which use the same tilesets. If you prioritize the
  graphics quality and creativity over the number of screens, then use the
  tiles as you wish (RAGE1 will take care of optimizing everything as much
  as it can), but be aware that you will not have as much screens.

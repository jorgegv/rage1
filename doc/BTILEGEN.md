# BTILEGEN Tool

A tool for automatically generating the GDATA BTILE definitions of tiles
which have previously been drawn on a PNG file, and some associated
metadata.

BTILEGEN receives as arguments one or more PNG files, which are supposed to
contain tile data (that is, tiles drawn according to a 8x8 grid).

An associated TILEDEF file is expected to exist in the same directory of the
PNG file, but with .tiledef extension (e.g.  `town_tiles.png` ->
`town_tiles.tiledef`). The TILEDEF file contains one line per BTILE, with
its definition values: name, start row, start column, width and height.
Comments can be introduced by character `#` up to the end of the line, and
blank lines are ignored. On each line, fields are separated by blanks.

Example:

```
# example comment

town_house_1	0 2 3 4
```

This would define the tile at (row,col) = (0,2), and having 3 columns and 4
rows. All dimension and position values are cell (8x8) based, as is common
in Spectrum graphics.

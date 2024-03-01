# MEMORY BUILD TIPS

You can mangle the RAGE1 memory layout for the 128K games to a certain
amount, mainly by moving around the INT table and stack, which are
approximately in the middle of the memory map.

You can move the INT table and stack by tweaking the `iv_table_addr` value
in the `interrupts_128` section in file `etc/rage1-config.yml`, respecting
the restrictions explained in the comments (i.e.  the standard memory
settings for an IM2 int table in the Speccy), and also the following
guidelines:

- The INT table can NEVER be stored below address 0x8000. This is the
  absolute minimum value you can set in `iv_table_addr`

- Uncompressed datasets are stored during the game at address 0x5B00, and
  above it a bit of space is also needed for the sprites used in the
  dataset, just beloe thw INT table.  So if you move the INT table up in
  memory, you can have bigger DATASETs.

- Bigger uncompressed DATASETs mean there are more possibilities of sharing
  tiles between the screens belonging to each DATASET, but take care: the
  _compressed_ datasets must fit into the upper memory banks (they are
  stored there and decompressed in realtime to 0x5B00 during the game).

- Also you need to take into account the code that is running in lowmem.

- In general, use the `make mem` target after a successful build to get a
  detailed memory map, and see if you can move things from one place to
  another and where the free space is.

- When you have a big game and your memory banks are almost full, it's a bit
  of a trial and error process until you find the optimal layout of your
  game's assets.

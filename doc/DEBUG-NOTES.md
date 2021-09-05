# DEBUG NOTES

## Debug session 3/9/21

Debugging program execution after banking implementation.

* All code up to init_hero runs apparently without problems
  - BASIC loader works OK [verified]
  - Loader bank switching routine works OK [verified]
  - Bank code blocks are loaded on each bank (BASIC loader switches banks and loads
  code correctly on each bank)  [verified]
  - Game starts normally  [verified]
  - init_memory -> OK  [verified]
  - init_sp1 -> OK (apparently, but it does something on the screen. It does
  not hang -> possible problem?  )  [verified]
  - init_interrupts -> OK  [verified]
  - init_hero -> OK (but takes a "long" time, an observable delay) [verified]
  - init_bullets -> HANGS

* The program does not reach  run_main_game_loop call in main.c

Initial diagnosis:

- init_hero probably corrupts something (it allocates sprites, so SP1 and/or
  heap may be affected)

- init_bullets hangs (also allocates sprites)

- Possible problem with SP1 initialization

- Possible problem with heap size and position

## Debug session 4/9/21

- Variable _current_assets was being allocated over $C000 -> Moved into
  lowmem/asmdata.asm

- Variable _dataset_map is allocated over $C000 -> Problems!!  It is
  accessed by dataset_activate for copying the dataset data to low memory,
  but when it is accessed the memory bank is switched!!  Wrong values are
  read!!  It should be placed in low memory!!  -> r1banktool modified to
  generate dataset_map data in lowmem asm.


--------
WIP: To be continued

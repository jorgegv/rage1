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

## Debug session 5/9/11

- dataset_activate fixed, works OK
- Game makes it to init_hero and hangs there
- Step into that, hangs in call to sprite_allocate
- Into sprite_allocate, sp1_CreateSpr works OK, hangs just after loop with
  sp1_AddColSpr. Warning: the 's' pointer contains the sprite allocated via
  malloc, but it contains 0xC407!! This is upper memory, but the heap is
  supposedly located at 0x5B00 + 4000, so this is definitely wrong!

-> Points to problems specifying the heap, follow that lead.

- Changed memory.c: in addition to calling heap_init to initialize the heap
  area, it is needed also to set the heap base address by direct assigment
  to _malloc_heap variable.

- With this change, the whole game works OK (menu, control selection, game
  play, game end, sounds), but there is still a glitch with the background
  tile: it shows the bitmap for the hero sprite.

-> Follow lead of some sprite corruption for the ' ' tile.

- SP1's 512 byte array that specifies the pointers for each of the 256 basic
  tiles (at $F000) should be filled with pointers to ROM character tables,
  but instead it's filled with 0's. ????

- SP1 initializes tiles 32-127 with pointers to the ROM chars...  but those
  are stored on the 48K ROM (ROM 1), so this only works if ROM 1 is active! 
  Our default value output to port $7FFD was mapping ROM 0, which is the
  128K editor ROM (which we really don't care about), and this is the reason
  for the corrupted graphics.  We should have ROM 1 (48K) always active.

-> Modified function memory_switch_bank to add a default configuration
  including the mapping of ROM 1 everytime that a new memory bank is
  selected to be paged.

- GAME FULLY WORKS NOW IN 128k MODE!!

--------

# BANKING DESIGN

## Rationale

Since the SP1 library and the RAGE1 engine itself have started to occupy
quite a lot of memory, there is fewer memory dedicated to game assets
(screens, sprites, tiles, rules, etc.).

There are a few memory optimizations pending, but the real one would be to
switch to 128K compatible games, so that we can use the other 64K for those
assets.

The main problem with that is that paging in the 128K model takes place in
the upper 16K page (base 0xc000), but this is occupied by the SP1 library
data and some other structures. So it is not possible to use it to have
regular assets during the game, but only as a kind of "external" storage.

So the assets reside in whatever page they are loaded at start, but when
they are needed (entering, exiting screen) they must be loaded into "low"
memory: a chunk of memory below 0xc000 which will be reserved for this
purpose.

## Memory layout

We have tried to have a memory map as packed as possible, and using all of
the memory holes for the game, if possible.

The low memory map for our game is as follows:

```
0000-3FFF: ROM			(16384 BYTES)
4000-5AFF: SCREEN$		( 6912 BYTES)
5B00-7FFF: LOWMEM BUFFER	( 9472 BYTES)
8000-8100: INT VECTOR TABLE	(  257 BYTES)
8101-8180: STACK		(  128 BYTES)
8181-8183: "jp <isr>" OPCODES	(    3 BYTES)
8184-D1EC: C PROGRAM CODE	(20585 BYTES)
D1ED-FFFF: SP1 LIBRARY DATA	(11795 BYTES)
```

## Implementation

We will distinguish two phases for our program: the loading phase, and
the execution phase.

### Loading Phase

The Loading phase starts by loading a BASIC loader that does the following:

- Set RAMTOP to 0x6fff (that's enough space to run the complete loader)

- Load a minimal bank switching ASM routine at an address below 0x8184 (e.g. 
  0x7000)

- For each of the banks 1, 3, 4 ,6 ,7:

  - Switch page frame (0xc000) to bank N using the mentioned banking
    routine (POKE + RAND USR)

  - Load code to position 0xc000.  Data compiled for this section must be
    ORG 0xc000 (I think z88dk does this for you if using `#pragma BANK_N` )

- Switch page frame back to bank 0

- Load the C program code to position 0x8184. This code should be at most
  20585 bytes (from 0x8184 to 0xd1ec: 0xd1ed-0xffff is reserved for SP1
  data structures)

- Start program execution at 0x8184 (RAND USR)

The BASIC loader can be compiled to TAP format with BAS2TAP.

### Execution phase

- Program execution starts at 0x8184

- Stack pointer is set to 0x8181 at startup

- Interrupts are disabled at startup

- The first thing the program does is setting up interrupts: 0x8000-0x8100
  is the 257 byte interrupt vector table, which contains byte 0x81 at all
  positions. It also patches "jp <isr>" into addresses 0x8181-0x8183. It
  then sets IM2 mode and enables interrupts.

- At this point, all the memory map is setup and the code is in place.  The
  buffer at 0x5b00-0x7fff will be used as the LOW MEM buffer for copying
  assets from high memory banks: when they are needed, page frame (0xc000)
  is switched to the source bank, content is copied, then bank 0 is switched
  back.

- The memory area from 0x5b00 normally contains system variables and BASIC
  program code, but since we are not returning to BASIC ever, we can freely
  use this area for our own purposes.

- The main bank switching routine (not to be confused with the BASIC loader
  switching routine) must be based in memory below 0xc000, since it will
  switch the memory range above that point.  This means it should be
  included in main.c to ensure it is linked at the beginning of the memory
  map.

- From this moment, the program can follow the design points above to switch
  banks and copy assets to the low memory buffer as needed during the game.

- Since we are based in Bank 0, and we will be always switch a bank, copy
  data, and switch again to bank 0, we will always know the bank we have
  selected.  This means we don't need to keep track of the last value
  written to port 0xfffd, and just write the bank we need to map into port
  0xfffd:

  - We will be always selecting banks 0-7, so we will be using bits 0-2 in
    port 0xfffd

  - Bit 3 = 0 selects normal screen

  - Bit 4 = 0 selects 128K ROM (which is irrelevant for us)

  - Bit 5 = 0 means memory banking is kept enabled (which is what we want)

## Design Keys for Game Data

- All of the game code must reside in low memory (below 0xc00), as a rule of
  thumb. Code that is used in exceptional situations (menu, start, game end,
  game over conditions) can be in other banks provided that it does not call
  anything outside its own bank or the main bank.

- There are some assets that are used all the time and must reside in low
  memory: character set, game state, etc.

- There are other assets that are used only at given times, and that can be
  loaded and unloaded on-demand: sprites, tiles, screen rules, sounds, etc.

- For the loadable assets that are reusable, a simple optimization is to
  have them organized in SETS.  I.e.  sprite sets, btile sets, sound
  sets, screen sets.

- A SET is a group of assets that can be loaded at once.

- The MAP is an array of screens.  SCREENs can be arranged in sets, so the
  MAP contains not only the screen number, but tuples (screen set, index)

- The SCREEN has new fields for BTILE, SPRITE, SOUND and RULE sets that are
  the ones used for that screen.  The indexes for elements on each screen
  are always referred to the current set of elements of the given type.

- When ENTER_SCREEN or EXIT_SCREEN, the current sets for all element types
  are checked, and switched to the new sets if needed before/after
  switching screen.

- For switching element sets, the whole set is copied from high to low
  memory as needed.  With this schema, only the sets for sprites, btiles,
  sounds, screens and rules that are used by the current screen are in low
  memory.

- Element sets need not be big.  In fact, they should be as small as
  possible, in order to fit in low RAM.  We can have a big number of sets
  in high memory, up to 80 KB (5 x 16KB banks: 1,3,4,6,7)

## References

- https://zxspectrumcoding.wordpress.com/2019/11/17/z88dk-bank-switching-part-1/

- https://worldofspectrum.org/faq/reference/128kreference.htm

- https://github.com/andybalaam/bas2tap
 
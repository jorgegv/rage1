# BANKING DESIGN

## Rationale

Since the SP1 library and the RAGE1 engine itself have started to occupy
quite a lot of memory, there is fewer memory dedicated to game assets
(screens, sprites, tiles, rules, etc.).

There are a few memory optimizations pending, but the real one would be to
switch to 128K compatible games, so that we can use the other 96K for those
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
0000-3FFF: ROM                  (16384 BYTES)
4000-5AFF: SCREEN$              ( 6912 BYTES)
5B00-7FFF: LOWMEM BUFFER + HEAP ( 9472 BYTES)
8000-8100: INT VECTOR TABLE     (  257 BYTES)
8101-8180: STACK                (  128 BYTES)
8181-8183: "jp <isr>" OPCODES   (    3 BYTES)
8184-D1EC: C PROGRAM CODE       (20585 BYTES)
D1ED-FFFF: SP1 LIBRARY DATA     (11795 BYTES)
```

## Implementation

We will distinguish two phases for our program: the loading phase, and
the execution phase.

### Loading Phase

The Loading phase starts by loading a BASIC loader that does the following:

- Set RAMTOP to 0x7fff (that's enough space to run the complete loader)

- Load a minimal bank switching ASM routine at an address below 0x8184 (e.g. 
  0x8000)

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
  buffer at 0x5b00-0x7fff will be used as the LOWMEM buffer for copying
  assets from high memory banks: when they are needed, page frame (0xc000)
  is switched to the source bank, content is copied, then bank 0 is switched
  back.

- The upper part of the LOWMEM buffer is used as the heap. Since only SP1 is
  using the heap for sprite allocation, its size is automatically calculated
  by DATAGEN.

- The memory area from 0x5b00 normally contains system variables and BASIC
  program code, but since we are not returning to BASIC ever, we can freely
  use this area for our own purposes.

- The main bank switching routine (not to be confused with the BASIC loader
  switching routine) must be based in memory below 0xc000, since it will
  switch the memory range above that point.  This means it should be
  included in main.c to ensure it is linked at the beginning of the memory
  map.

- Since we are based in Bank 0, and we will be always switch a bank, copy
  data, and switch again to bank 0, we will always know the bank we have
  selected.  This means we don't need to keep track of the last value
  written to port 0xfffd: if we just write the bank number to port 0xfffd,
  we get the behaviour we want (but see the following sections for a
  followup):

  - Bits 0,1,2 will be always used for selecting banks 0-7

  - Bit 3 = 0 selects normal screen

  - Bit 4 = 1 selects 48K ROM (which is irrelevant for us - but we need to
    select ROM1, the 48K ROM: SP1 uses the char definition data from there!)

  - Bit 5 = 0 means memory banking is kept enabled (which is what we want)

  - Bits 6,7 are unused

From this moment, the program can follow the design points above to switch
banks and copy assets to the low memory buffer as needed during the game.

## Linking Issues

When copying a block of data/code from one memory address to another,
there is one critical thing that we must take into consideration: pointers.

### Code Pointers

Code pointers are mainly used as the destination for CALL and JP
instructions.

If the destination address is outside the memory block that we are copying,
then everything is fine: the address is valid and will not be overwritten
(hopefully!) when moving our code around.

If the destination is inside the memory block that we are copying, things
change substantially: the code was originally compiled and placed on a given
base address, and the JP's and CALL's into code that falls inside this
memory range match the ORG directive that was used for the compilation of
that code.

When copying that code elsewhere, we are essentially changing the ORG for
it, and for this reason we need to fix the destination addresses in all
those calls, so that they match the new base address where the code is being
copied.  Typically, these fixes would be as easy as substracting the
original ORG address and then adding the new base address to the pointer
which is being fixed.

There is a problem with that: we need a list of the byte positions in our
code where pointers need to be fixed, i.e. a _relocation table_. This means
some overhead for our code.

Adding to that problem, the relocation table will need to be processed at
runtime, so we also need the code to do it and patch the code accordingly
after copying it...which is more code overhead.

### Data Pointers

With data pointers the situation is similar: if the data contains pointers
that point to addresses outside the range that is being copied, everything
is fine. But if the data pointers point to some addresses inside our range,
those pointers also need to be fixed in the same way as described for the
code pointers.

This means those pointers need to be added to the relocation table described
before, which means more overhead.

### Possible solutions

The issues analyzed above are exactly the ones that are solved by a specific
program: the linker.

Without going into much details: when the compiler generates code and data
and they contain memory addresses, these addresses are generated as if the
code and data was going to be loaded at address 0x0000, and a relocation
table is generated alongside with the code, with the list of pointers that
would need to be fixed. All that info (code, data and relocation table) is
included in the object (`*.o`) file.

A linker knows precisely the final memory map for our program, and using the
information from the object files, it arranges them in memory and patches
code and data using the relocation tables in order to match the final
address where everything will be loaded.

So one possible solution would be to implement this schema in the code/data
that will be paged in our program: relocation tables and a "linker" function
that moves code around and fixes pointers.

But there is other possible solution: if what we have described here is the
work done by a linker, why not use the standard Z88DK linker to do this job?
Obviously our Z88DK linker, which runs on Linux/Windows, is not going to run
directly on the Spectrum, but we can make it do the work for us and arrange
everything so that we can just move things around in the Spectrum and know
that everything works.

So we will do the following setup:

- The code/data that will be paged will be included in separate binaries.
  They will be compiled and linked as standalone blobs with no external
  references.

- Those sections (DATASETs) will have an ORG 0x5B00, which is the base
  address of our LOWMEM area (i.e.  where all that code/data will be copied
  when needed at runtime).  This means that code/data will _already_ be
  prepared to run at that address.  _This_ is the job that the Z88DK linker
  will do for us.

- The DATASETs will need to fit in the LOWMEM area (which is at most ~9 kB
  minus the heap size).  Heap size is calculated automatically from the game
  definition (it depends mostly on the number of simultaneous sprites on
  screen).

- When the DATASET is needed at runtime, it will be copied to base address
  0x5B00, which matches the ORG used for compiling the section, and so
  everything will work fine without further fixes.

- A small Dataset Mapping Table (DMT) will be needed within the main section
  (non-paged) code, that will map each dataset to the physical bank (0-7)
  the offset inside the bank from which data will be copied into LOWMEM, and
  the size of the DATASET.  See dataset.h for the structure of the DMT
  entries.
  
## Design Keys for Game Data

- All of the game code must reside in low memory (below 0xC000), as a rule of
  thumb. Code that is used in exceptional situations (menu, start, game end,
  game over conditions) can be in other banks provided that it does not call
  anything outside its own bank or the main bank. Code that runs and
  finishes without referring any other code or data besides its own memory
  bank or the home banks is also suitable for this (e.g. a 128K music
  player, which is run 50 times per second.)

- There are some assets that are used all the time and must reside in the
  home bank: character set, game state, etc.

- There are other assets that are used only at given times, and that can be
  loaded and unloaded on-demand: sprites, tiles, screens, flow rules,
  sounds, etc.

- For the loadable assets that are reusable, a simple optimization is to
  have them organized in DATASETS.

- A DATASET is a group of assets that can be loaded at once.

- The MAP is made of screens.  Each screen is defined inside a DATASET. 

- Each screen has a GLOBAL index which is the screen identifier, and a LOCAL
  index into the DATASET screen table.

- There is a SCREEN DATASET MAP, which maps the GLOBAL index to a structure
  that contains the DATASET each screen is defined into, and the LOCAL index
  for that screen into the DATASET screen table.

- The assets that are used in that screen must be stored in the same
  DATASET.  The indexes for elements on each screen are always referred to
  the set of elements of the given type which is defined in the same
  DATASET.

- When ENTER_SCREEN, the needed DATASET is requested.  The dataset selection
  routine checks if the dataset has changed or not, and does nothing in the
  later case.

- For switching DATASETs, the whole set is copied from high to low memory as
  needed.

- We can have a big number of DATASETs in high memory, up to 80 KB (5 x 16KB
  banks: 1,3,4,6,7). Even more with ZX0 compression.

## Banked Game Data Implementation

- A game DATASET (sprites, map, rules, btiles, etc.) must be self contained:
  pointers can only reference data that is either inside the same DATASET or
  the home memory bank.  This allows to compile a game DATASET to a single
  binary with no external dependencies.

- An ASSET RECORD structure is generated as the first element in the DATASET
  source file generated.  It contains pointers to the asset tables inside
  the DATASET.

- The DATASET binary file is compiled at a fixed ORG address of 0x5B00 (this
  is the address where it will be loaded at runtime).  It is generated with
  the "__orgit" trick by Dom
  (https://z88dk.org/forum/viewtopic.php?p=19796#p19796) so that it is
  compiled to the desired base address 0x5B00.  Since the ASSET RECORD
  structure is the first data item in the DATASET, and the address is known,
  we can access all the internal game data assets from the main code by
  using this structure and its internal pointers.  It is also linked as
  standalone binary files with no CRT.

  Example commands:

~~~
zcc +zx -compiler=sdcc -clib=sdcc_iy dataset1.c -o dataset1.bin --no-crt
~~~

- DATASETs are compressed with ZX0 after being compiled.  Compressed
  datasets are then laid out in BANKs, and their coordinates (dataset
  number, bank number, offset inside bank, size) are saved, so that several
  datasets can be included in the same bank.

- The DATASET MAP TABLE (DMT) must be generated and included in main
  (non-banked) memory.  This table contains tuples of (dataset, memory bank,
  address offset, size), which are used to decompress the dataset into the
  final 0x5B00 runtime address.

- The data in the DMT is used at runtime to select the proper DATASET and
  switch to the neded memory bank when starting the game, switching screens,
  ending game, etc.

## Issues with banked screen data and asset state during the game

Some game assets (e.g.  btiles, enemies,...) have some kind of state which
is reset at game startup, and changes during the game (flags field, movement
coordinates, etc.); this state is currently stored in the asset definition
structure for some asset types.

This is fine when the assets don't "move" in memory; but when memory banking
is introduced, assets are stored compressed in "read-only" memory and can
reloaded to the working memory zone at any time.  That state would then get
reset when switching out a dataset and bringing it back in later.  So asset
configuration and state need to be in different data structures.

State needs to be global (i.e.  home bank), so it needs to be as small as
possible.  Possibly `flags` fields need to be reduced to 8-bit instead of
the current 16-bit ones.

Layouts based on "flag byte for all game enemies", "flag byte for all game
btiles", etc.  do not scale.  Tables will be mostly static, with only a few
entries changing.  We need to have state only for the assets that can
change.

Not ALL state needs to be global.  Some state may not matter being reset
when loading a dataset, e.g.: movement state for the enemies.  Main state
that needs to be maintained is ALIVE/DEAD, ENABLE/DISABLE, etc.

Design:

- For each screen, a state table for all its assets that need some stored
  state.  An array `screen_ScreenXX_asset_state` of `struct asset_state_s`
  stored in home bank.

- Pointers to all screen state tables are included in the global
  `game_state` structure for each screen.

- DATAGEN: in the screen config data, replace every place where state is
  stored (e.g.  `flags` fields) with a byte that is an index into the
  containing screen's asset state table.

- Since the number of elements with state on each screen will likely be very
  small (enemies that can be killed, tiles that can be enabled, etc.), the
  state table for each screen will be just a few bytes.  This means also
  that the asset index into the the state table for that screen can be just
  1 byte.

- Since the asset state needs to be reset at game startup, we need the
  initial value for that and that value needs to be also stored somewhere. 
  If we store it in the asset configuration, we would need to walk all
  datasets at game startup in order to get the default values for state
  assets.  So an alternative solution is store the default value together
  with the runtime asset state in the home bank.  This way we do not need to
  walk dataset at startups, and game reset is immediate.

- We would have then: a) a `struct asset_state_info_s` with fields
  `asset_state` and `asset_initial_state` (a 2-byte struct); b) a table of
  `struct asset_state_info_s` for each screen, which contains the current
  state of the changing assets in that screen; c) a field `state_index` in
  each asset configuration, which is the index for that asset into the state
  table described in b); and d) a pointer in `game_state` to the array of
  pointers to asset state tables for each screen.

- Index 0 is reserved for the state of the screen itself

- Since the `struct asset_state_info_s` is 2 bytes long, the index can be
  127 as a maximum, and there is maximum of 128 state-changing assets per
  screen (which is more than enough).  We will use the value $FF
  for the `state_index` field in asset configuration, to indicate that the
  asset does NOT have an associated state (we can define it as an
  ASSET_NO_STATE constant).  The $FF value is an illegal value for the
  index, since all indexes must be <= 127.

## Single source compiling for 48/128 (banked/non-banked) mode

- The current banked assets can be accessed via the `banked_assets` global
  variable.  This a pointer that is initialized at program startup to a
  fixed value of 0x5B00, since datasets are always loaded there and the
  asset record for the dataset is always at that address.

- Additionally to the regular banked datasets, we have a `home_dataset`
  which is always placed at regular program memory (i.e.  it is not stored
  on a memory bank and it is _not_ loaded at 0x5B00).

- The global variable `home_assets` is also a pointer initialized at program
  startup and it always points to the `home_dataset` asset record.

- The `home_dataset` has the same structure of a banked dataset (but in
  regular memory) and can have the same types of assets as a regular
  dataset.

- The `home_dataset` is used for assets that must be always present.  That
  is at least:

  - BTiles that are used for drawing the game menu
  - Hero sprites
  - Bullet sprites

- Each asset must be store in the same DATASET as the screen where it is
  used. So the DATASE must be defined for a SCREEN, and it is propagated to
  all assets used in it.

- Dataset switches occur on ENTER_SCREEN events, so there must be a global
  map stored in regular (non-banked) memory, which maps the screen->dataset
  relationship (global variable `screen_dataset_map`) and the global->local
  index for the screen.

- A `game_config` setting selects if the game is to be compiled in for a 48K
  or 128K Spectrum (e.g.  `spectrum_target` directive, with values
  `48/128`), and the game is compiled differently:

  - If configured for 48K mode, the `home_assets` and `banked_assets` both
    point to the `home_dataset`, which is expected to fit in the regular 48K
    RAM,.  Also, a simplified BASIC loader is generated which does not load
    anything in the memory banks, and bank switching routines are
    conditionally compiled off the main program.

  - If configured for 128K mode, `home_assets` points to the `home_dataset`
    and `banked_assets` points to the currently selected dataset at 0x5B00. 
    Also, the banking BASIC loader is used for loading bank data, and all
    memory banking routines are compiled in and used.

## References

- https://zxspectrumcoding.wordpress.com/2019/11/17/z88dk-bank-switching-part-1/

- https://worldofspectrum.org/faq/reference/128kreference.htm

- https://github.com/speccyorg/bas2tap

- https://www.z88dk.org/wiki/doku.php?id=libnew:examples:sp1_ex1

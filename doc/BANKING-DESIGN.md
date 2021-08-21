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

- Since we are based in Bank 0, and we will be always switch a bank, copy
  data, and switch again to bank 0, we will always know the bank we have
  selected.  This means we don't need to keep track of the last value
  written to port 0xfffd: if we just write the bank number to port 0xfffd,
  we get the behaviour we want (but see the following sections for a
  followup):

  - Bits 0,1,2 will be always used for selecting banks 0-7

  - Bit 3 = 0 selects normal screen

  - Bit 4 = 0 selects 128K ROM (which is irrelevant for us)

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

- The code/data that will be paged will be included in separate code
  sections.  Arbitrary sections can be defined by using #pragmas in C code,
  and they will be output as separate `.bin` or `.tap` files by the
  compiler/linker.

- Those sections will have an ORG 0x5B00 (also selectable by #pragmas),
  which is the base address of our LOWMEM area (i.e.  where all that
  code/data will be copied when needed at runtime).  This means that
  code/data will _already_ be prepared to run at that address.  _This_ is
  the job that the Z88DK linker will do for us.

- Since the sections will need to fit in the LOWMEM area (which is ~9 kB), a
  good maximum size would be 8 KB.  This allows for 2 sections to fit in a high
  BANK, and we do not waste too much of the LOWMEM area.

- Each 8 kB section will be loaded at the proper BANK address (0xC000 or 0xE000)
  by the BASIC loader.

- When the section is needed at runtime, it will be copied to base address
  0x5B00, which matches the ORG used for compiling the section, and so
  everything will work fine without further fixes.

- A small Memory Mapping Table (MMT) will be needed within the main section
  (non-paged) code, that will map each section to the physical bank (0-7)
  and the top or bottom half of the bank that will be copied into LOWMEM. 
  The structure for each entry could be:

  - Bits 0-2: physical bank (0-7)

  - Bit 3: bank half (0: low 0xC000; 1: high 0xE000)

### Possible enhancement

There is one implicit assumption in all the above analysis and design: that
the data/code in the paged sections is immutable and does not need to change
during the game.

But what if we wanted to be able to make modifications in tha section while
running, and _keep_ those modifications?  It would be interesting that after
paging the memory area out and back in later, the changes are still there. 
I.e.  make the section a READ/WRITE section, and not a READ ONLY one.

There are two small changes to the design in previous sections that would
allow us to do this:

- Add an additional R/W bit to each MMT entry, which would be as follows:

  - Bits 0-2: physical bank (0-7)

  - Bit 3: bank half (0: low 0xC000; 1: high 0xE000)

  - Bit 4: RO/RW (0: readonly; 1: read/write)

- Depending on bit 4 of the MMT entry, the section would be treated
  differently when paging: it would only be copied to LOWMEM when paging it
  in (for RO sections); or it would be copied to LOWMEM when paging it in
  and _back_ to the bank when paging it out (for RW sections)

- For this to work, now we _do need_ to know which of the physical banks is
  currently selected (since we may need to copy data back to it).  So we
  need to keep it somewhere.

- There are performance considerations, since each time a section is paged
  in/out, a whole block of data might need to be copied back and forth (once
  for a RO section, and twice for a RW section).  So this is definitely not
  a mechanism to be used frequently, or inside loops, but sporadically.

- It would be interesting to explore reducing the section size (to e.g. 
  4kB).  It would make it easier to use it more often during the game (since
  copying data would be faster, less data involved), but it would make it
  more inconvenient since code in a section cannot call code in other
  sections (only code in the main section).

- It would also be interesting to explore copying functions different from
  LDIR based ones.  Copying 8 kB with an LDIR instruction takes around 50ms.

This is indeed a paging memory manager design :-)

## Design Keys for Game Data

- All of the game code must reside in low memory (below 0xc000), as a rule of
  thumb. Code that is used in exceptional situations (menu, start, game end,
  game over conditions) can be in other banks provided that it does not call
  anything outside its own bank or the main bank.

- There are some assets that are used all the time and must reside in the
  home bank: character set, game state, etc.

- There are other assets that are used only at given times, and that can be
  loaded and unloaded on-demand: sprites, tiles, screens, flow rules,
  sounds, etc.

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

## Banked Game Data Implementation

- A game DATASET (sprites, map, rules, btiles, etc.) must be self contained:
  pointers can only reference data that is either inside the same DATASET or
  the home memory bank.  This allows to compile a game DATASET to a single
  binary with no external dependencies.

- An ASSET RECORD structure is generated as the first element in the DATASET
  source file generated.  It contains pointers to the asset tables inside
  the DATASET.

- The DATASET binary file is compiled at a fixed ORG address of 0x5B00 (this
  is the address where it will be loaded at runtime).  Since the ASSET
  RECORD structure is the first data item in the DATASET, and the address is
  known, we can access all the internal game data assets from the main code
  by using this structure and its internal pointers.

- DATASETs are compressed after being compiled, and inserted as binary data
  (a named byte array) in a BANKED DATA SOURCE FILE.

- BANKED DATA SOURCE FILEs are generated with the "__orgit" trick by Dom
  (https://z88dk.org/forum/viewtopic.php?p=19796#p19796) so that they are
  compiled to base address 0xC000 (the address where they will be loaded and
  accessed at runtime). They are also linked as standalone binary files with
  no CRT, and a TAP file is created with no loader, only the CODE section.
  Example commands:

~~~
zcc +zx -compiler=sdcc -clib=sdcc_iy bank3.c -o bank3 --no-crt
z88dk-appmake +zx --org 0xC000  --noloader -b bank3_code_compiler.bin -o bank3.tap
~~~

- The DATASET REFERENCE TABLE (DRT) must be generated and included in main
  (non-banked) memory.  This table contains triplets of (dataset, memory bank,
  source address), which are used to decompress the dataset into the final
  0x5B00 runtime address.

- The data in the DRT is used at runtime to select the proper DATASET and
  switch to the neded memory bank when starting the game, switching screens,
  ending game, etc.

## References

- https://zxspectrumcoding.wordpress.com/2019/11/17/z88dk-bank-switching-part-1/

- https://worldofspectrum.org/faq/reference/128kreference.htm

- https://github.com/speccyorg/bas2tap

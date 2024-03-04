# SINGLE USE BLOBS

A RAGE1 game uses some big buffers:

- In 128K games: the DATASET decompression buffer at $5B00-$8000 (or higher,
  depending on the location of the INT table), about 9K

- In both 128K and 48K games: the SP1 buffers at $D1ED-$FFFF, about 11K

These buffers are overwritten when the game is initialized and also while
running, but they are empty just after program load.

They could be used for storing code and data that can be run at the very
beginning of the game initialization, just when it has just finished
loading, knowing that it will be wiped away when the real game is started. 
This can be ideal for **intros/demos/ credits, etc.** that are shown/run
just once after game load.

- For the SP1 buffer (uncontended memory, SP1BUF): the intro code at that
  address can be directly loaded and run from there.

- For the DATASET buffer (contended memory, DSBUF): in case the intro code
  needs to run from uncontended memory (e.g.  beeper tunes), it can be
  temporarily _swapped_ with an area in higher non-contended memory, run the
  intro code, and then restore the contents of the non-contended area (which
  have been saved previously).  Or it can be run directly from there if
  contended memory is not an issue for the intro code.

So we could define a maximum of 2 single use blobs (SUBs), one for SP1
buffer and other for DATASET buffer.  The changes needed for RAGE1 are
indicated in the next sections.

## Build changes

- There will be two new directories under `game_src`: `game_src/sub_sp1buf`
  (for SP1 SUB) and `game_src/sub_dsbuf` (for DATASET SUB)

- The code inside each of those two directories must be completely
  self-contained.  They need to be completely independent programs that can
  run standalone.

- A private Makefile skeleton will be provided to compile the same code
  either as a standalone TAP file (for easy testing and debugging) or as a
  headerless TAP file which can be used in the global RAGE1 build.

- The global RAGE1 Makefile will use the targets in the private Makefile for
  the binary output.

## DATAGEN changes

- The `GAME_CONFIG` section will add support for a new `SINGLE_USE_BLOB`
  element, similar to this:

```
GAME_CONFIG
	(...)
	SINGLE_USE_BLOB TYPE=SP1|DS DS_ORG_ADDRESS=XXXX ORDER=N
	(...)
END_GAME_CONFIG

```

- The SP1 or DS type indicates if the SP1BUF or the DSBUF will be used for the
  SUB.

- For the SP1 type, the code will run directly from the SP1BUF address
  (0xD1ED, in uncontended memory)

- For the DS type, the code can run directly from the DSBUF address
  (0x5B00, in contended memory).

- If uncontended memory is needed with the DS type (e.g.  because a beeper
  sound engine is used), a DS_ORG_ADDRESS parameter can be specified.  In
  this case, the SUB will be temporary swapped to that address before
  execution, and the contents at that address saved to 0x5B00.  The SUB code
  will be then run from DS_ORG_ADDRESS, and when it returns, the saved data
  wil be restored to the DS_ORG_ADDRESS from 0x5B00.

- Checks will be implemented to enable DSBUF SUB only in 128K mode. SP1BUF
  SUB will be allowed in both modes.

- The conditional compilation BUILD_FEATURE_SINGLE_USER_BLOB,
  BUILD_FEATURE_SINGLE_USER_BLOB_DSBUF and
  BUILD_FEATURE_SINGLE_USER_BLOB_SP1BUF #define macros will be generated.

- A table in an ASM file will be generated with the SUB data needed for
  loading and running the code at the proper addresses

- An ORDER parameter can be used to indicate how the SUBs must be executed.
  If no ORDER is specified, SP1BUF will be run first, then DSBUF. If ORDER
  is provided, the SUBs will be run in ascending ORDER.

## RAGE1 startup changes

- The SUBs will run at the very beginning of the program, even before any
  initialization takes place.  This is to ensure that the RAGE1 engine
  initializes everything after all SUBs have run, so no unexpected changes
  can happen.

- Only the SUBs configured in GAME_CONFIG will be run.

- If both are configured, then if no ORDER is specified, SP1BUF will be run
  first, then DSBUF.  If ORDER was provided, the SUBs will be run in
  ascending ORDER.

- All SUB related initialization and execution will only be brought into the
  main game if the functionality is used, via the conditional compilation
  macros mentioned before (BUILD_FEATURE_xxxx)

## SUB initialization

- The SUB initialization and run function will be the first function called,
  before even any of the RAGE1 init routines.

- The SUB initializacion code will use the data table previously generated
  by DATAGEN and use the ROM routine LD_BYTES to load the headerless TAPs
  into the proper places in RAM.  The user will just sense one or two
  additional loading blocks.

- When using DSBUF, both SUBs must NOT enable interrupts at any time.  The
  SUBs are called with interrupts disabled, and should stay this way.  If
  they were run with the normal interrupt configuration (i.e.  the ROM ISR
  routine), some system variables in the SYSVARS area (0x5B00 and above)
  will be updated by the ROM ISR, and will corrupt the data we just loadad
  at that address, with catastrophic consequences.

- After the SUB(s) have been loaded in place, they will be run in the order
  specified in the previous section, with interrupts disabled.

- When the SUBs return, the rest of the RAGE1 game startup will continue. 
  RAGE1 will take full control over the machine and the DSBUF and SP1BUF
  will be wiped and used for their intended purpose during the game.  At
  this point, the entry code stored in DSBUF and SP1BUF will be fully gone.

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

## DATAGEN changes

- The `GAME_CONFIG` section will add support for a new `SINGLE_USE_BLOB`
  element, similar to this:
```
GAME_CONFIG
	(...)
	SINGLE_USE_BLOB NAME=<name> LOAD_ADDRESS=XXXX ORG_ADDRESS=YYYY RUN_ADDRESS=ZZZZ
	(...)
END_GAME_CONFIG

```

- `LOAD_ADDRESS` indicates where the blob will be loaded in the load stage

- `ORG_ADDRESS` (optional) indicates where the blob must be located for
  running.  If not specified LOAD_ADDRESS will be used as ORG_ADDRESS.

- `RUN_ADDRESS` (optional) indicates the entry point that will be called to
  execute the code.  If not specified, ORG_ADDRESS will be used as
RUN_ADDRESS.

- `NAME` is a regular RAGE1 identifier used to refer to the proper SUB.

- If LOAD_ADDRESS is different from ORG_ADDRESS, the block wil be exchanged
  temporarily from LOAD_ADDRESS to ORG_ADDRESS before running, and restored
  to the original location after it has finished.  The memory block at
  ORG_ADDRESS is also temporarily saved at LOAD_ADDRESS, so nothing is lost.

- The possibility of this temporary swap is intended for code that can be
  loaded in free contended memory (e.g.  the decompression buffer at 0x5B00)
  but needs to run in uncontended memory (e.g. because it uses an advanced
  beeper routine).

- Addresses can be specified in decimal, or in hex notation, with '0x' or
  '$' prefixes

- Checks will be implemented to enable DSBUF SUB only in 128K mode. SP1BUF
  SUB will be allowed in both modes.

## Loadertool changes

- The regular ASM loader will be modified to also load SUBs after all banks
  have been loaded.  The loader code will load, swap (if needed) and run
  the SUB code before jumping to the main program.

- The SUBs will be loaded and run in the same order as they are specified in
  the GAME_CONFIG directive.

- The SUBs will start their execution at the address indicated in their
  `RUN_ADDRESS` parameter (or the defaults indicated above), with
  _interrupts disabled_.

- SUBs must NOT enable interrupts at any time.  The SUBs are called with
  interrupts disabled, and should stay this way.  If they were run with the
  normal interrupt configuration (i.e.  the ROM ISR routine), some system
  variables in the SYSVARS area (0x5B00 and above, or BANK 7 at 0xD200) will
  be updated by the ROM ISR, and will corrupt the data we just loaded at
  that address, with catastrophic consequences.

## Build changes

- For each SUB there will be a directory under `game_src` called
  `sub_<subname>`, where `subname` is the name specified with the NAME
  parameter described above.

- The code inside each of those directories must be completely
  self-contained.  They need to be completely independent programs that can
  run standalone.

- A private Makefile skeleton will be provided to compile the same code
  either as a standalone TAP file (for easy testing and debugging) or as a
  headerless TAP file which can be used in the global RAGE1 build. This can
  be copied to the SUB directory as a starting point.

- The global RAGE1 Makefile will use a specific `sub_bin` target in the
  private Makefile for the binary output, which will be called `sub.bin`,
  and another one `sub_tap_nohdr` for generating a headerless TAP file.

- The loader tool will be modified to gather information about the SUBs and
  generate additional code for loading and running them before jumping to
  the main program.

## RAGE1 startup changes

- The SUBs will run befre any RAGE1 initialization has taken place, even
  before the `main()` function has been called.  This is to ensure that the
  RAGE1 engine initializes everything after all SUBs have run, so no
  unexpected changes can happen.

- Only the SUBs configured in GAME_CONFIG will be run.

- When the SUBs return, the rest of the RAGE1 game startup will continue. 
  RAGE1 will take full control over the machine and the DSBUF and SP1BUF
  will be wiped and used for their intended purpose during the game.  At
  this point, the entry code stored in DSBUF and SP1BUF will be fully gone.

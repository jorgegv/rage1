# CODESET Design

This document describes the model for code that can be executed from the
high memory banks, so that low memory can be freed for all-time assets,
game state, etc.

This design builds on the previous design for banking and DATASETs (see
[BANKING_DESIGN.md](BANKING-DESIGN.md)), and enhances it for supporting
CODESETs. A thorough understanding of that document is very recommended
before reading this one.

## What is a CODESET

Expanding on the DATASET concept (that is: a set of data assets which is
stored compressed in high memory banks and it is decompressed to a fixed
buffer in low memory when it is needed), the CODESET has a similar
philosophy and design, but with the following important differences:

- It is not compressed

- It is not read-only

- It is loaded at address 0xC000 (the high memory bank base address)

- It is mapped at 0xC000 with the regular memory banking operations

- Code can be executed directly from the bank, with some restrictions (this
  is of course the main feature of this design)

## Design constraints

The design constraints for a CODESET are:

- It can only change DATA either in the global state or in its own memory
  bank, but not in other memory banks.

- It can only run or call CODE  either in the low memory area or in its own
  memory bank, but not in other memory banks.

- The CODESET is loaded at a fixed address of 0xC000

- If no CODESET functions are included in the game, the CODESET
  infrastructure should not be compiled in.

Beware: SP1 code and data (for example) are stored in low memory + bank 0,
so they can't be called from any CODESET!

## Data structures and memory layout

- A CODESET owns a memory bank. Banks dedicated to CODESETs cannot be used
  for DATASETs.

- Similar to DATASETs, each CODESET has at address 0xC000 a data structure
  of type `struct codeset_assets_s` which contains info about the assets in
  the CODESET: pointers to low memory data structs, and a table of the
  functions that are callable from outside the CODESET.

- All CODESET functions have the same prototype: void f(void);

- The local `struct codeset_assets_s` in CODESETs is initialized at program
  startup with pointers to low memory data structures: `game_state`,
  `home_assets`,`banked_assets`.

- CODESET functions receive no parameters and return void.  All accesses to
  low memory data from the CODESET functions has to be done via the pointers
  set up in its assets structure.

- A global table `all_codeset_functions`is generated in low memory with data
  for all the CODESET functions in all CODESETS.  A global index is assigned
  to each function.  The function data includes the CODESET where it lives,
  and the local index into the CODESET function table.  The
  `all_codeset_functions` table is indexed with the global function index to
  get the CODESET and the local function index in that CODESET.

## Mechanism for calling a CODESET function from low memory

- Function `codeset_call_function` (in `engine/src/codeset.c`) allows
  calling a given function given its global index.

- The `codeset_call_function` function does the following tasks to invoke
  the codeset function requested:

  - Index the `all_codeset_functions` table with the global function index
    received as its parameter, to get the codeset number and the local
    function index into its codeset

  - Index the `codeset_info` table with the codeset number from the previous
    step to get the memory bank number which we need to activate

  - Switch to the new memory bank (via call to `memory_switch_bank`
    function)

  - Access the `codeset_assets_s` structure at the beginning of the codeset
    (fixed address 0xC000), use the local function index obtained in the
    first step to access the codeset functions table and invoke the
    function.

  - Switch back to bank 0 and return

- As it was said before, the codeset functions accept no parameters and
  return no value.  All interaction with the program has to be done via the
  global `game_state` variable and the asset pointers that are setup with
  the codeset init function.

## Mechanism for calling low memory code from a CODESET function

(TBD)

## DATAGEN and BANKTOOL options for CODESETs

(To be refined)

- Parts of the RAGE1 Engine code can be moved to CODESETs, and also game
  functions specified as GAME_FUNCTIONS in GDATA files

- CODESET #0 is reserved for engine code and is mapped to memory bank 4
  (uncontended, for speed reasons), the other 4 memory banks (1,3,5,7) can
  be used for other CODESETS or DATASETs.

DATAGEN Changes:

- Directive GAME_FUNCTIONS changes to GAME_FUNCTION and specifies a single
  function.  Before, several functions could be defined in the same line,
  but this unnecesarily complicates the definition for multiple attributes
  for the same function.

- New syntax: GAME_FUNCTION NAME=function_name TYPE=MENU,INTRO,GAME_END,GAME_OVER
  CODESET=1 FILE=function_name.c

- The FILE component is optional.  If it exists, it will be associated to
  the function; if it is not, it will be assumed that the function lives in
  a file called function_name.c in the `game_src` directory for your game

- With the above changes, the DATAGEN tool can generate a list of functions
  with their names, types, codeset and filenames for each one.  This list
  should be dumped in the internal_state.dmp intermediate file.

BANKTOOL Changes:

- It reads the intermediate dump file from DATAGEN, as usual

- Besides generating the DATASET files into directory
  `build/generated/datasets`, it will also generate the CODESET files in
  dedicated directories under directory `build/generated/codesets/XX`, being
  `XX` the codeset number.

- It accepts 2 new parameters for specifying the lists of banks to be used
  for DATASETs and CODESETs (numbers, comma separated)

- It uses the new function list generated by DATAGEN to layout the functions
  in CODESETs: for each function it copies the associated file to the
  directory belonging to the associated codeset for that function

- The 128K BASIC loader generated by BANKTOOL must be modified to take into
  account the loading of the new CODESETs (= banks)

- In 48K mode everything goes into low memory and the codeset function calls
  are #defined to be just calls to the regular functions, with no CODESET
  translation step.

Makefile changes:

- The Makefile has rules and targets similar to those for the DATASET
  builds, which generate more BANK_N.BIN and associated .TAP files which are
  used to build the final TAP.

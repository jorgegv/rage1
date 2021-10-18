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

- It can run or call CODE  either in the low memory area or in its own
  memory bank, or in other memory banks via the `codeset_call_function`
  function

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
  be used for other CODESETS or DATASETs (Temporary: to be revisited)

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

- Besides generating the DATASET files into directory
  `build/generated/datasets`, it will also generate the CODESET files in
  dedicated directories under directory
  `build/generated/codesets/codeset_XX.src`, being `XX` the codeset number.

- It uses the new function list to layout the functions in CODESETs: for
  each function it copies the associated file to the directory belonging to
  the associated codeset for that function

BANKTOOL Changes:

- The 128K BASIC loader generated by BANKTOOL must be modified to take into
  account the loading of the new CODESETs (= banks)

- In 48K mode everything goes into low memory and the codeset function calls
  are #defined to be just calls to the regular functions, with no CODESET
  translation step.

Makefile changes:

- The Makefile has rules and targets similar to those for the DATASET
  builds, which generate more BANK_N.BIN and associated .TAP files which are
  used to build the final TAP.

## Implementation Notes

What DATAGEN must do for the combination of 2 different variables:

- 48K / 128K mode compilation

- GAME_FUNCTION directives have/do not have CODESET parameter

So, 4 different cases:

### Case 1: 48K MODE + NO CODESET in GAME_FUNCTION

- In 48K mode, codesets are not used

- Since no CODESET is specified, all GAME_FUNCTIONs go into `home` codeset
  (low memory)

- All codeset function call macros must be resolved to regular function calls

- No loss of efficiency, everything is resolved at C macro level

### Case 2: 48K MODE + CODESET in GAME_FUNCTION

- In 48K mode, codesets are not used

- Each GAME_FUNCTION has an associated codeset. The ones that do not
  have a codeset go into `home` codeset (low memory)

- Since codesets make no sense in 48K mode, they should be ignored when
  generating code in 48K mode

- All codeset function call macros must be resolved to regular function calls

- No loss of efficiency, everything is resolved at C macro level

### Cases 3 and 4: 128K MODE + CODESET/NO CODESET in GAME_FUNCTION

- In 128K mode, codesets ARE used

- Each GAME_FUNCTION has an associated codeset. The ones that do not
  have a codeset go into `home` codeset (low memory)

- For functions in `home` codeset, their function call macros must resolve
  to a direct function call.  For functions in other codesets, their
  function call macros must resolve to a call to codeset_call_function()

- Slight efficiency loss when calling codeset functions, since a bank switch
  is needed before and after the call

- If no GAME_FUNCTIONs have an associated CODESET, they all go into the
  `home` codeset, the BUILD_FEATURE_CODESETS macro is not defined, all
  codeset infrastructure is not compiled, and all codeset function calls
  must be resolved to regular function calls, so no loss of efficiency.

## Migration of engine code to CODESET 0

It is convenient to migrate some of the engine functionality to CODESET 0,
so that more low memory is freed for assets that need to be in low memory:
hero graphics, etc.

### Design of engine code migration to CODESET 0

- Engine code which runs in CODESETs must be stored separately, in
  `engine/codeset/N`, with N being the codeset (normally 0)

- Files under `engine/codeset/N` will not be included in the normal build
  target

- If building in 48K mode, files under `engine/codeset/N` will be copied to
  `build/game_src` so that they are included in the general compilation

- If building in 128K mode, files under `engine/codeset/N` will be copied to
  `build/generated/codesets/codeset_N.src` so that they are compiled inside
  the proper CODESET

- Engine functions that are moved to a CODESET must have a definition in
  `engine/include/rage1/codeset.h`, similar to the following:

~~~
#ifdef BUILD_FEATURE_ZX_TARGET_48
    #define CALL_ENGINE_FUNCTION_MY_FUNCTION()	(my_function())
#endif
#ifdef BUILD_FEATURE_ZX_TARGET_128
    #define CODESET_FUNCTION_MY_FUNCTION	1
    #define CALL_ENGINE_FUNCTION_MY_FUNCTION()	(codeset_call_function( CODESET_FUNCTION_MY_FUNCTION ))
#endif
~~~

- Also in `engine/include/rage1/codeset.h`, the
  `CODESET_GLOBAL_INDEX_RESERVED_MAX` must be always updated with the higher
  function ID that has been reserved for engine codeset functions.  This is
  meant so that user functions which are requested to be in codesets are
  assigned IDs starting from the next free ID.  Function IDs are
  consecutive.

- Finally, functions that have been migrated to CODESET functions must be
  always called with the above macro definition (e.g.
  `CALL_ENGINE_FUNCTION_MY_FUNCTION()`) so that the correct function call is
  resolved at compile time depending on the build type: if building for 48K,
  a regular function call will be done, and if 128K the call will be done
  through the `codeset_call_function` trampoline.

- Best initial candidates for migration to CODESET are functions that only
  access global game state or data (i.e. no display).

- Some functions may be refactored so that display calls can be diverted to
  other moments in the main game loop (e.g. via some flag in `loop_flags`),
  and those calls are avoided in the function, which may make it easy to
  migrate it to a codeset.

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

## Data structures and memory layout

- A CODESET owns a memory bank. Banks dedicated to CODESETs cannot be used
  for DATASETs.

- Similar to DATASETs, each CODESET has at address 0xC000 a data of type
  `struct codeset_assets_s` which contains info about the assets in the
  CODESET: init function, pointers to low memory data structs, and a table
  of the functions that are callable from outside the CODESET.

- All CODESET functions have the same prototype: void f(void);

- CODESETs have an init function which is called at program startup with
  parameters that are pointers to low memory data structures: `game_state`,
  `home_assets`,`banked_assets`.  The init function uses them to initialize
  the local `struct codeset_assets_s`.

- CODESET functions receive no parameters and return void.  All accesses to
  low memory data from the CODESET functions has to be done via the pointers
  set up when the init function was called.

- A global table `all_codeset_functions`is generated in low memory with data
  for all the CODESET functions in all CODESETS.  A global index is assigned
  to each function.  The function data includes the CODESET where it lives,
  and the local index into the CODESET function table.  The
  `all_codeset_functions` table is indexed with the global function index to
  get the CODESET and the local function index in that CODESET.

## Mechanism for calling a CODESET function from low memory

- A function `codeset_call_function` exists to call a given function by its
  global index.

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


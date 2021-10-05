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

- Similar to DATASETs, each CODESET has at address 0xC000 a table of data
  for all the functions contained in it. Data for each function is function
  address (maybe more?)

- All CODESET functions have the same prototype

- CODESET functions receive a parameter which is a pointer to a struct with
  low memory information, that is, pointers to low memory data: game_state,
  home_assets, asset_state table, etc.  All low memory access from the
  CODESET functions has to be done via these pointers.

- A global table is generated in low memory with data for all the CODESET
  functions in all CODESETS.  A global index is assigned to each function,
  and the data for that function includes: the CODESET where it lives, and
  the local index into the CODESET function table, in a similar way as the
  dataset assets mappings are currently done

## Mechanism for calling a CODESET function from low memory

...

## Mechanism for calling low memory code from a CODESET function

...

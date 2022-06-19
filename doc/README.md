# RAGE1 Game library

## Quick Start

* **NEW!** [TUTORIAL](tutorial/INDEX.md): a detailed walkthrough of a full
  game creation, using as an example the first phase of Famargon, my little
  Spectrum family game

* [REQUIREMENTS.md](REQUIREMENTS.md): requirements needed to compile and run

* [USAGE-OVERVIEW.md](USAGE.md): how to use the engine to create your own
  game - Start with this one!

## General information

* [TOOLS.md](TOOLS.md): an overview of the RAGE1 tools that can be found in
  the `tools` directory

* [DATAGEN.md](DATAGEN.md): design and manual of DataGen, a game data
  generation and scripting tool (sprites, tiles, items, game flow,
  conditions, actions, etc.)

* [RECIPES.md](RECIPES.md): common behaviours which are commonly used in
  adventure games, and how you would implement within RAGE1

* [FUSE-DEBUG.md](FUSE-DEBUG.md): debugging aids implemented in RAGE1 if you
  are using FUSE spectrum emulator

## Design details

THe following documents decribe the internals of several subsystems in RAGE1
and their implementation details. Please read carefully if you wish to
contribute to the engine!

* [DESIGN.md](DESIGN.md): general design of the game flow and main loop

* [OPTIMIZATIONS.md](OPTIMIZATIONS.md): some general directions on
  optimizing code and data for Z80

* [MAP-SCREEN-DATA-DESIGN.md](MAP-SCREEN-DATA-DESIGN.md): internal design
  for the text-mode map compiler.

* [MEMORY-MAP.md](MEMORY-MAP.md): memory map for a RAGE1 game

* [BANKING-DESIGN.md](BANKING-DESIGN.md): describes how banking is
  implemented for using the extra memory banks available in the 128K
  Spectrum models

* [CODESET-DESIGN.md](CODESET-DESIGN.md): describes how RAGE1 stores extra
  code (not data!) in higher memory banks

* [BANKED-FUNCTIONS.md](BANKED-FUNCTIONS.md): describes how extra code
  stored in CODESETs can be used and called from the main game code

* [CONDITIONAL-COMPILATION.md](CONDITIONAL-COMPILATION.md): describes the
  conditional compilation techniques used in the RAGE1 source so that only
  the used functionality is included in the final binary

* [ROADMAP.md](): lists released versions with main functionalities, and
  future versions with expected features

## Obsolete documents

* [TODO.md](TODO.md): general checklist of desired items for the game/engine
  (obsolete, use GitHub issue list)

* [DEBUG-NOTES.md](DEBUG-NOTES.md): a trace of a couple of debug sessions
  held while implementing 128K support. Only interesting for historical
  purposes, and if you like reading about some debugging/deductions...

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RAGE1 (Retro Adventure Game Engine, release 1) is a ZX Spectrum game engine written in C and Z80 assembly, built on top of the SP1 sprite library. It targets both 48K and 128K Spectrum models. Games are defined via `.gdata` data files and compiled using z88dk with SDCC backend.

## Build Commands

Environment setup (Linux only, not needed on Windows/Cygwin):
```bash
source env.sh
```

Build the default game (uses ZX_TARGET from game config):
```bash
make build
```

Force a specific target:
```bash
make build48                          # Force 48K build
make build128                         # Force 128K build
```

Build a specific game:
```bash
make build target_game=games/minimal
make build target_game=/path/to/external/game
```

Build all test games (CI validation):
```bash
make all-test-builds
```

Build a single test game:
```bash
make build-minimal
make build-mapgen
```

Run in FUSE emulator:
```bash
make run
```

Memory usage report:
```bash
make mem
```

Create a new game from template:
```bash
make new-game target=<path-to-new-game-dir>
```

## Toolchain

- **Compiler**: z88dk with SDCC backend (`zcc +zx`, `sdcc_iy` clib)
- **Compression**: z88dk-zx0 (ZX0 algorithm for datasets)
- **BASIC loader**: bas2tap
- **Data generation**: `tools/datagen.pl` (Perl) - parses `.gdata` files and generates C source
- **Map generation**: `tools/mapgen.pl` and `tools/btilegen.pl`
- **Bank management**: `tools/banktool.pl`, `tools/loadertool.pl`
- **Perl 5** with modules: Data::Compare, List::MoreUtils, GD, YAML, Algorithm::FastPermute, Digest::SHA1

## Architecture

### Directory Structure

- `engine/src/` - Core engine C source (game loop, hero, enemies, sprites, collision, map, flow rules, memory management, etc.)
- `engine/include/rage1/` - Engine headers
- `engine/banked_code/` - Code that runs from banked memory (128K mode)
- `engine/lowmem/` - Code that must reside in low memory
- `engine/loader48/`, `engine/loader128/` - BASIC loaders per target
- `tools/` - Perl/shell build tools (datagen, mapgen, banktool, etc.)
- `games/` - Test games used for CI and as examples (default, minimal, mapgen, blobs, crumbs, etc.)
- `etc/rage1-config.yml` - Engine configuration (interrupt vectors, base addresses, banked function definitions)
- `build/` - Generated build artifacts (created during build, not in repo)

### Game Data Structure

A game consists of two directories:
- `game_data/` - `.gdata` files organized in subdirectories: `game_config/`, `btiles/`, `sprites/`, `heroes/`, `map/`, `flow/`, `patches/`
- `game_src/` - Custom C/ASM code (game functions, codeset code)

### Build Pipeline

1. `make clean` - Remove previous build artifacts
2. `make config` - Copy game_data and game_src into `build/`
3. `make data` - Run `datagen.pl` to parse `.gdata` files and generate C source, headers, and `features.h`
4. Compile engine + generated + custom source into the main binary
5. For 128K: compile datasets, codesets, banked code, and bank binaries separately
6. Generate ASM loader and BASIC loader
7. Package everything into `.tap` files, concatenate into final `game.tap`

### Key Engine Concepts

- **BTiles** (Big Tiles): Multi-cell static graphics composed of 8x8 SP1 tiles
- **Sprites**: Moving graphic entities (hero, enemies, bullets) with animation frames
- **Screens**: Game map units composed of BTiles, enemies, hotzones, and items
- **Hotzones**: Screen zones that trigger actions (screen transitions, game events)
- **Flow Rules**: Scripted game logic (checks + actions) defined in `.gdata` files, processed per-screen or globally
- **Datasets**: Groups of screen data that get swapped in/out of low memory (128K mode)
- **Codesets**: Groups of code that get bank-switched at 0xC000 (128K mode)
- **SUBs** (Single Use Binaries): One-shot loadable code blocks

### Conditional Compilation

Features are auto-detected by `datagen.pl` from game data and emitted as `BUILD_FEATURE_*` macros in `build/generated/features.h`. All engine code uses `#ifdef BUILD_FEATURE_*` guards. Custom code should include `features.h` as the first non-system include.

### Memory Layout (128K mode)

Configured in `etc/rage1-config.yml`. Key regions:
- `0x0000-0x3FFF`: ROM
- `0x4000-0x5AFF`: SCREEN$
- `0x5B00-0x7FFF`: Low memory buffer + heap (dataset swap area)
- `0x8000+`: Interrupt vector table, stack, ISR, then C program code
- `0xD1ED-0xFFFF`: SP1 library data
- Upper 16K page (`0xC000`): Bank-switched for datasets/codesets

### Makefile Structure

- `Makefile` - Top-level: clean, config, build orchestration, test game targets
- `Makefile.common` - Shared variables, compiler flags, generic rules, data generation
- `Makefile-48` - 48K-specific build (org at 0x5F00)
- `Makefile-128` - 128K-specific build (datasets, codesets, banked code, banks)
- `Makefile.game` - For external games using RAGE1 as a library

### Entry Point

`engine/src/main.c`: initializes memory, SP1, interrupts, datasets, controllers, hero; then runs the main loop: `menu -> intro -> game_loop -> game_over/game_end` (repeating).

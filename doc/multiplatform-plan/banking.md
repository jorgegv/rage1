# Banking & memory map: ZX paging vs CPC RAM expansion

This document is the Banking chapter of the RAGE1 cross-platform plan
(see `doc/multiplatform-plan/README.md` once it lands; siblings
already in place: `gfx.md`, `assets.md`, `toolchain.md`,
`cpc-renderer.md`). It covers the **>64K memory** axis: how RAGE1's
existing ZX-128 paging model (datasets / codesets / banked code /
SUBs / low memory) must be generalised so the same engine can target
ZX 48K, ZX 128K, CPC 464/664 (flat 64K) and CPC 6128 (banked 128K)
in Phase 1.

Architectural anchors that are *not* re-litigated here:

- The asset model (shared `.gdata` + per-platform overlays) is owned
  by `assets.md`.
- The graphics HAL (`gfx_*`) and CPC renderer (cpctelera vendored) are
  owned by `gfx.md` and `cpc-renderer.md`.
- The build matrix (`PLATFORM=zx48|zx128|cpc-flat|cpc-banked`,
  `Makefile-cpc-flat`, `Makefile-cpc-banked`) is owned by
  `toolchain.md`.
- This doc owns *only* the memory-model, paging, dataset/codeset/SUB
  redesign. Where there is overlap with sibling docs, it is flagged
  in-line.

Conventions used in this file:

- Code references are `file_path:line` (clickable in most editors).
- Phases are tagged `B1, B2, …`; tasks within them `B1-1, B1-2, …`.
- "ZX game" = any `games/*` test game; back-compat is best-effort,
  green at phase boundaries (parent plan's anchor).
- "CPC" without qualifier = both CPC 464/664 (flat) and CPC 6128
  (banked); "CPC 6128" or "cpc-banked" is the banked variant; "CPC
  464/664" or "cpc-flat" is the flat variant.

---

## 1. Current state audit

### 1.1 ZX 128K paging model (port 0x7FFD)

The ZX 128 paging model is documented in `doc/BANKING-DESIGN.md` and
implemented in `engine/src/00bswitch.c`. The salient mechanics:

- The upper 16 KB page (`0xC000–0xFFFF`) is the **only** memory
  window into which arbitrary RAM banks can be paged. The window is
  selected by writing to **I/O port `0x7FFD`**
  (`engine/src/00bswitch.c:18-44, 70-95`).
- The bit layout of the byte written to `0x7FFD`:
  - bits 0–2: RAM page (0–7) to map at `0xC000`
  - bit 3: 0 = normal screen, 1 = shadow screen (bank 7)
  - bit 4: 0 = 128K ROM, 1 = 48K ROM (RAGE1 sets this to 1 because
    SP1 reads UDG/charset data from the 48K ROM —
    `engine/src/00bswitch.c:38-43`)
  - bit 5: 0 = paging enabled, 1 = paging permanently locked (until
    reset)
  - bits 6–7: unused
- Default value RAGE1 ORs the bank into: `0x10` (48K ROM, normal
  screen, paging enabled — `engine/src/00bswitch.c:45`).
- Banks 5 and 2 are **always mapped** at `0x4000–0x7FFF` and
  `0x8000–0xBFFF` respectively in standard 128 mode; they cannot be
  swapped out. Bank 5 = `0x4000` = SCREEN$. **Only bank 0 lives at
  `0xC000` after reset** (`0x10 | 0 = 0x10`).
- The bank switch function is **`memory_switch_bank()`** at
  `engine/src/00bswitch.c:82-105`. It is hand-assembler, atomic
  (DI / OUT / EI), and tracks the current bank in a global
  `memory_current_memory_bank` because the port is write-only.
  Bank tracking is interrupt-safe via `interrupt_nesting_level`
  bookkeeping
  (`engine/src/00bswitch.c:86-104`,
  `doc/BANKED-FUNCTIONS.md:160-198`).

Memory map at runtime (default SP1 / 128K profile from
`doc/BANKING-DESIGN.md:30-39`):

```
0x0000–0x3FFF  ROM (48K)                       16384 B
0x4000–0x5AFF  SCREEN$ (bank 5)                 6912 B
0x5B00–0x7FFF  LOWMEM buffer + heap (bank 5)    9472 B
0x8000–0x8100  IM2 IV table (257 bytes)          257 B
0x8101–0x8180  Stack                             128 B
0x8181–0x8183  "jp <isr>"                          3 B
0x8184–0xD1EC  C program code (bank 5+2)       20585 B
0xD1ED–0xFFFF  SP1 library data (bank 2)       11795 B
0xC000–0xFFFF  Bank-switched window (one of
               banks 0/1/3/4/6/7 at a time)    16384 B  (overlaps above)
```

The interrupt vector base (`iv_table_addr`), ISR pointer
(`isr_vector_byte`/`isr_vector_address`), and code base
(`base_code_address`) are configured in `etc/rage1-config.yml:30-34`
and consumed by `Makefile.common:96-100` and
`engine/src/interrupts.c:78-85`. RAGE1 uses one alternative profile
(IV at `0x8400` etc.) commented at `etc/rage1-config.yml:36-43`.

### 1.2 Datasets — what they are, how they're emitted, how they're loaded

**Concept** (`doc/BANKING-DESIGN.md:256-301`). A *dataset* is a
self-contained blob of game data (screens, BTiles, sprites, flow
rules, enemy graphics) whose pointers reference only its own
contents or fixed home-bank symbols. Each screen belongs to exactly
one dataset; entering a screen activates that dataset (cheap if it's
already current).

**Emission** (`Makefile-128:67-86`):

1. `datagen.pl` writes per-dataset C/ASM source into
   `build/generated/datasets/dataset_N.src/` (one directory per
   dataset).
2. Each `dataset_N.bin` is compiled by `zcc +zx --no-crt` (no CRT,
   standalone) with `ORG 0x5B00` enforced via the **"__orgit" trick**
   (`doc/BANKING-DESIGN.md:312-321`) so every internal pointer is
   already resolved for the runtime load address.
3. `dataset_N.bin` is checked against `DATASET_MAXSIZE` (computed by
   `datagen.pl` and exposed in `build/generated/game_data.h`,
   referenced from `Makefile.common:50`).
4. **ZX0-compressed** to `dataset_N.zx0` via `z88dk-zx0`
   (`Makefile-128:83-86`).
5. `tools/banktool.pl` (`tools/banktool.pl:60-72`) bin-packs the
   compressed datasets into 16 KB bank binaries by exploring
   permutations (`tools/banktool.pl:166-211`). The valid bank list
   is **hard-coded at `tools/banktool.pl:28`**:
   ```perl
   my @dataset_valid_banks = ( 1, 3, 7, 6, 4 );
   ```
   Note bank 4 here — datasets *can* share bank 4 with banked code
   if the packer needs it; in practice bank 4 is pre-occupied by
   `banked_code.bin` (`tools/banktool.pl:91-121`) and only spills
   over when nothing else fits.
6. `banktool.pl` emits **`dataset_info.asm`**
   (`tools/banktool.pl:331-363`), a fixed-layout table
   `(bank_num, size, offset_into_bank)` per dataset, linked into the
   main binary (`section code_crt_common`).

**Loading** (`engine/src/dataset.c:28-58`):

1. `dataset_activate(d)` reads `dataset_info[d]` to learn (bank,
   offset, size).
2. `memory_switch_bank(bank)` pages the right bank at `0xC000`.
3. `dzx0_standard()` decompresses from `0xC000 + offset` into
   `BANKED_DATASET_BASE_ADDRESS = 0x5B00`
   (`engine/include/rage1/dataset.h:24`).
4. Bank 0 is restored; the global `game_state.active_dataset` is
   updated.
5. The decompressed dataset's `struct dataset_assets_s` is at the
   well-known address `0x5B00`; `banked_assets` is a global pointer
   permanently set to that address
   (`engine/src/dataset.c:67`).

**At load (cold boot)** the BASIC loader cooperates with
`tools/loadertool.pl`-generated `asmloader.asm`
(`tools/loadertool.pl:225-249, 359-378`) to:

1. For each bank in the bank-map: write bank number to `0x7FFD`,
   then `LD_BYTES` (ROM tape-load routine at `0x0556`) into
   `0xC000`.
2. Restore bank 0.
3. Load main binary at `base_code_address` (default `0x8184`).
4. Load SUBs (see §1.4).
5. `jp` into main code.

The dataset model carries **two ZX-specific assumptions** that are
not portable as written:

- The bank IDs (1, 3, 4, 6, 7) are physical RAM page numbers
  consumed by port `0x7FFD`. They are not abstract slot numbers.
- The swap window is `0xC000`. The destination buffer is `0x5B00`.
  Both are chosen because they fall outside both SCREEN$ (`0x4000`)
  and the always-mapped banks 5 + 2 (`0x4000–0xBFFF`).

### 1.3 Codesets — same

**Concept** (`doc/CODESET-DESIGN.md`). A *codeset* is a 16 KB block
of **executable** code that lives at `0xC000` while its bank is
paged. Unlike datasets, codesets are **not** decompressed into low
memory; the code is run directly from the swap window. Used for
optional game functions and (for codeset 0) engine code that the
team has chosen to migrate out of low memory.

**Constraints** (`doc/CODESET-DESIGN.md:31-48`, also
`engine/src/codeset.c`):

- A codeset can mutate **only** global home-bank state and its own
  data; it cannot reach into other banks.
- Codeset functions have a fixed prototype: `void f(void)`.
- Cross-codeset and home → codeset calls go through
  **`codeset_call_function( global_function_id )`**
  (`engine/src/codeset.c:54-70`) which (a) looks up
  `all_codeset_functions[id]` for `(bank, local_index)`,
  (b) switches bank, (c) calls
  `codeset_assets->functions[local_index]()`, (d) restores bank.
- The first data structure in every codeset bank is
  `struct codeset_assets_s` at `0xC000`
  (`engine/src/codeset.c:38`). It is populated at init time
  (`init_codesets()`, `engine/src/codeset.c:32-51`) with low-memory
  pointers (`game_state`, `home_assets`, `banked_assets`) so the
  codeset can reach back into the home bank.

**Emission** (`Makefile-128:88-99`):

- One directory per codeset under
  `build/generated/codesets/codeset_N.src/`, fed by `datagen.pl`.
- Compiled `--no-crt`, **org `0xC000`**, single binary per codeset.
- Size cap `CODESET_MAXSIZE = 16384` (`Makefile.common:55`).
- **Not** ZX0-compressed (must be executable directly).
- `banktool.pl` places each codeset at the *start* of its bank
  (`tools/banktool.pl:122-147`); the per-codeset bank list is
  hard-coded at `tools/banktool.pl:25`:
  ```perl
  my @codeset_valid_banks = ( 6, 1, 3, 7 );
  ```
  Bank 6 is preferred because uncontended (faster).
- `banktool.pl` emits `codeset_info.asm` (analogous to
  `dataset_info.asm`).
- Engine code that *is* migrated to codeset 0 lives under
  `engine/codeset/N/` (per `doc/CODESET-DESIGN.md:218-237`) and is
  copied to the appropriate build directory by the build glue.
- A **48K fallback path**: in 48K builds, `codeset_call_function()`
  is `#define`d away to a direct call
  (`doc/CODESET-DESIGN.md:218-263`); no infrastructure cost.

### 1.4 SUBs — same

**Concept** (`doc/SINGLE-USE-BLOBS.md`). A *Single Use Blob* is a
self-contained binary (typically intro / credits / preboot demo)
that runs once after load, **before** RAGE1's main() takes control.
It uses buffers (the dataset decompression buffer at `0x5B00`, the
SP1 buffer at `0xD1ED`) that are not yet populated, then discards
itself when RAGE1 boots.

**`.gdata` declaration**
(`doc/SINGLE-USE-BLOBS.md:36-69`,
`tools/loadertool.pl:102-117`,
`games/sub_bufs_128/game_data/game_config/Game.gdata`):

```
SINGLE_USE_BLOB NAME=foo LOAD_ADDRESS=0x6500 ORG_ADDRESS=0xD200 \
                RUN_ADDRESS=0xD200 COMPRESS=1
```

- `LOAD_ADDRESS`: where the tape-loader puts it.
- `ORG_ADDRESS`: where it must be relocated to before running.
- `RUN_ADDRESS`: the entry-point address.
- `COMPRESS=1`: store ZX0-compressed and decompress at SUB-start.
- If `LOAD_ADDRESS != ORG_ADDRESS`, the loader swaps the original
  contents of `ORG_ADDRESS..(ORG_ADDRESS+size)` into
  `LOAD_ADDRESS..` before running the SUB, and swaps them back
  afterwards (`tools/loadertool.pl:323-348`,
  `doc/SINGLE-USE-BLOBS.md:55-66`).

**Build** (`Makefile-128:104-124`,
`games/sub_bufs_128/game_src/sub_dsbuf*/Makefile`):

- Each SUB lives at `game_src/sub_<name>/` with its own Makefile
  that compiles a standalone `sub.bin` via
  `zcc +zx ... --no-crt` and emits a headerless TAP with
  `z88dk-appmake +zx -b sub.bin --org $ORG`. The per-SUB
  `Makefile` skeleton is provided as a starting point.
- Optional `z88dk-zx0` compression.

**Load + run** (`tools/loadertool.pl:274-348`):

1. `asmloader` loads all banks, then main, then each SUB at its
   `LOAD_ADDRESS`.
2. For each SUB in declaration order: optional decompress; optional
   swap; `di`; `call RUN_ADDRESS`; optional unswap.
3. Finally `jp` into main.
4. SUBs must run with interrupts disabled
   (`doc/SINGLE-USE-BLOBS.md:88-94`) because the bank 7 / SYSVARS
   area is repurposed.

The SUB infrastructure is **almost** ZX-agnostic. The only
ZX-specific bits are:

- `LOAD_ADDRESS` / `ORG_ADDRESS` defaults relate to the ZX memory
  map (the documented 2 SUBs target `0x5B00–0x7FFF` and
  `0xD1ED–0xFFFF`).
- The compression is ZX0 (also fine on CPC — `z88dk-zx0` works
  regardless of target).
- The loader uses `LD_BYTES` (ROM at `0x0556`) — Sinclair-specific.
- Bank 7 / SYSVARS warning is Sinclair-specific.

### 1.5 Low memory: `engine/lowmem/` and the locked-down code

The task spec mentions `engine/lowmem/`. Today
(`ls engine/lowmem`) the directory is **empty**. The actual
low-memory code was relocated into `engine/src/` with `00*` filename
prefixes so the linker picks them up first; the relocations were
recorded in commits
`1b3e440` ("moved lowmem code to general engine/src dir but with
filename hacks so that they are linked first"),
`b352758`, `ebf6406`. See `git log -- engine/lowmem`.

The current low-memory contract is enforced by:

1. **`mmap.inc`** (248 lines, all `section …` directives). It
   reorders the linker section sequence so that `data_*`, `bss_*`
   and `rodata_*` are placed *before* code, preventing data drift
   above `0xC000` (`doc/BANKING-DESIGN.md:485-513`).
2. **`tools/lowmemsym.pl`** (called from `Makefile-128:64`,
   target `lowmemcheck`). Reads `main.map`, asserts that every
   symbol listed in `ALL_LOWMEM_SYMBOLS` is linked below `0xC000`.
   The symbol list is computed at `Makefile-128:48-57`:
   - every `extern` declared in `engine/include/rage1/**.h`
   - a hard-coded critical-functions list: `init_datasets`,
     `init_codesets`, `memory_switch_bank`, `dataset_activate`,
     `codeset_call_function`, `memory_call_banked_function`
     (`Makefile-128:51`)
   - every symbol in generated `game_data.o`
   - every symbol in `engine/src/*.o`.
3. **`tools/check_mmap_sections.sh`** (`make section-check`):
   verifies `main.map` only contains sections that
   `mmap.inc` knows about — catches accidental drift if the engine
   adds a new section.
4. **`engine/banked_code/`** is the explicit opposite seam: code
   here is **not** loaded into low memory; it is emitted into
   `banked_code.bin` and lives in bank 4 at runtime
   (`engine/include/rage1/memory.h:30`,
   `tools/banktool.pl:101-112`). 48K builds compile the same files
   as if they were in low memory (the `common/` subset goes into
   the 48K binary — `Makefile-48:28-30`).

So when this document says "low memory code" it means: code that
must be linked below `0xC000` because it runs while a non-home bank
is paged. The locked-down set is small and well-identified:

- `00bswitch.c`: the bank-switch primitive itself.
- `00lowmem.c`: the banked-function call trampolines.
- `dataset.c`, `codeset.c`: the dataset/codeset activators.
- All interrupt-time code (`interrupts.c`, ISR body): the ISR runs
  on whatever bank was paged when the interrupt fired.
- All `extern`-visible engine symbols accessed across the
  bank-switch boundary (via the `Makefile-128:48` rule).

### 1.6 ZX 48K (no banking)

The 48K build sidesteps banking entirely
(`doc/BANKING-DESIGN.md:452-468`,
`zpragma-48.inc`,
`Makefile-48`):

- Single flat 48K RAM. Code org at `0x5F00`
  (`zpragma-48.inc:14`); stack at `0xD1D1`
  (`zpragma-48.inc:15`); IV table at `0xD000` (SP1) or `0xE000`
  (JSP); ISR at `0xD1D1` or `0xE1E1` (`engine/src/interrupts.c:88-98`).
- No `0x7FFD` port writes; no `memory_switch_bank()` compiled in
  (`engine/src/00bswitch.c:48` gates the whole compilation unit on
  `BUILD_FEATURE_ZX_TARGET_128`).
- `banked_assets` aliases to `home_assets`
  (`engine/src/dataset.c:72-74`) — the entire game data must fit in
  low memory.
- Banked code: only `engine/banked_code/common/*` files are
  compiled, and they are compiled *as if* they were normal engine
  source — i.e. they end up in low memory like everything else
  (`Makefile-48:28-30`). The `banked_code/128/` files are simply
  not compiled.
- No codesets at runtime (codeset macros expand to direct calls
  per `doc/CODESET-DESIGN.md:173-198`).
- SUBs **still work** in 48K (`doc/SINGLE-USE-BLOBS.md:6-9, 70-72`,
  `games/sub_bufs_48`). Only the DSBUF-target SUB is gated to 128K
  by the documented check
  (`doc/SINGLE-USE-BLOBS.md:70-72`). SP1-buffer SUBs work on both.

So ZX 48K is a *degenerate case* of the banking model: same
`.gdata` syntax, same engine source compiled with
`BUILD_FEATURE_ZX_TARGET_48`, banking infrastructure compiles out.

### 1.7 Tooling: banktool.pl, loadertool.pl, check_banked_code_definitions.pl

| Tool | Lines | Inputs | Outputs | ZX-coupling |
|---|---|---|---|---|
| `tools/banktool.pl` | 363 | `build/generated/datasets/dataset_*.zx0`, `build/generated/codesets/codeset_*.bin`, `engine/banked_code/banked_code.bin` | `bank_N.bin` (concatenated bank images), `bank_bins.cfg`, `dataset_info.asm`, `codeset_info.asm` | Hard-coded `@dataset_valid_banks = (1,3,7,6,4)` and `@codeset_valid_banks = (6,1,3,7)` at `tools/banktool.pl:25, 28`. Hard-coded `$max_bank_size = 16384` (`:32`). Implicitly assumes one-bank-at-a-time swap-window paging. |
| `tools/loadertool.pl` | 510 | `build/generated/bank_*.bin`, `build/generated/sub_*.bin*`, `build/game_data/game_config/Game.gdata`, `etc/rage1-config.yml` | `asmloader.asm` | Hard-coded loader orgs (`$loader_org_48 = 0x5E00`, `$loader_org_128 = 0x8000` — `tools/loadertool.pl:33-34`). Emits Sinclair `LD_BYTES` calls (`:217`), `0x7FFD` port writes via the `bswitch` stub (`:369-376`), `RANDOMIZE USR` semantics implicit in `asmloader` callability. Reads `ZX_TARGET` and `SPRITE_ENGINE` from game config (`:164-195`). |
| `tools/check_banked_code_definitions.pl` | 176 | `build/generated/banked_function_defs.h`, `build/generated/banked/128/00banked_function_table.asm` | exit 0 / 1 + error report | Toolchain-neutral: validates symbol consistency between the function-ID `#define`s and the ASM dispatch table. No port / bank-number knowledge. |
| `tools/generate_banked_function_defs.pl` | 118 | `etc/rage1-config.yml` (the `banked_functions:` list) | `00banked_function_table.asm`, `banked_function_defs.h` | Toolchain-neutral. Emits an ORG `0xC000` directive (`tools/generate_banked_function_defs.pl:57`) but that's a generalisable detail (see §3). |
| `tools/lowmemsym.pl` | 50 | `main.map`, `ALL_LOWMEM_SYMBOLS` list | exit 0 / 1 | Called from `Makefile-128:64` (target `lowmemcheck`). Treats the `0xC000` threshold as the lowmem boundary — this is a hard-coded ZX-paging assumption that must become a CLI threshold argument (see Phase B3-1). |
| `tools/check_mmap_sections.sh` | — | `main.map`, `mmap.inc` | exit 0 / 1 | Toolchain-neutral. |

Summary classification of the audit:

| Concept | Class |
|---|---|
| 16K paging-window concept | **(b) ZX-paging-shaped but generalisable** — CPC 6128 also has a per-16K-page swap concept, just with 4 windows and a different mapping space. |
| Datasets-as-a-mechanism (self-contained, ORG-locked, decompressed into a fixed buffer) | **(a) already platform-agnostic in spirit** — the *concept* travels intact; only the swap window and destination address are platform-specific. |
| Dataset valid-banks list `(1,3,7,6,4)` | **(c) ZX-specific** — physical RAM page numbers. |
| Codeset valid-banks list `(6,1,3,7)` | **(c) ZX-specific** — physical RAM page numbers; also "bank 6 is uncontended" is ZX-128-specific lore (CPC's RAM is uniformly accessed). |
| Codesets-as-a-mechanism (org'ed `0xC000`, exec from window) | **(b) generalisable** — the abstract concept "executable bank at the swap window" exists on CPC 6128 too, but the choice of *which* window changes. |
| Banked code (reserved bank, dispatch table at `0xC000`) | **(b) generalisable** — same as codesets. |
| SUB load/swap/run dance | **(a) already platform-agnostic** — the model only cares about addresses, sizes, and `LD_BYTES`-equivalent. |
| `LD_BYTES` ROM call in the asmloader | **(c) ZX-specific** — needs a CPC firmware-call analog. |
| Port `0x7FFD` writes | **(c) ZX-specific** — CPC uses port `0x7Fxx` and a different bit layout (§2.2). |
| Bank-tracking variable + DI/EI critical section | **(a) already platform-agnostic** — every paged system needs the same. |
| IM2 interrupt mode + IV table layout | **(c) ZX-specific** — CPC uses IM1 from the firmware. Generalisable in shape (per-platform ISR seam). |
| `engine/banked_code/{common,128}/` directory split | **(b) generalisable** — fork to `{common, zx128, cpc-banked}/` is a natural extension. |
| `etc/rage1-config.yml` interrupt config | **(b) generalisable** — add per-platform sections. |

Everything that needs to change is in scope of the work plan in §6.

---

## 2. CPC memory model

### 2.1 CPC 464/664 — 64K flat

CPC 464 and CPC 664 have **64 KB of RAM** and no bank-switching
hardware on board. The address space is approximately:

```
0x0000–0x3FFF  RAM (lower ROM overlay when enabled)
0x4000–0xBFFF  RAM
0xC000–0xFFFF  RAM, used as screen RAM by default
               (upper ROM overlay when enabled)
```

The CPC firmware (ROM) is **paged in** by default at `0x0000–0x3FFF`
(lower ROM, OS) and `0xC000–0xFFFF` (upper ROM, BASIC). Both can
be paged out, exposing the underlying RAM. This is controlled by
Gate Array writes (port `0x7Fxx`, bits 2 (upper ROM enable) and 3
(lower ROM enable), `&xx` style). cpctelera's
`cpct_disableFirmware()` paged these out.

Default screen RAM is at `0xC000–0xFFFF` (16 KB). The screen base
can be moved to `0x4000–0x7FFF` via CRTC register R12/R13, but
`0xC000` is canonical and what cpctelera assumes by default.

The 464/664 stack is set up by AMSDOS/firmware near `0xC000` going
down; once we take over (lower-ROM out, upper-ROM out), we control
the stack and can put it where we like.

**For RAGE1**, the cpc-flat memory profile is effectively a
"degenerate banking case" — same as ZX 48K is a degenerate case of
the ZX 128 model. No datasets-as-paged, no codesets, no banked code.
All assets must fit alongside engine + screen + stack in the 64 KB.

### 2.2 CPC 6128 — 128K Gate Array banking

The CPC 6128 has the same 64 KB CPU address space but **128 KB of
RAM** (some 6128+s and 464+ "Plus" machines and aftermarket
expansions go to 512 KB; out of scope here). The extra 64 KB is
accessed via the **Memory Mapping Register (MMR)** in the PAL chip,
addressed at I/O port `0x7Fxx` with the data-byte command pattern
`110xxxxx` (i.e. `0xC0 | (config & 0x07) | ((page & 0x03) << 3)`).

Authoritative references: CPCWiki "Gate Array", Grimware
"documentations/devices/gatearray", and cpctelera's
`cpct_pageMemory` documentation
(`lronaldo.github.io/cpctelera/files/memutils/cpct_pageMemory-asm.html`).

Key facts:

- **Same I/O port window (`0x7Fxx`) as the Gate Array** (which
  handles palette / mode / ROM enables). The PAL/MMU and the Gate
  Array discriminate on bits 15:14 of the address bus and on the
  high bits of the data byte (`0b11xxxxxx` writes to the PAL/MMU
  RAM mapper; `0b10xxxxxx` to Gate Array ROM enable; `0b00xxxxxx`
  to palette index; `0b01xxxxxx` to palette colour). RAGE1 only
  cares about the `0b110xxxxx` (RAM mapping) form for banking.
- **The address space is divided into 4 fixed 16 KB pages** (unlike
  ZX 128's single bank-window at `0xC000`):
  - page A: `0x0000–0x3FFF`
  - page B: `0x4000–0x7FFF`
  - page C: `0x8000–0xBFFF`
  - page D: `0xC000–0xFFFF`
- **8 standard mapping configurations** (`C0..C7` in MMR speak,
  matching cpctelera's `cpct_pageMemory` argument 0..7):

| Config            | 0x0000 (A) | 0x4000 (B) | 0x8000 (C) | 0xC000 (D) |
|-------------------|------------|------------|------------|------------|
| 0 (reset default) | RAM 0      | RAM 1      | RAM 2      | RAM 3      |
| 1                 | RAM 0      | RAM 1      | RAM 2      | RAM 7      |
| 2                 | RAM 4      | RAM 5      | RAM 6      | RAM 7      |
| 3                 | RAM 0      | RAM 3      | RAM 2      | RAM 7      |
| 4                 | RAM 0      | RAM 4      | RAM 2      | RAM 3      |
| 5                 | RAM 0      | RAM 5      | RAM 2      | RAM 3      |
| 6                 | RAM 0      | RAM 6      | RAM 2      | RAM 3      |
| 7                 | RAM 0      | RAM 7      | RAM 2      | RAM 3      |

  Source: cpctelera reference table cross-checked against Grimware
  Gate Array documentation. The "base 64K" is RAM 0/1/2/3; the
  "extended 64K" is RAM 4/5/6/7.

- **Critical limitation** (per Grimware): the Gate Array always
  reads video data from RAM 0 (or the page selected by CRTC), **not
  from the currently-mapped page at `0xC000`**. So mapping RAM 7
  at `0xC000` does *not* change what the screen displays — only
  CRTC's page-select does. This means the swap window for a
  RAGE1-style dataset can land on RAM 7 / `0xC000` without
  disturbing the screen, **provided we leave the screen reading from
  RAM 0**. (For the same reason, `RAM 4` at `0x4000`
  via Config 4 is a *true second copy* of low memory — useful for
  double-buffering scenarios; not relevant to RAGE1's design yet.)

- The 8-configuration table is **not** an arbitrary
  bank-at-arbitrary-window matrix: most slots in most configs are
  RAM 0/1/2/3 (base). Effectively only two extended-RAM access
  shapes matter to RAGE1:
  - **Config 1**: RAM 7 at `0xC000` — extended bank at the upper
    window, base intact. *This is the natural ZX-128 analog.*
  - **Configs 3..7**: an extended bank (3, 4, 5, 6, 7 respectively)
    at `0x4000` — extended bank at the middle window, base
    elsewhere.
  - Config 2 swaps *all four* pages to extended-RAM siblings of
    them — used for whole-second-64K access patterns; awkward for
    RAGE1's "small swap window" model.

- The MMR is **write-only** (like ZX's `0x7FFD`), so the current
  configuration must be tracked in a software variable. Same
  pattern as `memory_current_memory_bank`
  (`engine/src/00bswitch.c:49`).

### 2.3 cpctelera's banking primitives (`cpct_pageMemory`, RAM bank macros)

cpctelera exposes the MMR via two surfaces
(`external/cpctelera/cpctelera/src/memutils/`):

- **`cpct_pageMemory(config)`** — takes one of 8 numeric configs
  (the table in §2.2), writes the corresponding MMR command to
  port `0x7Fxx`, returns. Implementation is a short asm routine
  (`cpct_pageMemory.s`). Does **not** track previous state —
  caller must do so.
- **Bank macros** (`memutils/cpct_setVideoMemoryPage.h.s` family,
  plus `cpct_pageMemory.h.s`): named constants for the 8 configs
  (`CPCT_RAM_BANK_PAGE_0..7` style, exact names per cpctelera
  version) and convenience macros for the common case of mapping
  RAM 7 at `0xC000`.
- **`cpct_setVideoMemoryPage()`** is the *CRTC* page selector
  (where the Gate Array fetches video data from), distinct from
  the CPU memory map. Mentioned here only to flag that RAGE1's
  banking strategy must not confuse the two: switching the swap
  window with `cpct_pageMemory` does not change what shows on
  screen.

**Use cpctelera's primitives, do not roll our own.** Rationale:

1. cpctelera's asm is small and the calling convention is SDCC-
   compatible (`__z88dk_callee` annotated). Wrapping with a
   `cpc_memory_switch_bank()` is a few lines.
2. The MMR command-byte construction is one place we definitely
   don't want to bug-for-bug reimplement.
3. cpctelera already has the bank-name constants we'd otherwise
   invent ourselves.

What RAGE1 *will* roll on top of cpctelera:
- The atomic "DI / set new bank / track in software variable / EI"
  wrapper (see §1.1; interrupt-safety is RAGE1's contract, not
  cpctelera's).
- The "save previous, switch, restore" idiom (cpctelera
  `cpct_pageMemory` doesn't return previous state).

Coordinate with `cpc-renderer.md` §4.2: the cpctelera memutils
sources need to be in the source glob for `Makefile-cpc-banked`.

### 2.4 Comparison: ZX 128 paging vs CPC 6128 banking

| Aspect                                       | ZX 128K                                          | CPC 6128                                                                  |
|----------------------------------------------|--------------------------------------------------|---------------------------------------------------------------------------|
| Paging port                                  | `0x7FFD` (write-only)                            | `0x7Fxx` MMR command `0b110xxxxx` (write-only)                            |
| Banks of RAM total                           | 8 banks of 16 KB                                 | 8 banks of 16 KB (4 base + 4 extended)                                    |
| Always-mapped banks                          | 5 (`0x4000`), 2 (`0x8000`)                       | RAM 0/1/2 in default config (configs 0, 3..7)                             |
| Swap window                                  | One: `0xC000`                                    | Effectively one preferred: `0xC000` (config 1) or `0x4000` (configs 3..7) |
| Number of "free" banks visible at the window | 1 at a time, drawn from {0,1,3,4,6,7}            | 1 at a time, drawn from {3,4,5,6,7} (configs 1, 3..7)                     |
| Where the screen sits                        | bank 5 at `0x4000`                               | RAM 0 (or CRTC-selected), independent of MMR                              |
| ROM enable in the swap byte                  | yes (bit 4)                                      | no (separate Gate Array `0b100xxxxx` command)                             |
| Bank tracking                                | software variable (`memory_current_memory_bank`) | same — both ports are write-only                                          |
| Interrupt mode                               | IM 2 with user IV table                          | IM 1 from firmware (default), can take over                               |
| Stack location for banked builds             | `0x8101–0x8180` (configurable)                   | flexible; cpctelera typically uses `0xC000`-adjacent                      |
| Compression-on-load convention               | ZX0 (z88dk-zx0)                                  | ZX0 also works (same z88dk tool family)                                   |
| ROM loader for cold-boot                     | Sinclair `LD_BYTES` at `0x0556`                  | AMSDOS file loader (firmware call) or raw block read from tape            |

The structural parallels are strong. The main differences:

- CPC has **multiple swap windows** (B at `0x4000`, D at `0xC000`).
  Different configs use different windows.
- CPC's "uncontended bank" notion does **not exist** — CPC RAM is
  uniformly contended by the Gate Array on every cycle of every
  scanline. So "prefer bank 6 because uncontended" (ZX-128 lore at
  `tools/banktool.pl:25, 28`) does not transfer.
- Screen RAM placement on CPC is **independent** of the MMR (it's
  CRTC-driven). The (1.1) ZX rule "bank 5 / bank 7 selectable by
  bit 3 of `0x7FFD`" has no CPC equivalent.

---

## 3. Cross-platform banking model design

### 3.1 Per-platform memory maps

Concrete maps for each of the four Phase-1 targets. Addresses are
the RAGE1-side commitment, not the hardware-baseline (which is the
same on both ZX and CPC: 64 KB CPU address space, ROMs/RAMs as
above).

#### 3.1.1 zx48

Status quo (`doc/BANKING-DESIGN.md:452-468`, `zpragma-48.inc`):

```
0x0000–0x3FFF  ROM
0x4000–0x5AFF  SCREEN$
0x5B00–0x5EFF  unused (system vars, free)
0x5F00–0xCFFF  C code + data + bss
                  (CRT_ORG_CODE = 0x5F00, ~28 KB)
0xD000–0xD100  IM2 IV table (SP1)  | 0xE000–0xE100 (JSP)
0xD101–0xD1D0  Stack               | 0xE101–0xE1D0
0xD1D1         jp <isr>             | 0xE1E1
0xD1ED–0xFFFF  SP1 buffers          | (JSP shifted accordingly)
```

No paging. `BUILD_FEATURE_PLATFORM_ZX48` selected at config time.
`memory_switch_bank` not compiled in. `dataset_activate` becomes a
no-op (assets live in `home_assets`).

#### 3.1.2 zx128

Status quo (`doc/BANKING-DESIGN.md:30-39`):

```
0x0000–0x3FFF  ROM
0x4000–0x5AFF  SCREEN$
0x5B00–0x7FFF  Dataset decompress buffer + heap (9472 B)
0x8000–0x8100  IM2 IV table
0x8101–0x8180  Stack
0x8181–0x8183  jp <isr>
0x8184–0xD1EC  C code + data + bss
0xD1ED–0xFFFF  SP1 buffers
0xC000–0xFFFF  Paged window (banks 0/1/3/4/6/7) — overlaps above
                  Bank 0 = default (= home bank, shares the C-code
                  area)
                  Bank 4 = banked engine code (`banked_code.bin`)
                  Banks 1/3/6/7 = datasets, codesets, spill
```

`BUILD_FEATURE_PLATFORM_ZX128` selected. Full banking compiled in.

#### 3.1.3 cpc-flat (CPC 464/664)

```
0x0000–0x3FFF  RAM (lower ROM paged out at startup);
               could host code + data + bss
0x4000–0x7FFF  RAM: code + data + bss + dataset buffer
0x8000–0xBFFF  RAM: code + data + bss
0xC000–0xFFFF  Screen RAM (CRTC reads from RAM 0, default base)
               16 KB locked
```

Concrete address-budget proposal:

```
0x0000–0x003F  Z80 jump table / firmware vectors (preserved
               by leaving lower ROM paged in *briefly* during
               boot, then disabling).
0x0040–0x00FF  RAGE1 entry vectors / reset stub
0x0100–0x03FF  IM 1 ISR + small ASM data
0x0400–0x3FFF  Free RAM (≈15 KB) — usable by code/data
0x4000–0xBEFF  C code + data + bss (≈32 KB)
0xBF00–0xBFFF  Stack (256 B, top-down — initial budget; exact size
               TBD against a hand-walk of worst-case ISR+library
               nesting in Phase B4-2, then frozen in
               `zpragma-cpc-flat.inc`)
0xC000–0xFFFF  Screen RAM (mode 1) — 16 KB
```

Notes:

- **Lower ROM is disabled** at boot so that `0x0000–0x3FFF` is RAM.
  cpctelera's `cpct_disableFirmware()` (under `firmware/`) does
  this and saves/restores firmware vectors.
- **Upper ROM is disabled** so `0xC000–0xFFFF` is RAM, but the Gate
  Array still drives that region as screen RAM. Nothing else can
  live there.
- The `0x0040–0x00FF` region matters because IM 1 jumps to `0x0038`
  (the RST 38 vector) — RAGE1's ISR entry will live there.
- No banking: `memory_switch_bank` is a stub on cpc-flat (same
  shape as ZX 48). Datasets/codesets/banked-code compile out.
- Asset budget: depends on the game's code/asset ratio. CPC mode-1
  sprite/tile bytes are ~**2×** the size of ZX 1-bpp bytes for the
  same pixel area; mode-0 is ~**4×**. This is partly offset by
  CPC464's ~5-7 KB extra usable RAM vs ZX48 (CPC464: 64 KB total
  minus 16 KB screen at `0xC000-0xFFFF` minus small firmware reserve
  ≈ 46-48 KB; ZX48: 48 KB total minus ~7 KB screen at
  `0x4000-0x5AFF` minus ~350 B system vars ≈ 41 KB). For asset-light
  games, cpc-flat is more comfortable than ZX48; for asset-heavy
  games approaching the ZX48 cap, the 2× multiplier outpaces the
  RAM bonus and cpc-flat becomes tighter. Mode 0's 4× multiplier
  pushes cpc-flat hard regardless. See §5.


#### 3.1.4 cpc-banked (CPC 6128)

The big design choice. There are two reasonable shapes; the
recommendation is shape **A**.

##### Shape A (recommended): swap window at 0x4000 via Configs 3..7

The **preferred swap window is `0x4000` (page B), using MMR
Configs 3..7** (which expose RAM 3..7 respectively at the `0x4000`
window while keeping the base RAM 0 at `0x0000`, RAM 2 at `0x8000`
and RAM 3 at `0xC000`). Page D (`0xC000`) is reserved for screen
RAM and is *not* used as a code/data swap window — see the "Why
not page D?" rationale below.

```
0x0000–0x3FFF  Code home page (RAM 0) — engine code lives here
0x4000–0x7FFF  Swap window (page B)
                  Default mapping: RAM 1 (base, used as home data)
                  Banked mode: one of RAM 4..7 (extended)
0x8000–0xBFFF  Home data page (RAM 2)
0xC000–0xFFFF  Screen RAM (RAM 0 backing, CRTC-fetched)
                  Code/data **must not** live here (would show on
                  screen)
```

##### Why not page D / `0xC000`?

The natural ZX-128 analog would be MMR Config 1 (RAM 7 at `0xC000`,
base RAM 0/1/2 at `0x0000/0x4000/0x8000`). It is **rejected**
because `0xC000` is screen RAM on CPC. In MMR Config 0 (reset
default) RAM 3 is mapped at `0xC000` — and `0xC000` is where the
Gate Array fetches video data from in the default CRTC setup. So
RAM 3 is *claimed by the screen*; the free extended banks for our
datasets/codesets are **RAM 4, 5, 6, 7** (not 3), and the swap
window has to live somewhere other than page D to avoid
interleaving paged data with displayed pixels. That leaves page B
(`0x4000`) as the only viable swap window, and Configs 3..7 as the
mechanism to drive it.

Concrete RAGE1 layout sketch:

```
=== Page A (RAM 0): 0x0000–0x3FFF ===
0x0000–0x003F  Z80 vectors + minimal CRT (entry from AMSDOS load)
0x0038         IM 1 ISR entry (3-byte jp)
0x003B–0x00FF  RAGE1 ISR body + critical low-memory primitives
0x0100–0x3FFF  Engine C code (lowmem code: bank-switch,
               dataset_activate, codeset_call_function, …) [*]

[*] The `0x0100–0x3FFF` page-A engine-code budget is **optimistic**.
z88dk's default `+cpc` `CRT_ORG_CODE` is `0x1200`, and the `+cpc`
clib may install library support routines below that. The real
page-A code budget after the `+cpc` clib's support-routine footprint
is **TBD**, blocked on the z88dk CRT walk in Phase B4-1. See also
R9 (CRT_ORG_CODE on cpc-banked is constrained).

=== Page B (RAM 1, default): 0x4000–0x7FFF ===
0x4000–0x7FFF  Secondary code/data area, **only addressable in
               MMR Config 0**. Paged OUT during dataset / codeset /
               banked-code swaps. Realistic contents: one-shot
               pre-game init code, SUB load slot when no
               extended-bank read is needed, or kept unused.
               **Cannot** host anything that must coexist with
               banking operations — in particular, the dataset
               decompression buffer cannot live here because the
               compressed source (paged into the same window via
               MMR Configs 3..7) and the destination buffer would
               collide.

=== Page B (RAM 3..7, banked mode): 0x4000–0x7FFF ===
Whatever extended bank is currently paged: datasets / codesets /
banked code. Same as ZX 128's 0xC000 window in role, just at a
different address.

=== Page C (RAM 2): 0x8000–0xBFFF ===
0x8000–0x9FFF  Dataset decompression buffer + heap (8 KB,
               = BANKED_DATASET_BASE_ADDRESS; matches §3.2
               invariant — buffer base == compile-time ORG of
               dataset_N.bin). Final size driven by largest
               decompressed dataset (computed by datagen.pl,
               per-platform BUILD_MAX_DATASET_SIZE).
0xA000–0xBEFF  Generated game data (home dataset) + bss
0xBF00–0xBFFF  Stack (256 B, top-down — initial budget; exact size
               TBD against a hand-walk of worst-case ISR + cpctelera
               + C-frame nesting in Phase B4-2)


=== Page D (screen RAM): 0xC000–0xFFFF ===
0xC000–0xFFFF  Screen RAM (mode 1) — 16 KB, untouchable as
               code/data
```

**Design note — buffer placement alternative considered.** Placing
the decompression buffer + heap at the top of Page A (e.g. 8 KB at
`0x2000-0x3FFF`) was considered as a closer geometric mirror of
ZX 128 lowmem (buffer + engine code share one always-resident
window). It is workable in principle but constrains the Page A
engine-code budget to roughly 3.5 KB after the `+cpc` clib's
CRT support routines — too tight for RAGE1's current lowmem
engine. Page C top is the chosen design; the Page A alternative
is recorded here as a fallback to revisit if Phase B4-1's lowmem
measurement shows the engine fits comfortably in ~3.5 KB, OR if
cpc-banked games run out of home-data room in Page C and a
swap of constraints becomes attractive.

Implications and choices recorded here:

- **`BANKED_DATASET_BASE_ADDRESS` changes from `0x5B00` on ZX 128
  to `0x8000` on cpc-banked** (the home-page buffer in RAM 2).
  Per the §3.2 invariant, the same `0x8000` is also the
  compile-time ORG for `dataset_N.bin` on cpc-banked. See §3.2.
- The CPC-side `engine_code_memory_bank` (analog of
  `ENGINE_CODE_MEMORY_BANK = 4` in
  `engine/include/rage1/memory.h:30`) is the RAM number we choose
  to host banked engine code (e.g. RAM 4).
- The swap-window mechanism uses cpctelera's `cpct_pageMemory()`,
  wrapped by a `cpc_memory_switch_bank(bank)` that maps `bank
  ∈ {3,4,5,6,7}` → MMR config:
  ```
  RAM 3 → MMR Config 3   (RAM 3 at 0x4000)
  RAM 4 → MMR Config 4   (RAM 4 at 0x4000)
  RAM 5 → MMR Config 5   (RAM 5 at 0x4000)
  RAM 6 → MMR Config 6   (RAM 6 at 0x4000)
  RAM 7 → MMR Config 7   (RAM 7 at 0x4000)
  default → MMR Config 0 (base 64K)
  ```
- The "default" / "home" state is **MMR Config 0**: RAM 0 / RAM 1 /
  RAM 2 / RAM 3 at A/B/C/D. RAM 3 sits at `0xC000` and is claimed
  by the screen (see "Why not page D?" above), so code/data cannot
  live in RAM 3 in this layout. The free extended banks for our
  datasets/codesets are **RAM 4, 5, 6, 7**.
- **Valid-banks lists** (cpc-banked side):
  ```
  dataset_valid_banks_cpc  = (5, 6, 7, 4)   # 4 × 16 KB = 64 KB
  codeset_valid_banks_cpc  = (5, 6, 7, 4)   # same pool
  ```
  Bank 4 is listed *last* because it hosts banked engine code
  (mirroring the ZX-128 `(1,3,7,6,4)` convention where bank 4 is
  also last); datasets / codesets only spill into bank 4 once
  banks 5/6/7 are full. See R8.
- This is **4 banks**, vs ZX 128's 5 banks. **Dataset capacity
  drops from 5×16 = 80 KB to 4×16 = 64 KB** on CPC 6128 — flag
  as a planning constraint. (CPC 6128 has 128 KB total, ZX 128
  has 128 KB total; the difference is that on ZX one of the
  "extended" banks — bank 6 — is co-mapped at neither always-on
  position, freeing it for swap; on CPC the 4 base-RAM banks
  (0/1/2/3) are *also* the always-mapped + screen banks and the 4
  extended banks (4/5/6/7) are the only swappable ones.)
- **Banked code bank choice**: pick **RAM 4** (mirrors the
  ZX-128 choice of bank 4 at `engine/include/rage1/memory.h:30`).
  Bank 4 was a "uncontended bank" choice on ZX; on CPC the choice
  is arbitrary, but matching the number keeps documentation
  symmetric.

##### Shape B (rejected): two swap windows

Use both `0x4000` (page B) and a hypothetical second window —
either `0xC000` (page D, requiring screen relocation to `0x4000`)
or splitting one of `0x0000`/`0x8000`. This would give 2 banks
visible simultaneously. Rejected because:

- Moving the screen to `0x4000` via CRTC R12/R13 collides with
  page B being our swap window.
- Splitting `0x0000` / `0x8000` requires firmware-disabled boot,
  cooperative CRT, and complicates the loader.
- Adds non-trivial engine logic for "which window does this bank
  live in?" that ZX-128 doesn't have.
- The extra throughput (2 windows) doesn't unlock a use case
  RAGE1 has: the dataset model is "swap one big blob into
  buffer at a time", not "two blobs visible".

Stick to Shape A (one swap window at `0x4000`).

### 3.2 Dataset/codeset/SUB analogues per platform

| Concept                | zx48                     | zx128                                                 | cpc-flat                        | cpc-banked                                            |
|------------------------|--------------------------|-------------------------------------------------------|---------------------------------|-------------------------------------------------------|
| Datasets (paged)       | ❌ (home only)            | ✅ Window `0xC000`, dest buf `0x5B00` (ORG = `0x5B00`) | ❌ (home only)                   | ✅ Window `0x4000`, dest buf `0x8000` (ORG = `0x8000`) |
| Codesets               | ❌ (calls inline to home) | ✅ Org `0xC000`, exec from window                      | ❌                               | ✅ Org `0x4000`, exec from window                      |
| Banked engine code     | ❌ (linked into main)     | ✅ Bank 4 @ `0xC000`                                   | ❌                               | ✅ RAM 4 @ `0x4000`                                    |
| SUBs (one-shot intros) | ✅ (SP1 buffer only)      | ✅ (DSBUF + SP1 buffer)                                | ✅ (limited; small free regions) | ✅ (DSBUF + SP1-equivalent region)                     |
| Home dataset           | ✅                        | ✅                                                     | ✅                               | ✅                                                     |

Concrete proposals:

**Invariant**: dataset ORG = dataset destination buffer base =
`<platform-specific addr>`. This is the "__orgit trick" of §1.2:
because each `dataset_N.bin` carries pre-resolved internal pointers,
the compile-time ORG must equal the runtime decompression
destination, **not** the swap-window source address. (On ZX 128:
ORG = DEST = `0x5B00`; the swap window at `0xC000` is only the
*source* the decompressor reads from.)

**Datasets on cpc-banked**:
- *Destination-buffer placement* (drives ORG): on ZX 128, the
  buffer at `0x5B00` is in bank 5 (always mapped) and the source at
  `0xC000+offset` is in the swapped bank — different physical RAM,
  no overlap. On cpc-banked with Shape A, the swap window *is* the
  source (at `0x4000`) and the destination buffer must be in a
  different page (e.g. `0x8000`-region). **Decision**: place the
  dataset decompression buffer in **page C (RAM 2, `0x8000–`)**
  — this is the home data page; reserve the first N KB of it as
  the decompression buffer. Concrete proposal: buffer at
  `0x8000–0x9FFF` (8 KB) or `0x8000–0xAFFF` (12 KB), exact size
  driven by largest decompressed dataset (computed by `datagen.pl`,
  same as ZX `BUILD_MAX_DATASET_SIZE`).
- Dataset binaries compiled `--no-crt` with **ORG `0x8000`**
  (matching the destination buffer base — see invariant above; was
  `0x5B00` on ZX). Compressed with ZX0. Decompressed at runtime
  from `0x4000 + offset_in_bank` (the swap-window content, i.e. the
  paged bank) into the home-page buffer at `0x8000`.

  Trade-off: this shifts home data up to `0xA000` (or `0xB000`) on
  cpc-banked, which is tighter than `0x5B00 = 23 KB-free` on
  ZX 128. Asset budget on cpc-banked therefore needs careful
  accounting; flag as Risk R3.

**Codesets on cpc-banked**:
- Codeset binary compiled with **ORG `0x4000`** (was `0xC000` on
  ZX). The first struct at `0x4000` is `codeset_assets_s`.
- `codeset_call_function()` is unchanged in shape; the `0xC000`
  literal in `engine/src/codeset.c:38` becomes a `#define`
  parameterised by platform.
- `codeset_assets` pointer points to `0x4000` on cpc-banked, to
  `0xC000` on ZX 128.

**Banked engine code on cpc-banked**:
- `banked_code.bin` compiled ORG `0x4000`. The "table of function
  pointers at the start of the bank" pattern
  (`doc/BANKED-FUNCTIONS.md:23-31`, also
  `tools/generate_banked_function_defs.pl:57`) is unchanged: the
  table is at the bank's base, which is `0x4000` on cpc-banked,
  `0xC000` on ZX 128.
- The literal `0xC000` in
  `engine/src/00lowmem.c:24,41,60` becomes a per-platform
  `BANKED_FUNCTION_TABLE_BASE` macro.

**SUBs**:
- The SUB model travels almost unchanged. The `LOAD_ADDRESS` /
  `ORG_ADDRESS` / `RUN_ADDRESS` triad continues to work; only the
  *default values* and the *loader's load-block mechanism* change.
- On cpc-flat: SP1-buffer-equivalent SUB lives somewhere in the
  16 KB above the engine (no SP1, but if a sprite library reserves
  a buffer, we use that — see `cpc-renderer.md`). DSBUF-equivalent
  doesn't exist because there's no dataset buffer.
- On cpc-banked: same as ZX 128 conceptually; specific addresses
  follow the new memory map (DSBUF analog at `0x8000`-region; the
  SP1-equivalent SUB target depends on whatever the CPC
  sprite-library buffer ends up at).
- The loader-side change is the `LD_BYTES` substitution (§3.5 /
  §4.2).

### 3.3 Bank-ID space (does CPC share IDs with ZX?)

**Decision**: bank IDs are **per-platform**. They are *not* shared
between ZX and CPC.

Rationale:

- ZX bank 4 ≠ CPC RAM 4 in any meaningful semantic sense. They are
  both "bank index 4 in the hardware's enumeration" but the
  hardware's enumeration is different.
- The valid-banks list (`@dataset_valid_banks`,
  `@codeset_valid_banks`) is itself per-platform (`(1,3,7,6,4)` on
  ZX, `(5,6,7,4)` on CPC). Numbering coincidence is incidental.
- Per-platform bank IDs keep `etc/rage1-config.yml`,
  `tools/banktool.pl`, `tools/loadertool.pl` simpler — no mapping
  table, no "if zx then bank 1 means…".

What this means concretely:

- `dataset_info.asm` continues to emit `(bank_num, size, offset)`
  tuples, with `bank_num` being whatever the platform's bank
  enumeration says.
- `memory_switch_bank(bank)` is a per-platform implementation
  (ZX uses port `0x7FFD`, CPC uses cpctelera `cpct_pageMemory()`
  with a per-platform bank→config mapping table).
- The `ENGINE_CODE_MEMORY_BANK` literal at
  `engine/include/rage1/memory.h:30` becomes per-platform
  (`4` on both, coincidentally; documented as coincidental).
- `etc/rage1-config.yml` gains per-platform sections (§4.4).

### 3.4 Screen RAM placement decisions

| Platform           | Screen RAM                                                                          | Configurable?                           | RAGE1's stance                                      |
|--------------------|-------------------------------------------------------------------------------------|-----------------------------------------|-----------------------------------------------------|
| zx48               | `0x4000–0x5AFF` (6912 B)                                                            | No (one screen)                         | Fixed                                               |
| zx128              | bank 5 at `0x4000` (normal) or bank 7 (shadow)                                      | Yes via `0x7FFD` bit 3                  | RAGE1 uses normal screen; shadow not used           |
| cpc-flat (464/664) | `0xC000–0xFFFF` (16 KB) by default; CRTC R12/R13 can move it to `0x4000` (mode 0/1) | Yes, but cpctelera defaults to `0xC000` | RAGE1 follows cpctelera default: screen at `0xC000` |
| cpc-banked (6128)  | Same as cpc-flat: default `0xC000`, CRTC-relocatable                                | Yes                                     | RAGE1 follows cpctelera default: screen at `0xC000` |

**The screen-base address interacts with the gfx HAL**
(`gfx.md`-owned). Where the screen sits is a banking concern (this
doc) only insofar as it carves out a piece of the address space
that code/data can't use. The pixel/attribute model and the
SP1/JSP/cpctelera tile/sprite indexing are gfx.md's problem.

Flagged for `gfx.md`: the existing engine sometimes computes
`screen_address = 0x4000 + row*32+col*256 …` style; any such
ZX-specific arithmetic must be hidden behind the HAL or the CPC
backend will mis-render. Audit cross-references:
`engine/include/rage1/btile.h`, `engine/src/btile.c`.

### 3.5 ISR / interrupt layout per platform

| Platform | Mode | IV table | ISR entry | Cooperation with paging |
|---|---|---|---|---|
| zx48 | IM 2 | `0xD000` (SP1) / `0xE000` (JSP) | `0xD1D1` / `0xE1E1` | n/a |
| zx128 | IM 2 | `0x8000` (configurable in yml) | `0x8181` (configurable) | ISR runs on whatever bank is paged; must be in low memory; `interrupt_nesting_level` interlocks the bank-switch atomicity |
| cpc-flat | IM 1 | n/a (single `0x0038` vector) | `0x0038` (3-byte jp); RAGE1 owns it after firmware disable | n/a |
| cpc-banked | IM 1 | same as cpc-flat | same | ISR + jp target live in page A (RAM 0, `0x0000–0x3FFF`), which is permanently mapped under MMR Config 0; the bank-switch primitive is also in page A, so even if MMR is mid-flight on Config N, returning to Config 0 brings everything back; same `interrupt_nesting_level` interlock applies |

Concrete CPC interrupt setup (both flat and banked):

1. Disable firmware (`cpct_disableFirmware()`).
2. Install our jp at `0x0038` (RST 38 vector).
3. Write our ISR body somewhere in page A (e.g. `0x003B`).
4. `ei`.

The CPC ISR fires **300 times per second**, every 52 HSYNCs —
this rate is **fixed by the Gate Array hardware, not programmable**
(unlike the ZX which derives a single 50 Hz frame interrupt).
cpctelera's `firmware/cpct_setInterruptHandler` accepts a function
pointer and chains correctly. The only practical seam for RAGE1's
50 Hz cadence is therefore a divide-by-six in software. For
RAGE1's purposes the timer-tick semantics in
`engine/src/interrupts.c:34-46` need either to (a) divide the CPC
ISR ticks down to a 50 Hz time-tick (one-in-six counter), or (b)
hook a different CPC mechanism for 50 Hz. **Decision**: do (a)
inside the CPC ISR; it's simpler and isolated to one
platform-specific file.

The `etc/rage1-config.yml` interrupts section (`interrupts_128:`
key) gains `interrupts_cpc_flat:` and `interrupts_cpc_banked:`
peers. The CPC sections may be much simpler (just a few
fixed-address constants) but the symmetry is worth keeping.

#### 3.5.1 Interaction between 300 Hz ISR and the banked-function dispatcher (cpc-banked)

`cpc-banked` is the one configuration where the 300 Hz CPC tick
collides with non-trivial banking state. The interaction is worth
analysing up front so Phase B6 / B7 / AU5 budget for it rather than
discovering it under a live music player.

**The three actors:**

1. **The CPC ISR**, firing every 1/300 s, divided down to 50 Hz
   in software for `do_timer_tick()`.
2. **The audio tick** (music player + SFX mixer). On CPC this is
   the AT2 AKG generic player driving the AY chip. The player's
   call cadence is the music's row rate (typically 50 Hz, derived
   from the divided ISR counter — not the raw 300 Hz tick).
3. **The banked-function dispatcher**, which mid-frame may be in
   the middle of: save Config N → switch to Config M → run callee
   → switch back to Config N. The window between the two MMR
   writes is the dispatcher's critical section, and it runs with
   interrupts **enabled** by default (RAGE1's existing idiom on
   ZX128, where the IV table at `0x8000` is reachable from every
   paged-in configuration).

**The interaction matrix.** Each row is "what can be running when
the ISR fires", and what guarantees we need:

| Foreground state | What the ISR may need to do | Guarantee required |
|---|---|---|
| Engine code in Page A, no bank switch in flight | divide-by-six counter; eventual 50 Hz tick | ISR + ISR-callees fit in always-mapped memory (Page A, or low-RAM region also mapped under every Config) |
| Banked-function dispatcher mid-switch (MMR write completed, callee not yet entered) | same | same — but ISR must NOT itself trigger an MMR write, because the foreground's "restore" relies on `memory_current_memory_bank` being untouched |
| Banked codeset running (Config N ≠ Config 0) | same — divide-by-six only | ISR body and the divide-by-six counter must be reachable from Config N. On cpc-banked, Page A (`0x0000–0x3FFF`) is permanently mapped under every MMR Config including Config 0 → trivially satisfied if the ISR lives in Page A |
| 50 Hz tick fires — `do_timer_tick()` chain wakes the music player | music player tick may itself walk through several memory regions | music player code + AY register state + interrupt-time critical data MUST live in always-mapped memory. **Decision**: the AT2 AKG player and `audio_*` tick handler live in Page A (always-resident), NOT in a banked codeset; flow-rule eval and other tick-callbacks may live in banked codesets |

**Two design rules fall out of this:**

- **Rule A — ISR body is always-resident.** The ISR at `0x0038`
  jumps to a body in Page A (`0x003B`-ish, or any Page A address).
  No ISR-callee runs out of a banked codeset. This matches the
  table above and is the same invariant as ZX128's "ISR in low
  memory" rule.
- **Rule B — audio tick runs without re-paging.** The
  AT2 AKG generic player binary (~1.5 KB) and `audio_cpctel_*.c`
  glue live in Page A. The player advances per-row state and
  writes AY registers via z88dk's `out` intrinsics; both are
  Page-A-resident operations. Music data (`.akg` byte stream) is
  laid out by `cpct_audio` macros into a known address — placed
  in Page A by `Makefile-cpc-banked` if it fits, otherwise hosted
  in a per-music-track codeset that the ISR pages in *itself*
  with the same "save / restore Config" idiom (then the dispatcher
  must tolerate an ISR-driven Config flip — see Rule C below).
  **Default plan**: music data fits in Page A; we revisit only if
  a real game's `.akg` files push us past Page A's budget.
- **Rule C (only if Rule B's "music in Page A" assumption breaks).**
  If the ISR itself ends up calling `cpc_memory_switch_bank()` to
  fetch the next row of music data from a banked codeset, then
  the foreground dispatcher's two-MMR-write critical section MUST
  be reformulated as `di; mmr_write; ...callee...; mmr_write; ei`
  (interrupts disabled during the entire bank-switch round-trip).
  This is the conservative form; we adopt it only if measurement
  forces it. **Cost**: a few microseconds of jitter on the
  foreground per banked call; the divided-down 50 Hz tick still
  fires because the 300 Hz tick missed during the DI is recovered
  on the next ISR.

**Worst-case ISR cost budget (back-of-envelope, to be verified
empirically in Phase B6 / AU5):**

- Divide-by-six counter + 50 Hz fanout: ~40 T-states ≈ 10 µs at
  4 MHz.
- 50 Hz music player tick (every 6th ISR): ~3000 T-states ≈
  750 µs at 4 MHz, depending on the song. AT2 AKG's documented
  per-tick CPU is in this range; in practice songs vary.
- 300 Hz raw cost = `(non-tick × 5 + tick × 1) / 6`. With the
  numbers above: `(10 µs × 5 + 760 µs × 1) / 6` ≈ 135 µs average,
  or ≈ 4 % of the 3333 µs ISR period at 4 MHz. Easily affordable.
- Dispatcher worst-case latency (foreground impact): one extra
  MMR write `out (c), a` ≈ 12 T-states ≈ 3 µs. Negligible.

**Where this gets verified**: Phase **B6** (cpc-banked banking
infrastructure) measures the actual dispatcher cost on real
hardware/emulator; Phase **AU5** (real CPC audio) measures the
music player's actual per-tick cost. README §6 carries this as a
cross-cutting risk; banking.md R4 / R5 / R6 carry the per-doc
slices.

---

## 4. Tooling changes

### 4.1 `banktool.pl`: parametrise or split?

**Decision: parametrise the single tool**, with a
`--platform=zx128|cpc-banked` flag (default `zx128` for back-
compat). Rejected alternative: split into `banktool-zx.pl` and
`banktool-cpc.pl`.

Rationale:

- The bin-packing algorithm (`do_dataset_layout`,
  `tools/banktool.pl:174-211`) is platform-agnostic — same `N!`
  permutation walk, same per-bank capacity, same per-binary size.
  Replicating it in two scripts would double the surface for the
  same logic.
- The platform-specific pieces are small:
  1. The `@dataset_valid_banks` / `@codeset_valid_banks` lists.
  2. The pre-occupied bank-4 setup
     (`tools/banktool.pl:91-121`) — the "reserved bank for engine
     code" — which exists on both platforms.
  3. The `$max_bank_size` constant (`16384` on both — identical).
- The output formats (`bank_N.bin`, `bank_bins.cfg`,
  `dataset_info.asm`, `codeset_info.asm`) are platform-agnostic in
  shape — same struct layout, different bank numbers.

Concrete change to `tools/banktool.pl`:

```perl
# Replace lines 25,28 with a per-platform lookup:
my %platform_banks = (
    'zx128' => {
        codeset => [ 6, 1, 3, 7 ],
        dataset => [ 1, 3, 7, 6, 4 ],
        engine_code_bank => 4,
    },
    'cpc-banked' => {
        codeset => [ 5, 6, 7, 4 ],     # bank 4 last (engine code)
        dataset => [ 5, 6, 7, 4 ],     # prefer non-engine-code first
        engine_code_bank => 4,
    },
);
```

Plus a `getopts` extension to accept `-p <platform>`; the new tool
contract is:

```
banktool.pl -p <platform> -i <dataset_dir> -c <codeset_dir>
            -o <output_dir> -s <bank_switcher> [-l <lowmem_dir>]
```

`engine/banked_code/banked_code.bin` reference at
`tools/banktool.pl:104-112` stays the same (the engine code lives
in a different *file* per platform, but the file *path* relative to
the build is identical — see §4.3).

Coordinate with `toolchain.md` §3.5 / Phase T3-5: the same
parametrisation is already anticipated there.

### 4.2 `loadertool.pl`: parametrise (coordinate with toolchain.md)

**Decision**: parametrise the single tool, with a
`--platform=zx48|zx128|cpc-flat|cpc-banked` flag. `toolchain.md`'s
Phase T1-10 already promises this for ZX; this doc extends to CPC.

The current `loadertool.pl` is **510 lines** and most of its bulk
is the `generate_assembler_loader` function
(`tools/loadertool.pl:203-485`), which emits Z80 assembly using ZX
ROM calls (`LD_BYTES` at `0x0556`). On CPC the loader is
fundamentally different (it gets the data from AMSDOS or a tape
block via firmware, *or* the loader is itself a pre-assembled stub
chained from an AMSDOS-headed `.cpc` file).

Two strategies considered:

| Option | Description | Verdict |
|---|---|---|
| **A. Template selection** | The single tool reads a per-platform asm template (e.g. `engine/loader-{zx48,zx128,cpc-flat,cpc-banked}/asmloader.asm.in`), does variable interpolation (bank addresses, sizes, SUB list, …). | **Chosen.** |
| **B. Per-platform script** | `loadertool-zx.pl`, `loadertool-cpc.pl`. | Rejected — duplicates 60 % of the perl that gathers banks/subs/sizes. |

The shape after change:

```
loadertool.pl
   read platform from .gdata (or --platform option)
   gather bank binaries          # platform-agnostic
   gather sub binaries           # platform-agnostic
   sanity_check_sub_binaries     # platform-agnostic
   load template engine/loader-<platform>/asmloader.asm.in
   substitute placeholders for:
       - bank list (sizes, dest addresses)
       - sub list (load_addr, org_addr, run_addr, compress)
       - main_code_start / main_size
   write build/generated/asmloader/asmloader.asm
```

Concrete CPC template content for `cpc-banked`:

```asm
    org $LOADER_ORG     ; e.g. 0x4000 — TBD by Makefile-cpc-banked
    di                  ; firmware off / interrupts off

%FOR bank IN $BANK_BINS%
    ld a, %BANK_ID%
    call cpc_bswitch    ; calls cpct_pageMemory or our wrapper
    ld hl, %BANK_BIN_LOAD_ADDR%   ; pre-loaded by AMSDOS at this address
    ld de, 0x4000        ; swap-window dest
    ld bc, %BANK_SIZE%
    ldir
%ENDFOR%

    xor a               ; back to MMR Config 0 (base 64K)
    call cpc_bswitch
    jp $MAIN_CODE_START
```

(Plus SUB handling, mirroring the ZX flow.)

The choice of "AMSDOS pre-loads the whole .cpc into one
contiguous region, then we ldir it into banks" vs "firmware load
each bank from disk individually" depends on whether we ship as
`.dsk` (firmware load per-block possible) or `.cdt` (tape, one big
block easiest). `toolchain.md` §4.2 leaves both options open and
recommends `appmake +cpc -subtype=disk` (DSK) as the default. Final
decision deferred to Phase B5 in this plan and `cpc-renderer.md`
Phase R3.

Hard-coded constants to lift:
- `$loader_org_48 = 0x5E00`, `$loader_org_128 = 0x8000`
  (`tools/loadertool.pl:33-34`) → per-platform constants in
  `etc/rage1-config.yml`.
- The `bswitch` asm subroutine at `tools/loadertool.pl:368-378` →
  per-platform template snippet (ZX uses port `0x7FFD`, CPC uses
  cpctelera macro).
- The `ZX_TARGET` and `SPRITE_ENGINE` parsing at
  `tools/loadertool.pl:164-195` → replaced by reading `PLATFORM`
  (and `GFX_BACKEND`) from the merged config; coordinate with
  `assets.md` Phase A1 and `toolchain.md` Phase T1-1.

### 4.3 Bank-binary emission per platform

`engine/banked_code/` becomes a per-platform tree:

```
engine/banked_code/common/        # compiled into all banked builds
                                  # (today: zx128 and cpc-banked)
engine/banked_code/zx128/         # was: engine/banked_code/128/
engine/banked_code/cpc-banked/    # new: CPC 6128 banked engine code
```

`Makefile.common:58-69` (the `BANKED_CODE_*` variables) generalises
from `BANKED_CODE_*_128` to `BANKED_CODE_*_$(PLATFORM_BANKED_TAG)`
where `PLATFORM_BANKED_TAG` is set by the per-platform Makefile
(empty / not set on flat builds, `zx128` on `Makefile-zx128`,
`cpc-banked` on `Makefile-cpc-banked`).

The `banked_code.bin` file path
(`Makefile.common:69`,
`tools/banktool.pl:104-112`) becomes
`engine/banked_code/<platform>/banked_code.bin` *or* stays at the
common path `engine/banked_code/banked_code.bin` with build
isolation via `build/` (cleanup between platform builds). The
latter is simpler; recommend it.

Per-platform org addresses for bank binaries:

| Platform   | Banked-code ORG | Codeset ORG | Dataset ORG (compile-time) | Dataset DEST (runtime) |
|------------|-----------------|-------------|----------------------------|------------------------|
| zx128      | `0xC000`        | `0xC000`    | `0x5B00`                   | `0x5B00`               |
| cpc-banked | `0x4000`        | `0x4000`    | `0x8000`                   | `0x8000`               |

Note the invariant from §3.2: **dataset ORG = dataset DEST** on
every platform (the "__orgit trick" pre-resolves internal pointers
for the load address). Banked-code and codeset ORGs match the swap
window, because they execute in place from the window; dataset
ORG matches the destination buffer, because the dataset is
decompressed there before any pointer is followed.

The `Makefile-cpc-banked` carries these constants the same way
`Makefile-128:21-22` carries 128K constants (read from
`etc/rage1-config.yml`).

### 4.4 `etc/rage1-config.yml` extensions

**Naming-axis note**: this document keys YAML sections and tool
arguments off the **memory-model axis**
(`zx48 | zx128 | cpc-flat | cpc-banked`) rather than the
machine-identity axis (`zx48 | zx128 | cpc464 | cpc6128`) used by
`toolchain.md` §3.1's `PLATFORM` variable. The mapping is bijective
in Phase 1 (4 ↔ 4): `cpc464 → cpc-flat`, `cpc6128 → cpc-banked`.
CPC664 is supported as a *runtime target* of the cpc464 build —
memory-identical to CPC464 — and so does not appear as a separate
identity on either axis. See `toolchain.md` §3.1 for the full
PLATFORM-vs-memory-model split.

Add per-platform sections, keep the existing `interrupts_128`
shape so ZX builds don't change:

```yaml
# Existing — unchanged
interrupts_128:
  iv_table_addr: 0x8000
  isr_vector_byte: 0x81
  isr_vector_address: 0x8181
  base_code_address: 0x8184

# New
interrupts_cpc_flat:
  isr_address: 0x0038
  base_code_address: 0x4000     # or wherever toolchain.md settles
  stack_top: 0xBFFF             # CRT_STACK_SIZE driven separately

interrupts_cpc_banked:
  isr_address: 0x0038
  base_code_address: 0x0040     # ISR + lowmem code packs first
  stack_top: 0xBFFF
  banked_code_org: 0x4000
  codeset_org: 0x4000
  dataset_compile_org: 0x8000     # = dataset_runtime_dest (§3.2 invariant)
  dataset_runtime_dest: 0x8000

# New banking section: per-platform bank policy
banking:
  zx128:
    dataset_banks: [1, 3, 7, 6, 4]
    codeset_banks: [6, 1, 3, 7]
    engine_code_bank: 4
    bank_size: 16384
    swap_window: 0xC000
  cpc-banked:
    dataset_banks: [5, 6, 7, 4]
    codeset_banks: [5, 6, 7, 4]
    engine_code_bank: 4
    bank_size: 16384
    swap_window: 0x4000
```

Consumers update:
- `Makefile.common:96-100` reads from the platform's own
  `interrupts_*` section.
- `tools/banktool.pl` reads the `banking.<platform>` section (new
  source of truth replacing hard-coded `@dataset_valid_banks` /
  `@codeset_valid_banks`).
- `tools/loadertool.pl` reads platform-specific orgs from the same
  config.
- `tools/generate_banked_function_defs.pl:57` reads the
  `banked_code_org` from the platform section (replacing the
  hard-coded `0xC000`).

Per-banked-function entries (`banked_functions:` list at
`etc/rage1-config.yml:59-114`) stay platform-agnostic — the
*declarations* of what banked functions exist are shared across
ZX 128 and CPC 6128.

---

## 5. Dataset-size-budget under CPC layouts

`assets.md`'s Risk paragraph
(`doc/multiplatform-plan/assets.md:1048-1057`) deferred the CPC
asset-size budget to this document. Here's the analysis.

**Pixel-byte sizes per platform**:

| Format                  | bpp        | Bytes for an 8×8 cell | Bytes for a 16×16 sprite (no mask) |
|-------------------------|------------|-----------------------|------------------------------------|
| ZX 1-bpp + 1 attr       | 1 + (1/64) | 8 + ε                 | 32                                 |
| CPC mode 1 (4 colours)  | 2          | 16                    | 64                                 |
| CPC mode 0 (16 colours) | 4          | 32                    | 128                                |

So CPC mode-1 sprite/tile data is **~2× the bytes** of ZX
attribute-mode data; CPC mode-0 is **~4× the bytes**. Masks
(if present) add another bitmap of the same size in mode 1 (or
double in mode 0), depending on how cpctelera encodes them.

**Budget impact on cpc-banked datasets**:

- ZX 128 dataset capacity (uncompressed, per dataset): up to
  `DATASET_MAXSIZE` ≈ 9 KB after the LOWMEM buffer carve-out
  (`Makefile.common:50`). With ZX0 compression and 80 KB of
  bank space (5 banks), a game typically fits 10–15 datasets.
- cpc-banked dataset capacity, Shape A: 4 banks × 16 KB = **64 KB
  total bank space**, ~3 KB destination buffer headroom. With
  ZX0 compression, that's roughly **64 KB / ~2× CPC-bytes-per-
  ZX-byte = effective ~32 KB of "ZX-equivalent" content**.

  In other words, **a game designed against ZX 128's bank budget
  will need substantially fewer screens per dataset on CPC 6128**,
  or smaller per-screen tile counts, or per-platform overlays
  that ship richer art on ZX 128 and more austere art on CPC 6128.

- cpc-flat: dataset model doesn't apply (no banking); all assets
  live in the home dataset, which fits in whatever the 64 KB CPU
  map leaves after engine + screen + stack. Tightness depends on
  the game's code/asset ratio (CPC464's ~46-48 KB usable RAM vs
  ZX48's ~41 KB partly offsets the 2× mode-1 / 4× mode-0 byte
  multiplier — see §3.1.3). Mode 0 is materially tighter than
  mode 1 on cpc-flat (4× asset bytes vs ZX 1bpp), so a non-trivial
  mode-0 game is likely to need per-platform overlays trimming
  sprite/tile counts, or a small game design. Final viability is a
  per-game judgement call deferred to execution.


**Decision**: `datagen.pl` continues to enforce
`DATASET_MAXSIZE` per-platform. The value is computed:

| Platform   | Buffer                          | DATASET_MAXSIZE                     |
|------------|---------------------------------|-------------------------------------|
| zx48       | n/a                             | ∞ (home only; gated by overall RAM) |
| zx128      | `0x5B00–0x7FFF` minus heap      | ~9 KB                               |
| cpc-flat   | n/a                             | ∞ (gated by overall RAM)            |
| cpc-banked | `0x8000–0x9FFF` (proposed 8 KB) | ~8 KB                               |

The `datagen.pl` macro that emits `BUILD_MAX_DATASET_SIZE`
(`Makefile.common:50`) needs to be platform-aware. Concrete
proposal: emit
`BUILD_MAX_DATASET_SIZE_<PLATFORM>` and have `Makefile.common` pick
the right one.

**Mitigation strategy**:

1. Use ZX0 aggressively (already in place).
2. Default to **CPC mode 1** (not mode 0) — the 2× factor is more
   manageable than 4×. Track as `cpc-renderer.md` OQ-1 (already
   leaning this way).
3. The per-platform asset overlay path (assets.md Tier 2 / 3,
   `doc/multiplatform-plan/assets.md:471-498`) lets authors ship
   different art per platform when the size budget bites.
4. Document this clearly: a "default" RAGE1 game probably can't
   target cpc-banked without art trimming or per-platform
   overlays.

Track as Risk R3.

---

## 6. Phased work plan

The phases below assume `toolchain.md`'s Phase T1 (introduce
`PLATFORM` axis) and (eventually) Phase T2/T3 (CPC bring-up) land
in parallel; banking phases pick up where toolchain phases hand
off. Each phase ends green per the project's "phase-exit green"
rule:
- `make all-test-builds` (ZX subset) green at every phase exit.
- `tests/00regression/` ZX screenshots green at every phase exit.
- Phase-specific exit criteria below.

Numbering: **B = Banking**, phases **B1, B2, …**, tasks **B1-1**…

### Phase B1 — Banking-config externalisation (ZX-only, no behaviour change)

**Goal**: lift hard-coded banking constants from Perl tools into
`etc/rage1-config.yml`, keeping behaviour byte-identical for ZX.

- **B1-1** Extend `etc/rage1-config.yml` with a `banking:` top-
  level key, with sub-key `zx128` populated from the current
  hard-coded values in `tools/banktool.pl:25,28` and
  `engine/include/rage1/memory.h:30`.
  - *What to test*: diff the YAML vs documentation; build.
- **B1-2** Update `tools/banktool.pl` to read the `banking.zx128`
  section instead of using its own hard-coded `@dataset_valid_banks`
  / `@codeset_valid_banks`. Keep the hard-coded values as fallback
  with a deprecation warning if the YAML is missing the section.
  Add `-p <platform>` option with default `zx128`.
  - *What to test*: rebuild every test game; `bank_bins.cfg`,
    `dataset_info.asm`, `codeset_info.asm` byte-identical to
    pre-change; `make all-test-builds`.
- **B1-3** Update `tools/generate_banked_function_defs.pl` so that
  the `org 0xC000` literal (`generate_banked_function_defs.pl:57`)
  is parameterised — read `banking.<platform>.swap_window` from
  YAML. Default `zx128` so behaviour unchanged.
  - *What to test*: diff
    `build/generated/banked/128/00banked_function_table.asm`
    against pre-change; `make all-test-builds`.
- **B1-4** Update `engine/include/rage1/memory.h:30`
  (`ENGINE_CODE_MEMORY_BANK = 4`) to be a `#ifdef
  BUILD_FEATURE_PLATFORM_ZX128`-gated definition; introduce
  `BUILD_FEATURE_PLATFORM_*` macros if not yet present (cross-
  depend on `toolchain.md` T1-8).
- **B1-5** Update the `0xC000` literals in
  `engine/src/00lowmem.c:24,41,60` and
  `engine/src/codeset.c:38` to use a
  `BANKED_FUNCTION_TABLE_BASE` / `CODESET_ASSETS_BASE` macro
  defined in `memory.h` / `codeset.h`, defaulting to `0xC000` on
  ZX 128. Behaviour byte-identical on ZX.
  - *What to test*: `make all-test-builds`; diff binaries.
- **Phase-exit criteria**:
  - All ZX banking constants now live in `etc/rage1-config.yml`
    under `banking.zx128`.
  - ZX behaviour byte-identical to pre-B1.
  - `make all-test-builds` and `tests/00regression/` green.

### Phase B2 — Banking-config split for ISR/codeset semantics

**Goal**: prepare per-platform interrupt and codeset config without
touching CPC yet.

- **B2-1** Reorganise `etc/rage1-config.yml`'s `interrupts_128:`
  key so it sits inside a per-platform tree:
  ```yaml
  interrupts:
    zx128: { iv_table_addr: 0x8000, … }
  ```
  Keep `interrupts_128:` as a **permanent silent alias** at the
  top level (per README §5.6); the loader recognises both spellings
  indefinitely. No removal scheduled.
- **B2-2** Update `Makefile.common:96-100` to read from the new
  nested location with a fallback to the old.
- **B2-3** Update `engine/src/interrupts.c:78-98` so the
  `BUILD_FEATURE_ZX_TARGET_128` / `ZX_TARGET_48` defines become
  `BUILD_FEATURE_PLATFORM_ZX128` / `PLATFORM_ZX48`. Stub fallback
  for missing platform.
- **Phase-exit criteria**:
  - `etc/rage1-config.yml` reflects a per-platform tree.
  - ZX builds byte-identical.

### Phase B3 — Lowmem checks: parameterise the threshold

**Goal**: turn the implicit `0xC000` threshold in `lowmemsym.pl`,
`mmap.inc` discipline, and the lowmem invariant into an explicit,
platform-aware constant.

- **B3-1** Update `tools/lowmemsym.pl` to accept a `--threshold`
  option (default `0xC000`). Pass from `Makefile-128:64` as
  `--threshold $(SWAP_WINDOW_zx128)`.
- **B3-2** Audit `mmap.inc` (248 lines, 97 sections) for any
  position-dependent assumptions. Document a per-platform mmap.inc
  policy: ZX 128 keeps `mmap.inc` as is; ZX 48 has no banking
  pressure so the existing default Z88DK mmap is fine; CPC needs
  new `mmap-cpc-flat.inc` and `mmap-cpc-banked.inc` (created in
  Phase B5).
- **B3-3** Update `tools/check_mmap_sections.sh` to accept a
  `--mmap <file>` argument so it can validate different mmap.inc
  variants. Default unchanged.
- **Phase-exit criteria**:
  - `lowmemsym.pl` and `check_mmap_sections.sh` accept per-
    platform parameters.
  - ZX builds byte-identical.

### Phase B4 — Document and freeze the CPC banking model

**Goal**: nail the design choices in §3 before writing CPC code.
This is documentation work; no engine/tool changes.

- **B4-1** Finalise §3.1.3 (cpc-flat memory map) and §3.1.4
  (cpc-banked memory map) numbers. Verify against cpctelera's
  default `CRT_ORG_CODE` and stack assumptions; if cpctelera
  forces different defaults, update §3.1 to match.
- **B4-2** Validate the "swap window at `0x4000`, dataset buffer
  at `0x8000`" decision against a hand-walk of a hypothetical
  small CPC game: hero sprite at home, one dataset of ~6 KB,
  one codeset, interactive call paths. Confirm no cross-page
  data hazards.
- **B4-2a** Hand-walk worst-case stack nesting on both CPC
  profiles (ISR entry + nested cpctelera library calls + deepest
  C call chain) and freeze the stack budget for §3.1.3 and §3.1.4.
  Initial budget of 256 B is a placeholder; ZX 128's 128 B is
  already tight, and CPC adds cpctelera frames on top, so 256 B is
  the floor, not the target.
- **B4-3** Document the bank-ID convention (per-platform, not
  shared — §3.3) in the `etc/rage1-config.yml` comment block.
- **B4-4** Cross-reference with `cpc-renderer.md` Phase R2 (PoC
  that compiles cpctelera + an empty game): align on where the
  screen RAM, cpctelera library data, and CRT live. Adjust §3.1.4
  if R2 surfaces a constraint.
- **Phase-exit criteria**:
  - §3.1.3 and §3.1.4 numbers are final and reviewed.
  - `cpc-renderer.md` author has signed off on the memory map.
  - This document is the single source of truth for the CPC
    memory map; `etc/rage1-config.yml` placeholders are added.

### Phase B5 — cpc-flat banking-config (no banking, but the seam exists)

**Goal**: stand up cpc-flat as a real PLATFORM in the banking
config, even though it has no banking. Mirror of the ZX 48
"banking compiles out" pattern.

- **B5-1** Add `banking.cpc-flat: { swap_window: null,
  bank_size: null, dataset_banks: [], codeset_banks: [],
  engine_code_bank: null }` to `etc/rage1-config.yml`. Add
  `interrupts.cpc-flat`. Add `cpc-flat` to the platform allowlist
  in `tools/banktool.pl` and `tools/loadertool.pl`.
- **B5-2** Create `mmap-cpc-flat.inc` (per §3.1.3). Reference from
  `zpragma-cpc-flat.inc` (lives in `toolchain.md` T2-2).
- **B5-3** Create `engine/loader-cpc-flat/` skeleton: an
  `asmloader.asm.in` template that does a no-op
  (cpc-flat → no banks to switch) but is shaped to be filled by
  `loadertool.pl`. Coordinate with `toolchain.md` T2-4.
- **B5-4** Update engine source to gate banking-related code on
  `BUILD_FEATURE_PLATFORM_ZX128 || BUILD_FEATURE_PLATFORM_CPC_BANKED`
  rather than `BUILD_FEATURE_ZX_TARGET_128`. Files affected:
  `engine/src/00bswitch.c:48`,
  `engine/src/00lowmem.c:20-77`,
  `engine/src/codeset.c:21,72`,
  `engine/src/dataset.c:27,65-74`. Stubs / aliases must compile
  cleanly with `BUILD_FEATURE_PLATFORM_CPC_FLAT`.
- **B5-5** Add a synthetic CPC-flat compile-test game (mirrors
  `games/00cpc-compile-test/` from `gfx.md` G7-4 if it's the same
  game). Verify it compiles the engine without banking-code
  errors. Linkage may not succeed yet (no real CPC binary
  produced); the goal is C-level shaping.
- **Phase-exit criteria**:
  - cpc-flat is a recognised PLATFORM in `etc/rage1-config.yml`
    and all banking tools.
  - Engine source compiles cleanly under `BUILD_FEATURE_PLATFORM_CPC_FLAT`.
  - ZX builds byte-identical.

### Phase B6 — cpc-banked banking infrastructure (engine-side)

**Goal**: implement the CPC 6128 bank-switch primitive,
`memory_call_banked_function*` variants, dataset/codeset infra. No
data flowing yet, but the engine knows how to switch banks.

- **B6-1** Add `engine/src/00bswitch_cpc.c` (or a unified
  `00bswitch.c` with `#ifdef BUILD_FEATURE_PLATFORM_CPC_BANKED`
  branch). Wrap `cpct_pageMemory()` in a
  `memory_switch_bank(bank)` function that maps `bank ∈ {4,5,6,7}`
  to MMR config and tracks state in
  `memory_current_memory_bank`. Atomicity: DI / out / EI same as
  ZX (`engine/src/00bswitch.c:82-105`).
- **B6-2** Decide on one of: (a) keep one
  `memory_switch_bank(bank)` API with a per-platform mapping
  table inside; or (b) introduce
  `memory_switch_bank_zx`/`_cpc` and `#define` the active one.
  Recommendation: (a) — minimises C-level branching in callers.
- **B6-3** Update `engine/src/00lowmem.c` so the
  `memory_call_banked_function*` helpers compile on cpc-banked
  with the new `BANKED_FUNCTION_TABLE_BASE` constant
  (`0x4000` on CPC vs `0xC000` on ZX, from
  `etc/rage1-config.yml`).
- **B6-4** Update `engine/src/codeset.c` and `engine/src/dataset.c`
  to use `BANKED_FUNCTION_TABLE_BASE` / `CODESET_ASSETS_BASE` /
  `BANKED_DATASET_BASE_ADDRESS` macros per platform.
  `BANKED_DATASET_BASE_ADDRESS` becomes per-platform: `0x5B00` on
  ZX 128, `0x8000` on cpc-banked. **Honour the §3.2 invariant**:
  whatever value `BANKED_DATASET_BASE_ADDRESS` takes on a platform
  is *also* the compile-time ORG for `dataset_N.bin` on that
  platform (§4.3 table, §3.2 callout). The dataset destination
  buffer address and the dataset compile ORG are one constant, not
  two.
- **B6-5** Add `engine/banked_code/cpc-banked/` directory with
  initial files mirroring the names of
  `engine/banked_code/128/` — even if their content is identical,
  they get separate per-platform compilation to allow different
  ORG / different per-bank layout.
- **B6-6** Add `mmap-cpc-banked.inc` per §3.1.4. Reference from
  `zpragma-cpc-banked.inc` (toolchain.md T3-2).
- **B6-7** Update `Makefile.common:58-70` so `BANKED_CODE_DIR_128`
  becomes `BANKED_CODE_DIR_<PLATFORM_BANKED_TAG>`, set by the
  per-platform Makefile.
- **B6-8** Update `engine/src/interrupts.c` so the IM 1 +
  `0x0038` setup is enabled on cpc-flat and cpc-banked. New file
  `engine/src/interrupts_cpc.c` or `#ifdef` branches. Hook the
  CPC ISR 300 Hz → 50 Hz divide-by-six.
- **Phase-exit criteria**:
  - Engine source compiles cleanly under
    `BUILD_FEATURE_PLATFORM_CPC_BANKED` with all banking infra
    on.
  - `memory_switch_bank` callable from a synthetic test program
    on the CPC. Validation may be a `make build-cpc6128
    target_game=games/cpc-bswitch-test` that toggles MMR configs
    and exits.
  - ZX builds byte-identical to B5 exit.

### Phase B7 — cpc-banked tooling (banktool, loadertool, asmloader template)

**Goal**: get `tools/banktool.pl` and `tools/loadertool.pl`
producing real CPC bank binaries and a working CPC asmloader.

- **B7-1** Extend `tools/banktool.pl` with `banking.cpc-banked`
  bank lists from `etc/rage1-config.yml`. Reserve RAM 4 for engine
  code (mirror of bank-4 reservation in
  `tools/banktool.pl:101-121`). Validate against a real CPC
  dataset/codeset compile output, including that the dataset binary
  is ORG'ed at `0x8000` (= `BANKED_DATASET_BASE_ADDRESS`, per the
  §3.2 invariant — *not* at the swap-window address `0x4000`).
- **B7-2** Create `engine/loader-cpc-banked/asmloader.asm.in`
  template (§4.2). Use cpctelera macros / our wrapper. The
  asmloader must:
  1. Load each bank's payload into the swap window (`0x4000`)
     after setting the right MMR config.
  2. Optionally decompress (datasets are ZX0; codesets and
     banked-code are uncompressed).
  3. Load SUBs (§3.2 / `doc/SINGLE-USE-BLOBS.md`).
  4. Reset MMR to Config 0; `jp $MAIN_CODE_START`.
- **B7-3** Update `tools/loadertool.pl` to read templates from
  `engine/loader-<platform>/asmloader.asm.in` and do variable
  substitution. Lift `$loader_org_48` and `$loader_org_128`
  literals into `etc/rage1-config.yml`. Pass `--platform`
  argument.
- **B7-4** Add SUB defaults for cpc-banked: where does
  DSBUF-equivalent live (`0x8000`-region)? Where does
  SP1-buffer-equivalent live (depends on cpctelera —
  `cpc-renderer.md` Phase R2 should have surfaced this)? Document
  defaults in `doc/SINGLE-USE-BLOBS.md`.
- **B7-5** Add a CPC-banked smoke-test game
  (`games/cpc-banked-test/`) with one trivial dataset, one
  trivial codeset, no SUBs. Build, run on emulator, observe
  dataset swap visible.
- **Phase-exit criteria**:
  - `make build-cpc6128 target_game=games/cpc-banked-test`
    produces a runnable `.dsk` (or `.cdt`).
  - The asmloader correctly bank-switches and the engine reads
    the right bytes from the swap window.
  - ZX builds byte-identical.

### Phase B8 — SUB infrastructure on CPC

**Goal**: full SUB support on cpc-flat and cpc-banked, including
the swap/restore and decompress paths.

- **B8-1** Define SUB-target buffer addresses for cpc-flat (likely
  the cpctelera sprite library's scratch buffer if it has one)
  and cpc-banked (the dataset buffer). Update
  `doc/SINGLE-USE-BLOBS.md` with a per-platform table.
- **B8-2** Update the CPC asmloader template (B7-2 already in
  place) with SUB load + swap + decompress + run logic, mirroring
  `tools/loadertool.pl:274-348`. Use cpctelera firmware-disabled
  block load primitives or our own loader (decision lives in
  `cpc-renderer.md` Phase R2 / `toolchain.md` Phase T2).
- **B8-3** Add a CPC SUB test game (`games/cpc-sub-test/`)
  mirroring `games/sub_bufs_128`.
- **Phase-exit criteria**:
  - CPC SUB-flow works end-to-end (load → swap → run → return →
    main).
  - ZX SUB games (`games/sub_bufs_48`, `games/sub_bufs_128`) still
    pass.

### Phase B9 — Cleanup and rename

**Goal**: tighten the per-platform discipline and finalise the
documentation pass. Per README §5.6, no renamed surfaces are
removed — old spellings stay accepted indefinitely.

- **B9-1** *(originally "remove the `interrupts_128:` top-level
  alias" — DROPPED per README §5.6.)* The top-level
  `interrupts_128:` alias stays accepted by `etc/rage1-config.yml`
  indefinitely. Documentation pass only: confirm both spellings
  are still recognised by `Makefile.common` and record the rename
  in `CHANGELOG.md` as "old name remains accepted indefinitely".
- **B9-2** Remove hard-coded `@dataset_valid_banks` /
  `@codeset_valid_banks` from `tools/banktool.pl` (deprecated
  since B1-2). The tool now hard-fails if `banking.<platform>` is
  missing from YAML.
- **B9-3** Rename `engine/banked_code/128/` to
  `engine/banked_code/zx128/`. Keep a **permanent silent
  forwarding symlink / Makefile alias** at the old path per
  README §5.6 (no deprecation cycle).
- **B9-4** *(originally "remove `BUILD_FEATURE_ZX_TARGET_*`
  macros" — DROPPED per README §5.6.)* Both
  `BUILD_FEATURE_ZX_TARGET_128` / `BUILD_FEATURE_ZX_TARGET_48`
  AND `BUILD_FEATURE_PLATFORM_*` macros stay emitted in
  `features.h` indefinitely. External games that `#ifdef` on
  the old macros keep building. Documentation pass only: record
  in `CHANGELOG.md` that the canonical macros are the new
  `BUILD_FEATURE_PLATFORM_*` family.
- **B9-5** Update `doc/BANKING-DESIGN.md`, `doc/CODESET-DESIGN.md`,
  `doc/SINGLE-USE-BLOBS.md`, `doc/BANKED-FUNCTIONS.md` to reflect
  the per-platform model. Add cross-links to this document.
- **Phase-exit criteria**:
  - No reference to "zx-only" naming in the banking code path
    that isn't gated by a `BUILD_FEATURE_PLATFORM_ZX*` macro.
  - Both `BUILD_FEATURE_ZX_TARGET_*` and
    `BUILD_FEATURE_PLATFORM_*` macros emitted in `features.h`;
    a smoke build of a `.gdata` that uses the old macros
    still works.
  - `make all-test-builds` green on every supported PLATFORM.
  - Banking docs reflect reality.

---

## 7. Risks

- **R1 — CPC swap window at `0x4000` conflicts with code/data
  placement.**
  *Impact*: Page B (`0x4000–0x7FFF`) is a 16 KB chunk of the
  64 KB CPU address space. On cpc-banked, putting datasets/
  codesets/banked-code there means *no permanent code or data*
  can live in page B. Engine code must fit in page A
  (`0x0000–0x3FFF`, 16 KB) plus page C (`0x8000–0xBFFF`, 16 KB)
  minus the dataset buffer and stack. That's tighter than ZX 128
  (where engine has `0x5B00–0xD1EC` = ~30 KB).
  *Mitigation*: aggressive use of codesets (move all non-core
  engine code into RAM 4 banked code; keep page A for the
  bank-switch primitive + ISR + critical path). Audit lowmem
  symbol list (`Makefile-128:48-57`) and migrate as much as
  possible to banked code. Track engine RAM budget via a CPC
  equivalent of `make mem` (`tools/mem-summary-*.sh` extended).

- **R2 — Dataset destination buffer dilemma on cpc-banked.**
  *Impact*: §3.2 noted that the dataset decompression buffer
  cannot live in the same page as the swap window. The proposed
  destination at `0x8000`-region in page C is **fixed** memory
  that competes with home data + bss. Sizing it correctly is
  not trivial.
  *Mitigation*: `datagen.pl` computes max-dataset-decompressed
  size and emits `BUILD_MAX_DATASET_SIZE_<PLATFORM>` (§5). The
  buffer in `mmap-cpc-banked.inc` is sized accordingly. If the
  buffer needs to grow during execution, hard-fail at build with
  a clear error. The asset overlay model (assets.md §2.4 Tier 2 /
  3) lets authors trim CPC datasets without affecting ZX.

- **R3 — CPC asset bytes are 2-4× the size of ZX bytes
  (§5).**
  *Impact*: Datasets on cpc-banked have effectively half (mode 1)
  or quarter (mode 0) the ZX-equivalent content budget.
  *Mitigation*: default to mode 1 (cpctelera OQ-1). Document
  clearly in `doc/multiplatform-plan/README.md` once it lands.
  The per-platform overlay model lets authors ship austere CPC
  art alongside richer ZX art.

- **R4 — CPC interrupt timing breaks ZX-tuned ISR cadence.**
  *Impact*: ZX runs 50 Hz interrupts; CPC default is 300 Hz raster
  interrupt. RAGE1's `do_timer_tick()`
  (`engine/src/interrupts.c:34-46`) expects 50 Hz.
  *Mitigation*: CPC ISR divides 300 → 50 with a small counter
  (§3.5). Carefully audit other places that assume 50 Hz
  cadence (animation, sound).

- **R5 — cpctelera's `cpct_pageMemory()` doesn't return previous
  state.**
  *Impact*: RAGE1's banking idiom is "save previous, switch, do
  work, restore" — `memory_switch_bank()` returns the previous
  bank (`engine/src/00bswitch.c:82-105`). cpctelera's
  `cpct_pageMemory()` doesn't.
  *Mitigation*: wrap with our own `cpc_memory_switch_bank()` that
  tracks state in `memory_current_memory_bank`, identical pattern
  to the ZX implementation. Cost: 6–8 extra Z80 bytes per
  switch.

- **R6 — cpctelera and z88dk fight over the MMR write byte.**
  *Impact*: cpctelera's `cpct_pageMemory()` writes a value
  composed by OR'ing its argument with `0xC0` (the MMR command
  signature). If z88dk's CRT or its own startup writes to port
  `0x7Fxx` with a different command (e.g. ROM enable), the two
  must not interleave during init.
  *Mitigation*: take over port `0x7Fxx` writes early. The
  asmloader sets MMR config explicitly before `jp main`.
  cpctelera's firmware-disable is called from `gfx_init` (or
  earlier). Coordinate with `cpc-renderer.md` Phase R2.

- **R7 — `tools/loadertool.pl` becomes a per-platform template
  zoo.**
  *Impact*: With 4 platforms each with subtle asmloader
  variations, the template files in `engine/loader-<platform>/`
  are 4 sets of (similar but not identical) Z80 assembly. If a
  bug needs fixing in the SUB-run flow, 4 templates need
  patching.
  *Mitigation*: factor common asmloader fragments into a shared
  `engine/loader-common/` directory; templates `%INCLUDE` them.
  Per-platform templates only carry the platform-specific bits
  (bank-switch stub, LD_BYTES vs AMSDOS load).

- **R8 — Bank-4 collision policy on CPC.**
  *Impact*: ZX 128's `tools/banktool.pl:101-121` reserves bank 4
  for `banked_code.bin` but allows datasets to *also* land in
  bank 4 (it's last in `@dataset_valid_banks`). On CPC the
  bank pool is 4 banks (4/5/6/7), so the engine-code bank (RAM 4)
  competes much more visibly with datasets.
  *Mitigation*: on CPC, the dataset valid-bank order is
  `(5, 6, 7, 4)` — bank 4 last. If banked-code grows large
  enough to consume all of bank 4, datasets can spill into the
  remaining space, mirroring ZX behaviour. The `BANK_MAXSIZE`
  check at `tools/banktool.pl:130-131` is platform-agnostic.

- **R9 — CRT_ORG_CODE on cpc-banked is constrained.**
  *Impact*: §3.1.4 proposes engine code in page A
  (`0x0000–0x3FFF`). z88dk's default `+cpc` CRT_ORG_CODE is
  `0x1200`. Using `0x0040` or `0x0100` deviates significantly.
  *Mitigation*: `zpragma-cpc-banked.inc` (`toolchain.md` T3-2)
  explicitly sets `CRT_ORG_CODE` and matches the asmloader.
  Validate in Phase B7-5 smoke test.

- **R10 — Loadertool refactor breaks per-SUB game Makefiles.**
  *Impact*: Every `games/*/game_src/sub_*/Makefile` calls
  `zcc +zx ... --no-crt`. CPC SUBs need `zcc +cpc ...`. There's
  no central template; each SUB ships its own Makefile. Adding
  CPC support requires per-SUB Makefile updates.
  *Mitigation*: `make new-game` is the standard SUB-creation
  path; it copies a per-SUB Makefile skeleton. Add a
  `--platform=<>` flag to the SUB template; update existing
  test-game SUB Makefiles in Phase B8. External user games are a
  one-time migration; document in CHANGELOG.

- **R11 — Codeset compile-org rewrite forces datagen changes.**
  *Impact*: `datagen.pl` emits codeset source under
  `build/generated/codesets/codeset_N.src/`. The compile rule
  `Makefile-128:94-99` org's at `0xC000` implicitly via
  `zpragma-128.inc`. The same `datagen.pl` output must compile
  at `0x4000` for CPC.
  *Mitigation*: the ORG is set by the per-Makefile-platform's
  `zpragma-*.inc` and `CFLAGS`, not by `datagen.pl`. Verify
  there's no `#pragma output CRT_ORG_CODE=0xC000` baked into
  generated source. If there is, parameterise it via a build var.

- **R12 — IM 2 vs IM 1 mismatch surfaces in shared code.**
  *Impact*: `engine/src/interrupts.c` is shared; the
  `IM2_DEFINE_ISR` macro (`engine/src/interrupts.c:67`) is z88dk
  ZX-specific. On CPC we use IM 1.
  *Mitigation*: gate `IM2_DEFINE_ISR` block on
  `BUILD_FEATURE_PLATFORM_ZX*`; provide a CPC IM 1 setup in
  parallel. Investigate whether z88dk's `+cpc` clib has a
  compatible `IM1_DEFINE_ISR`-style macro, or use raw asm.

- **R13 — Long-term: divergence from z88dk's `#pragma bank`
  banking model.**
  *Impact*: Phase 1 locks in Option A (extend RAGE1's custom
  banking; see OQ-B11). This means RAGE1 maintains its own
  banking pipeline indefinitely while z88dk evolves its
  `#pragma bank` mechanism. Over time, the gap may widen — z88dk
  improvements (better linker bank semantics, additional
  platforms covered out-of-the-box) accrue to projects using
  `#pragma bank` but not to RAGE1. The `__orgit` invariant
  (dataset ORG = destination buffer base, not source bank
  window) is the load-bearing piece that makes a future
  migration non-trivial.
  *Mitigation*: keep CPC banking parametrised the same way ZX
  banking is (per-platform valid-banks lists, per-platform
  loader template, per-platform swap-window primitive). Document
  the `__orgit` invariant explicitly in the implementation so a
  future migration spike can target it. A dedicated future task
  may spike z88dk's `#pragma bank` on a single ZX game,
  validating the `__orgit` workaround, before committing to
  migration. This is **not** Phase 1 work.

---

## 8. Open Questions

- **OQ-B1** ✅ — Dataset destination buffer placement on cpc-banked.
  **RESOLVED (2026-05-26)**: buffer at the **top of Page C**
  (`0x8000-0x9FFF`, 8 KB). Page A alternative considered (buffer
  + engine code share one window, ZX-128-style geometry) but
  rejected for Phase 1 because it constrains Page A engine code to
  ~3.5 KB after the `+cpc` clib's CRT footprint — too tight. The
  alternative is recorded in §3.1.4 as a fallback to revisit if
  Phase B4-1's lowmem measurement reopens it or if home-data
  pressure on Page C forces a swap of constraints.

- **OQ-B2 — Use cpctelera's `cpct_pageMemory()` directly or roll
  our own MMR write?**
  cpctelera's call has a 6-clock overhead vs hand-rolled. Engine
  code path uses `memory_switch_bank()` very frequently
  (every dataset activation, every banked-function call, every
  codeset call). For ZX the function is inline-asm
  (`engine/src/00bswitch.c:82-105`). Recommend doing the same on
  CPC: re-implement the 6-byte MMR write in our own
  `00bswitch_cpc.c`. Cross-check with `cpc-renderer.md` Phase R2.

- **OQ-B3 — Does `loadertool.pl`'s asmloader template live under
  `engine/loader-<platform>/` (per `toolchain.md` 4.3) or in a
  tool-side `tools/loader-templates/` tree?**
  Current location for ZX is `engine/loader{48,128}/` (BASIC
  loader only, no asm template). `toolchain.md` Phase T1-4
  renames to `engine/loader-zx{48,128}/`. The asmloader-as-
  template proposal in §4.2 implies template lives next to
  the BASIC loader, at `engine/loader-<platform>/asmloader.asm.in`.
  Confirm this is the right place.

- **OQ-B4** ✅ — CPC mode 0 in Phase 1. **RESOLVED (2026-05-26)**:
  **mode 1 only** in Phase 1; mode 0 (and mode 2) deferred. Aligns
  with `gfx.md` Q7, `cpc-renderer.md` OQ-1, and README §5.5
  two-layer model (which keeps modes 0/2 open as a future
  backend-internal mode parameter). Banking-side consequence:
  cpc-banked dataset budget is sized against mode 1's 2× byte
  multiplier; mode 0 would halve it.

- **OQ-B5 — Should `dataset_valid_banks_cpc` include bank 4
  at all, or never spill datasets into the engine-code bank?**
  ZX practice: bank 4 is *technically* in the dataset list
  (`(1,3,7,6,4)`) so it can spill if needed. CPC equivalent could
  be (a) `(5,6,7,4)` — same spill policy; or (b) `(5,6,7)` —
  bank 4 strictly reserved for engine code. Recommend (a)
  for symmetry. Confirm during Phase B7-1.

- **OQ-B6 — Cold-boot loader path on CPC: AMSDOS-headed `.cpc`
  one-shot, or per-block firmware loads from disk?**
  AMSDOS `RUN"FILE.CPC"` loads one contiguous blob to a fixed
  address, then `jp`s into it. Per-block disk loads can load
  each bank's payload directly to the swap window. The first is
  simpler but ties our hands on memory layout; the second is
  the natural CDT story but requires firmware-call inside our
  asmloader. Cross-ref `toolchain.md` §4.2 and
  `cpc-renderer.md` Phase R3. Decision in Phase B7-2.

- **OQ-B7 — Should `etc/rage1-config.yml` carry per-platform
  banking config inline, or split into
  `etc/rage1-config-<platform>.yml` files?**
  Inline is simpler. Split is cleaner if the per-platform
  sections grow much larger. Recommend: inline for Phase 1;
  revisit if the file exceeds ~500 lines.

- **OQ-B8 — Bank-ID semantic stability.**
  When a future contributor adds a 5th CPC RAM bank (e.g. for a
  6128-Plus or third-party expansion), how do we extend
  `dataset_banks: [5, 6, 7, 4]` without breaking existing
  `dataset_info.asm` consumers? The current
  `dataset_info.asm` is byte-level baked into main.bin, so
  per-bank rebuild is required anyway. Document: bank-list
  changes are not ABI-stable across game builds.

- **OQ-B9 — Does the SP1-equivalent "high RAM SUB target" on CPC
  collide with cpctelera's library-data area?**
  cpctelera has internal buffers (sprite scratch, palette table,
  etc.) at fixed addresses. Cross-ref `cpc-renderer.md` Phase R2 —
  the PoC must report which addresses cpctelera reserves so the
  CPC SUB-target table can avoid them. Block Phase B8-1 on this.

- **OQ-B10 — MSX placeholder.**
  The per-platform banking model designed here generalises
  cleanly to MSX (Megaram, ASCII8 mapper, KonamiSCC mapper — each
  is a "swap window + bank-id mapping" instance). The 4-page
  CPC-style "multiple windows" abstraction is more general than
  ZX's "single window" model — adopting it now leaves room for a
  later MSX port. C64 is **out of scope** for this project (see
  README §5.7) so the banking model is not required to
  accommodate it. No banking-side disqualification for MSX.

- **OQ-B11** ✅ — Banking mechanism: extend RAGE1's custom
  implementation vs migrate to z88dk's `#pragma bank`.
  **RESOLVED (2026-05-26)**: **extend RAGE1's existing custom
  banking** to CPC (Option A). Migrating to z88dk's `#pragma
  bank NN` (Option B) is a separate, larger refactor and is
  deferred to a future task. Rationale:

  - RAGE1's banking pipeline (`banktool.pl` page-policy lists,
    `loadertool.pl`-emitted asmloader, `--no-crt --org
    <buffer_address>` dataset compilation = the "__orgit trick")
    is battle-tested on ZX 128 and stable. A migration is a
    high-risk refactor that touches every existing game and
    perturbs the "ZX byte-identical at phase boundaries"
    invariant.
  - CPC extension under Option A is mostly mechanical: extend
    `banktool.pl` with `--platform` and the cpc-banked
    valid-banks list `(5,6,7,4)`; teach `loadertool.pl` a
    `--platform=cpc-banked` template (already in scope per
    toolchain.md T1-11); wrap MMR-config selection in
    `cpc_memory_switch_bank()`. No engine-side rethink.
  - The `__orgit` invariant (dataset ORG = destination buffer
    address, not source window) is RAGE1-specific and not
    obvious to express under z88dk's `#pragma bank`, which
    typically assumes ORG = swap window. Re-deriving the
    invariant on top of z88dk's linker is non-trivial and
    would warrant a dedicated spike.
  - Long-term: a future task may revisit Option B as a
    standalone migration project, with its own PoC validating
    the `__orgit` workaround on a single ZX game before
    generalising. Captured as a Risk entry (see §6) for
    visibility. This decision also resolves
    [`toolchain.md` OQ-T11](toolchain.md) to "Option A;
    toolchain.md stays neutral, banking.md owns the design".

---

*End of banking.md.*

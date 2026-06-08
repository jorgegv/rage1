# Phase 4 remaining — cpc-banked bring-up (B6 / B7 / T3) — execution tracker

> **Status (2026-06-08): ALL decisions DC1–DC7 RESOLVED — bring-up is UNBLOCKED;
> ready to implement Stage T3a (Makefile-cpc-banked / zpragma / mmap), built
> SHAPE-PARAMETRIC to experiment with the two memory-map partitions (DC3-D: Shape A
> = buffer in page C; Shape B = full-page-A buffer, code in page C).** Page-A/C fit,
> CRT_ORG_CODE floor, and the shape choice are measure-and-iterate items during
> implementation, not pre-decisions. This is an
> *execution* tracker that turns the approved design in
> [../banking.md §6 (B6/B7)](../banking.md) and
> [../toolchain.md §Phase T3](../toolchain.md) into a gated step sequence, and
> extracts the **open decisions that must be resolved before/while writing code**.
> No engine code has been written yet (branch `cpc_banked_bringup` created off
> `refactor_for_multiplatform`). cpc-banked = the CPC 6128 banked (ext-RAM) target;
> `PLATFORM=cpc6128` → `Makefile-cpc-banked`.

## Why this is gated, not big-banged

B6/B7/T3 touch the **most delicate part of the engine** (bank-switch primitive,
the IM1/300→50 Hz ISR, dataset/codeset/banked-code infra) for a **new platform**,
and the cpc-banked **memory map still has TBDs** that only a real build can
resolve (banking.md §3.1.4: *"whether the lowmem engine code fits is TBD at Phase
B6"*; the page-A code budget is called "optimistic"; R1/R2 risks). Phase-exit for
each phase requires **cap32 emulator validation**. Per the project's rules (no
big-bang untested rewrites; incremental gated steps; design tests early;
independent review per step), this must be built in small, individually-verified
increments — not in one unsupervised pass.

## Open decisions — NEED USER SIGN-OFF before the corresponding step

These are the points where `banking.md` leaves a choice or a TBD. Resolving them
unblocks the steps in the next section.

- **DC1 — Bank-switch source of truth.** ✅ **RESOLVED (user, 2026-06-08): direct
  ~6-byte Gate-Array MMR write** (no cpctelera link dependency on the banked path;
  mirrors the hand-translated CPC HW-I/O already used for keyboard/mode). B6-1 maps
  `bank ∈ {4,5,6,7}` → **MMR Configs 4..7** at the `0x4000` window via a direct `out`.
  **CORRECTION to banking.md** (which says "Configs 3..7"): Config **3** remaps
  `0xC000` to RAM7 and would corrupt the screen bank — the usable set is Configs
  **4,5,6,7** → RAM 4,5,6,7, which keep RAM0@0x0000 / RAM2@0x8000 / RAM3@0xC000 fixed.
- **DC2 — One API vs split.** ✅ **RESOLVED (user, 2026-06-08): single
  `memory_switch_bank(bank)`** with an internal per-platform mapping table
  (banking.md B6-2 (a)).
- **DC3 — cpc-banked memory map (the big one).** ✅ **RESOLVED (user, 2026-06-08)
  — all sub-parts settled below; bring-up is now UNBLOCKED.** Swap window forced to
  `0x4000` (because `0xC000`=screen). **Two candidate partitions of the always-mapped
  32 KB pool — Shape A (below) and Shape B — to be chosen by experiment, see DC3-D.**
  Concrete map for **Shape A** (all 8 banks used):
  ```
  RAM0  page A  0x0000–0x3FFF  resident code: vectors/ISR@0x0038; asm bswitch+ISR+
                               dispatcher @0x0040–0x11FF; engine C @0x1200–0x3FFF (~11.5K)
  RAM1  page B  0x4000–0x7FFF  Config-0 home: 0x4000–~0x57FF secondary/free;
                               ~0x5800–0x7FFF JSP data block (~10K, CPC tables) [DC7]
                Config 4–7    RAM4–7 paged over the whole window = compressed
                               dataset/codeset/banked-code source (RAM1 hidden during
                               swap, restored on return to Config 0; §3.5.1 interlock)
  RAM2  page C  0x8000–0xBFFF  resident: 0x8000..+MAXDS dataset decompress buffer
                               (=dataset ORG §3.2); above it home data+bss; stack top-down
  RAM3  page D  0xC000–0xFFFF  SCREEN (CRTC) — no code/data
  RAM4 = engine banked code | RAM5/6/7 = datasets/codesets
  ```
  Constants: `swap_window=0x4000`, `BANKED_FUNCTION_TABLE_BASE=0x4000`,
  `CODESET_ASSETS_BASE=0x4000`, `BANKED_DATASET_BASE_ADDRESS=0x8000`, banks `{4,5,6,7}`
  via Configs 4–7. `CRT_ORG_CODE` = **tunable** (see below), start at `0x1200`.

  ✅ **DC3-C RESOLVED (user, 2026-06-08):** page-C layout as above (buffer@0x8000 forced
  by §3.2; home data/bss above; stack `≈0xBF00` down per cpc-flat; hard-fail if >16 KB).

  ✅ **DC3-A RESOLVED (user, 2026-06-08): measure-and-iterate.** Mirror the ZX128
  lowmem/banked split into `engine/banked_code/cpc-banked/` as the START, build, measure
  page-A usage, offload more `lowmem→banked/codeset` if over budget. Plus two refinements:
  - **JSP render/composite code lives in the page-B HOME bank (RAM 1)**, co-located with
    the JSP buffers, called via plain `CALL` from page-A (NOT via the RAM-4 dispatcher).
    HARD CONSTRAINT: JSP code must never be in the banked RAM-4 set (else its buffers in
    RAM 1 are paged out when RAM4/5-7 map into page B). Valid homes = page A (RAM0) or
    page-B home (RAM1); RAM1 chosen to spare the scarce page-A budget. Fit: JSP code
    (~6 KB budget, measure) + ~10 KB buffers ≤ 16 KB RAM1; fallback = JSP code resident
    in page A, buffers stay RAM1.
  - **`CRT_ORG_CODE` is a TUNABLE, not fixed.** Verified (cpc-hello map): nothing but CRT
    *constants* live below `0x1200`; our code section starts at `0x1200`, so the
    `0x0040–0x11FF` gap (~4 KB) is z88dk `cpc_crt0`'s conservative default and is
    reclaimable. Start at `0x1200` for a working build, then lower `CRT_ORG_CODE` toward
    just above the resident asm and VALIDATE each drop on cap32 (still `RUN"`-loads + runs)
    — reclaims up to ~4 KB of page-A budget. (Confirm z88dk's reason for 0x1200 in
    `cpc_crt0.asm`: lower-ROM overlay / AMSDOS load workspace / firmware-off.)

  **Embedded TBD (now an implementation measure-item, NOT a blocker):** does resident
  engine C fit page A after the above? Only knowable post-first-build; valves = lower
  CRT_ORG_CODE + push more code to codesets + JSP in RAM1.

  🔬 **DC3-D — buffer-page choice: Shape A vs Shape B (user, 2026-06-08): RECORD BOTH,
  decide by EXPERIMENT.** KEY INSIGHT: pages A (RAM0) and C (RAM2) are BOTH always-mapped
  across Configs 0/4/5/6/7 (only page B swaps), so the always-resident pool is a single
  **32 KB** shared by {resident code, home data, bss, stack, dataset buffer}; a "shape"
  just partitions it, with the dataset buffer as the big movable block.
  - **Shape A** (above): buffer in page C → competes with data+stack → `MAXDS≈10 KB`;
    code fills page A. `BANKED_DATASET_BASE_ADDRESS=0x8000`, `CRT_ORG_CODE≈0x1200`.
  - **Shape B**: buffer FILLS page A (`0x0040–0x3FFF`, ~15.9 KB) → `MAXDS≈16 KB`; ALL
    resident code + home data + stack move to page C. `BANKED_DATASET_BASE_ADDRESS=0x0040`,
    `CRT_ORG_CODE=0x8000`. Bigger buffer ⇒ bigger datasets ⇒ more ZX0 compression + dedup,
    which matters because CPC assets are 2–4× ZX. B wins whenever resident code < a full
    page (likely, since much is banked + JSP in RAM1). Vectors `0x0000–0x003F` preserved
    (buffer starts `0x0040`); ISR/bswitch/dispatcher go to page C (RAM2 = always mapped).
    Decompress still works (Configs 4–7 map RAM0 dest + page-B source + RAM2 code at once).
  - **B's risk** (mirror of A's): all resident code+data+stack must fit page C's 16 KB.
  - **Decision = empirical.** Constants are externalised (YAML + mmap/zpragma), so a shape
    is just an address set → Stage T3a is built **shape-parametric**; measure resident-code
    size, max viable MAXDS, and real asset fit on a CPC game, then choose (B is the likely
    default for asset-heavy games). NEEDS: verify z88dk `+cpc` accepts `CRT_ORG_CODE=0x8000`
    + AMSDOS `RUN"` load at that org. NOT a blocker — it's an early implementation experiment.
- **DC4 — Dataset decompression buffer placement/size.** ✅ **RESOLVED (user,
  2026-06-08): as designed** — buffer sized from datagen's `BUILD_MAX_DATASET_SIZE_CPC6128`;
  hard-fail at build if oversized. Buffer PAGE (C vs A) per DC3-D experiment.
- **DC5 — SUB / SP1-equivalent buffer defaults on cpc-banked.** ✅ **RESOLVED
  (user, 2026-06-08): use the JSP buffers** (the CPC analogue of ZX's "DSBUF =
  SP1's buffer"). Caveat: **JSP buffers are MUCH smaller than SP1's**, so the
  SUB-load / scratch budget on cpc-banked is tight — size SUB targets against the
  actual JSP buffer size and hard-fail if a SUB overflows it. Detailed sizing lands
  with B7-4 / Phase B8 (B7 smoke game ships with no SUBs).
- **DC6 — pure-asmloader entry vs BASIC loader / disc autoboot.** ✅ **RESOLVED
  (user, 2026-06-08): option 1 — AMSDOS `RUN"FILE` entry, pure asmloader, no BASIC
  tokeniser; reuse the cpc-flat `zcc -create-app -subtype=dsk` packaging.** User asked: *is there a CPC option to autoload a file on
  start?* Findings: **stock CPC 464/664/6128 has NO power-on floppy autoboot** for
  AMSDOS/BASIC data discs (only ROM cartridges / CPC+ auto-run). The universal
  mechanism is the **AMSDOS binary `RUN"FILE`** — the 128-byte AMSDOS header carries
  load+entry addresses, so one command loads+executes; emulators auto-issue it
  (cpc-flat ALREADY does this: `tools/cap32-shot.sh:68` → `cap32 -a 'run"NAME.'`).
  The ONLY true zero-keystroke autoboot is a **CP/M system-format disc with a boot
  sector** (`|CPM`), which is heavyweight (CP/M disc format + boot-sector loader) and
  still not power-on-automatic from cold BASIC. *Recommendation: pure asmloader as
  the AMSDOS binary entry, launched via `RUN"FILE` (no BASIC tokeniser; reuse the
  proven cpc-flat `zcc -create-app -subtype=dsk` packaging). Adopt CP/M boot-sector
  only if end-user zero-keystroke boot becomes a hard requirement.* **Confirm.**
- **DC7 — JSP sprite-buffer placement on cpc-banked.** ✅ **RESOLVED (user,
  2026-06-08): JSP data block at the TOP of the `0x4000` window, in the page-B home
  bank RAM 1** (mirrors ZX's default `JSPDATA_SLOT3` = `0xE840–0xFFFF`, top of the
  `0xC000` window). *Verified (jsp_data.c):* the JSP block is placed at FIXED `__at`
  addresses via a per-target `#ifdef` — ZX `JSPDATA_SLOT3` (default) `0xE840–0xFFFF`,
  ZX `JSPDATA_SLOT2` `0xA840–0xBFFF`, and **`JSP_TARGET_CPC` (cpc-flat) `0x9800–0xBFFF`
  (~10 KB, packed just below the `0xC000` screen)**: BAT `0x9800`, FTT `0xA000`, DTT
  `0xA100`, BTT `0xA200`, ROTTBL `0xB200`. So the **small JSP refactor** is just a NEW
  `#ifdef` arm (CPC + banked) shifting those five addresses to the top of the `0x4000`
  window → block ≈ `0x5800–0x7FFF` in RAM 1. Leaving it at `0x9800–0xBFFF` on
  cpc-banked would eat ~10 KB of the squeezed page C — moving it to RAM 1 is what
  makes the page-C budget viable.
  *Benefits:* reclaims RAM 1 (otherwise the unused Config-0 page-B bank) and relieves
  the page-C squeeze. *Implication:* the block is hidden during swaps (same as ZX
  SLOT3) → honour the §3.5.1 Config-0-restore/ISR interlock before any JSP access;
  no capacity loss (a paged-in bank still exposes its full 16 KB from a different
  physical bank). New work item in B6: the JSP placement refactor.

## Gated step sequence (each step: build green + ZX byte-identical + cap32 check
where runnable + independent review for non-trivial/asm; commit per step)

**Stage T3a — make a cpc-banked build EXIST (skeleton, before engine infra):**
1. T3-1/T3-2 — `Makefile-cpc-banked` (model on `Makefile-zx128`; `ZCC_TARGET=+cpc`)
   + `zpragma-cpc-banked.inc` (org/stack per DC3). *Gate: a trivial cpc6128 build
   links; `.map` sections in expected regions.*
2. T3-3/B6-6 — `mmap-cpc-banked.inc` (DC3 numbers). *Gate: section-check passes.*
3. T3-8 + platform plumbing — `build-cpc6128` top target + `build-cpc` alias;
   `PLATFORM=cpc6128`→cpc-banked mapping in `tools/detect-platform.sh` + Makefile
   resolver; `datagen -p cpc6128` (T3-7) emits `BUILD_FEATURE_PLATFORM_CPC_BANKED`
   (+ keep legacy macros). *Gate: `make build-cpc6128 target_game=games/cpc-hello`
   reuses cpc-flat path enough to link a no-banking hello; ZX byte-identical.*

**Stage B6 — engine banking infra (no data flowing yet):**
4. B6-3/B6-4 — per-platform `BANKED_FUNCTION_TABLE_BASE` / `CODESET_ASSETS_BASE` /
   `BANKED_DATASET_BASE_ADDRESS` macros from YAML (DC3); make `00lowmem.c`,
   `codeset.c`, `dataset.c` compile under `BUILD_FEATURE_PLATFORM_CPC_BANKED`.
5. B6-1/B6-2 — bank-switch primitive (DC1/DC2): `memory_switch_bank()` CPC arm
   (DI/out/EI atomic), bank→Config table, `memory_current_memory_bank` state.
6. B6-8 — CPC IM1 + `0x0038` ISR + 300→50 Hz divide-by-six on cpc-banked
   (`interrupts_cpc.c` or `#ifdef`); ISR + bswitch primitive in page A.
7. B6-5/B6-7 — `engine/banked_code/cpc-banked/` dir mirroring `128/`;
   `BANKED_CODE_DIR_<tag>` set by `Makefile-cpc-banked`.
   *Stage gate (B6 exit): engine compiles under cpc-banked with banking on;
   `games/cpc-bswitch-test` toggles MMR configs and runs on cap32; ZX byte-identical.*

**Stage B7 — tooling + real bank binaries + asmloader:**
8. B7-1/T3-5 — `banktool.pl --platform` + `banking.cpc-banked` bank lists from
   YAML; reserve RAM 4 for engine code; dataset ORG `0x8000` (DC3/§3.2).
9. B7-2/B7-3/T3-4/T3-6 — `engine/loader-cpc-banked/asmloader.asm.in` template
   (load bank→swap window after MMR config, ZX0-decompress datasets, reset to
   Config 0, `jp MAIN`) + `loadertool.pl --platform=cpc-banked` template substitution;
   lift loader-org literals into YAML (DC6 = pure asmloader entry).
10. B7-5/T3-9 — `games/cpc-banked-test/` (1 dataset, 1 codeset, no SUBs) +
    `games/cpc-hello-banked/`. *Stage gate (B7/T3 exit):
    `make build-cpc6128 target_game=games/cpc-banked-test` → runnable `.dsk`;
    asmloader bank-switches correctly; engine reads right bytes from swap window
    (cap32 visual); ZX byte-identical; games added to the all-test-builds matrix.*

(SUBs on cpc-banked = Phase B8, out of this Phase-4 chunk; B7 smoke game has none.)

## Steps safe to start WITHOUT the decisions (can be done now, ZX-byte-safe)

- Stage T3a step 1–2 scaffolding (Makefile-cpc-banked / zpragma / mmap) can be
  *drafted* but their constants depend on DC3 — better to wait for DC3 sign-off to
  avoid churn.
- The backward-compatible `--platform` flag plumbing on `banktool.pl` /
  `loadertool.pl` (default = current zx128 behavior) and `datagen -p cpc6128`
  macro emission are the only genuinely decision-independent, ZX-byte-identical
  prep steps. Low value alone (untested until the CPC build exists), so deferred
  to execute alongside their stage rather than as orphan commits.

## Test games to add (regression matrix auto-discovers them; cpc6128 platform)

- `games/cpc-hello-banked/` — links, boots, prints (T3-9). ✅ ADDED (T3a).
- `games/cpc-bswitch-test/` — toggles MMR configs, exits (B6 validation). ✅ ADDED
  (B6 step 5): stamps a marker into each expansion bank {4,5,6,7} via the 0x4000
  window and reads them back; links only 00bswitch.c (CPC_LINK_BSWITCH=1). Ran
  **PASS on cap32** (128K 6128) — empirical proof of the GA RAM-config select;
  evidence at `games/cpc-bswitch-test/cap32-pass.png`. Also a build-only matrix game.
- `games/cpc-isr-test/` — CPC IM1 ISR + 300→50 Hz divide validation. ✅ ADDED
  (B6 step 6): init_interrupts() then current_time advances (ticks 0→86, secs 0→1).
  Ran **PASS on cap32** — empirical proof the IM1 path ticks on cpc-banked; links
  interrupts.c + asmdata_cpc.c (CPC_LINK_ISR=1). Evidence
  `games/cpc-isr-test/cap32-pass.png`. Also a build-only matrix game.
- `games/00cpc-banked-compile-test/` — whole-engine cpc-banked compile-test. ✅ ADDED
  (B6 step 4); auto-joins the matrix via the `00cpc%` filter.
- `games/cpc-banked-test/` — 1 dataset + 1 codeset, observe swap (B7 validation).

## Risk register (from banking.md §7, live)

- R1 — swap window `0x4000` ⇒ no permanent code/data in page B; engine must fit
  page A + page C minus buffers. **Measure after Stage T3a/B6 step 4.**
- R2 — dataset buffer placement/size dilemma (DC4).
- R3 — CPC asset bytes 2–4× ZX ⇒ tighter dataset budget (mode-1 default).
- R-T3 — no headless Locomotive BASIC tokeniser ⇒ DC6 pure-asmloader entry.

## Follow-ups surfaced (durable record — do not rely on session memory)

- **Memory-report scripts need a CPC extension.** `tools/mem-summary-*.sh`,
  `tools/dsinfo.sh`, `tools/r1size.sh` currently hardcode the literal `build/` path
  AND the ZX memory layout. When extended to cover CPC (and especially cpc-banked),
  they MUST account for: (a) the per-target JSP fixed buffer regions (DC7 — ZX
  `JSPDATA_SLOT3` `0xE840–0xFFFF`, cpc-flat `JSP_TARGET_CPC` `0x9800–0xBFFF`,
  cpc-banked top-of-`0x4000` in RAM 1); and (b) the cpc-banked page map for the
  CHOSEN shape (DC3-D) — Shape A (dataset buffer in page C `0x8000`, code in page A,
  `CRT_ORG_CODE≈0x1200`) vs Shape B (buffer fills page A `0x0040`, all resident
  code+data+stack in page C, `CRT_ORG_CODE=0x8000`). The buffer page and code page
  differ between the shapes. `banking.md` §7 R1 also calls for a CPC `make mem`
  equivalent to track the resident RAM budget. (Recorded here so the repo, not just
  session memory, carries it; matches the auto-memory `cpc-jsp-buffer-memmap`.)
- **JSP cpc-banked placement refactor** (DC7): add a CPC+banked `#ifdef` arm in
  `external/jsp/lib/jsp_data.c` pinning BAT/FTT/DTT/BTT/ROTTBL to the top of the
  `0x4000` window (≈`0x5800–0x7FFF`); land it alongside B6 (the JSP-in-RAM1 decision).
- **z88dk `+cpc` org checks** (DC3-D / DC3): verify `+cpc` accepts `CRT_ORG_CODE=0x8000`
  (Shape B) and that AMSDOS `RUN"` loads at that org; and confirm `cpc_crt0.asm`'s
  reason for the `0x1200` default before lowering it (lower-ROM overlay / AMSDOS
  workspace / firmware-off).
- **Banked-function ASM-table dir is hardcoded `…/banked/128/`** (B6 step-4 review NIT):
  `build.banked_functions.asm_table_filename` in `etc/rage1-config.yml` is the literal
  `build/generated/banked/128/00banked_function_table.asm`, so a cpc-banked build writes
  its table (correct `org 0x4000`) into a ZX-named `128` dir. Harmless until B7 (the ASM
  is generated but not compiled/linked at B6 step 4); make it platform-aware (per-platform
  `BANKED_CODE_DIR_<tag>`) when the cpc-banked bank binaries are actually built (B7 / step 8).
- **Decouple `interrupts.c` from the gfx/SP1 header chain** (B6 step-6 review NIT):
  `engine/src/interrupts.c` includes `rage1/debug.h` → `gfx.h` → `gfx_sp1.h`, whose
  `<games/sp1.h>` include is ZX-only, so compiling the interrupt path on CPC requires
  selecting a non-SP1 gfx backend (cpc-isr-test sets `GFX_BACKEND JSP` as a workaround).
  A file that does no graphics should not transitively require a gfx backend choice;
  decouple `debug.h` from `gfx.h` (or make `gfx_sp1.h` self-guard its SP1-lib include).
  Low priority / layering hygiene.
- **Widen the banking-RUNTIME `BUILD_FEATURE_ZX_TARGET_128` guards for cpc-banked**
  (B6 step-4 review MINOR): step 4 made the banking *consumer* files compile, but several
  runtime call sites are still gated on the legacy `ZX_TARGET_128` (which cpc-banked does
  NOT define), so a built cpc-banked game would skip them: `engine/src/banked.c:12`
  (`init_banked_code()` body), `engine/src/main.c:45/57` (`init_banked_code()` +
  `audio_sfx_beeper_init()` calls), `engine/src/map.c:171` (`dataset_activate()` on screen
  entry). Widen these to the canonical banked-platform predicate
  (`PLATFORM_ZX128 || PLATFORM_CPC_BANKED`, the B5-4 pattern) as part of the B6 step that
  brings the engine LOOP up on cpc-banked (after the bank-switch primitive lands). Audit for
  any other `ZX_TARGET_128`-gated banking runtime while doing so.

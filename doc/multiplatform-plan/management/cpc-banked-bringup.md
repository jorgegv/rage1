# Phase 4 remaining — cpc-banked bring-up (B6 / B7 / T3) — execution tracker

> **Status (2026-06-08): DC1/DC2/DC4/DC5/DC6/DC7 RESOLVED; DC3 (memory map) IN
> DISCUSSION — shape + constants + JSP placement settled; page-C layout/stack
> (DC3-C) and the page-A code-banking strategy (DC3-A) still to confirm. DC3 is the
> sole blocker for T3a/B6 code.** This is an
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
- **DC3 — cpc-banked memory map (the big one).** 🔶 **IN DISCUSSION (user,
  2026-06-08). CENTRAL BLOCKER for all T3a/B6 code.** Shape A confirmed in shape
  (swap window forced to `0x4000` because `0xC000`=screen). Concrete proposed map
  (all 8 banks used):
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
  `CODESET_ASSETS_BASE=0x4000`, `BANKED_DATASET_BASE_ADDRESS=0x8000`,
  `CRT_ORG_CODE=0x1200`, banks `{4,5,6,7}` via Configs 4–7.
  **Still to settle:** (a) page-C layout order + stack top (DC3-C); (b) code-banking
  strategy for the page-A fit — mirror ZX128 lowmem/banked split, measure, offload to
  codesets (DC3-A, measure-and-iterate). **Embedded TBD:** does resident engine C fit
  ~11.5 KB page A? (only knowable after first build; fallback = push more to codesets).
- **DC4 — Dataset decompression buffer placement/size.** ✅ **RESOLVED (user,
  2026-06-08): as designed** — buffer in page C (`0x8000` region), sized from
  datagen's `BUILD_MAX_DATASET_SIZE_CPC6128`; hard-fail at build if oversized.
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

- `games/cpc-hello-banked/` — links, boots, prints (T3-9).
- `games/cpc-bswitch-test/` — toggles MMR configs, exits (B6 validation).
- `games/cpc-banked-test/` — 1 dataset + 1 codeset, observe swap (B7 validation).

## Risk register (from banking.md §7, live)

- R1 — swap window `0x4000` ⇒ no permanent code/data in page B; engine must fit
  page A + page C minus buffers. **Measure after Stage T3a/B6 step 4.**
- R2 — dataset buffer placement/size dilemma (DC4).
- R3 — CPC asset bytes 2–4× ZX ⇒ tighter dataset budget (mode-1 default).
- R-T3 — no headless Locomotive BASIC tokeniser ⇒ DC6 pure-asmloader entry.

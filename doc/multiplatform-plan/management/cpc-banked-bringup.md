# Phase 4 remaining — cpc-banked bring-up (B6 / B7 / T3) — execution tracker

> **Status: READY TO START, blocked on user decisions (2026-06-08).** This is an
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

- **DC1 — Bank-switch source of truth.** B6-1: wrap `cpct_pageMemory()` vs. emit a
  direct ~6-byte Gate-Array MMR write (banking.md ~515 notes the latter). Map
  `bank ∈ {4,5,6,7}` → MMR Configs 3..7 at the `0x4000` window. *Recommendation:
  direct MMR write (no cpctelera link dependency on the banked path, mirrors the
  hand-translated CPC HW-I/O approach already used for keyboard/mode).* **Decide.**
- **DC2 — One API vs split.** B6-2: single `memory_switch_bank(bank)` with an
  internal per-platform mapping table (recommended) vs `_zx`/`_cpc` variants.
  *Recommendation: single API (banking.md B6-2 (a)).* **Confirm.**
- **DC3 — cpc-banked memory map numbers (the big one).** Adopt Shape A as-is
  (swap window `0x4000` via Configs 3..7; engine code in page A `0x0000–0x3FFF`;
  home data page C `0x8000–0xBFFF`; screen `0xC000`; extended banks RAM 4..7)?
  And fix the concrete constants for `etc/rage1-config.yml`:
  `BANKED_FUNCTION_TABLE_BASE=0x4000`, `BANKED_DATASET_BASE_ADDRESS=0x8000`
  (= dataset compile ORG, §3.2 invariant), `CODESET_ASSETS_BASE=0x4000`,
  swap_window `0x4000`, `CRT_ORG_CODE` (z88dk +cpc default `0x1200`), valid
  extended banks `{4,5,6,7}`. **The TBD inside DC3:** does the lowmem engine C
  fit the ~15.5 KB page-A budget? This can only be measured after T3-1/B6-6 give
  us a build; the fallback (buffer-in-page-A / migrate more code to codesets) is
  pre-authorised if it doesn't. *Recommendation: adopt Shape A + these constants;
  treat the fit as a measure-and-iterate item, not a pre-decision.* **Decide
  Shape A + constants.**
- **DC4 — Dataset decompression buffer placement/size.** Per R2: buffer lives in
  page C (`0x8000` region), sized from datagen's
  `BUILD_MAX_DATASET_SIZE_CPC6128`; hard-fail at build if oversized.
  *Recommendation: as designed.* **Confirm.**
- **DC5 — SUB / SP1-equivalent buffer defaults on cpc-banked** (B7-4/B8): JSP has
  no SP1 DSBUF; where do SUB load slot + scratch live? *Likely page B
  (`0x4000`, Config 0) per banking.md §3.1.4.* **Confirm or defer SUBs to B8** (B7
  can ship with "no SUBs" smoke game; SUB support is Phase B8 anyway).
- **DC6 — Locomotive BASIC loader vs pure-asmloader entry** (T3-4, risk R-T3): no
  reliable headless BASIC tokeniser. *Recommendation: AMSDOS `RUN"FILE.CPC"` →
  pure asmloader entry (same single-step `zcc -create-app -subtype=dsk` path that
  cpc-flat proved), no BASIC tokeniser dependency.* **Decide.**

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

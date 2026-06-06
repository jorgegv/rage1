# RAGE1 cross-platform — task execution status

Top-level execution status for the 56 subsystem phases that make
up the cross-platform plan. Tasks are grouped under the six
top-level phases defined in [../README.md §4](../README.md). One
line per phase that appears in [gantt.md](gantt.md).

## Editing policy

This file's **only mutable content is the checkbox state**
(`[ ]` ↔ `[x]`). Task descriptions, IDs, indentation, and ordering
are stable and must NOT be edited as part of execution work. They
only change when the underlying tasks themselves are added /
removed / renamed in the per-subsystem docs and Gantt chart — those
changes ripple in *from* the canonical docs, never *from* this file.

If a phase is split, removed, or renamed in its per-subsystem doc:
update [gantt.md](gantt.md) first, then mirror the change here.

A top-level phase ticks complete only when every nested phase
under it is ticked complete.

Tasks that are in-progress should be ticked with [~] as soon as they are started.

## Status

- [x] **Phase 1 — Foundation (no CPC code; pure preparation)**
  - [x] TS1 — backfill ZX regression baselines (≥80 % of test games)
  - [x] T0 — toolchain spike: prove z88dk `+cpc` + sdcc_iy + a tiny cpctelera build outside RAGE1
  - [x] B1 — banking-config externalisation into `etc/rage1-config.yml` (ZX byte-identical)
  - [x] G1 — `gfx_*` audit completion & baseline pin

- [x] **Phase 2 — HAL & asset-pipeline scaffolding (ZX-only, additive)**
  - [x] G2 — `SPRITE_ENGINE` → `GFX_BACKEND` mechanical rename
  - [x] A1 — introduce `PLATFORM` directive (`zx48`, `zx128` only)
  - [x] A2 — sibling-tree overlay copy in `make config` (mechanism only; no overlay files yet)
  - [x] T1 — `PLATFORM` axis throughout the Makefile family; ZX-only
  - [x] B2 — per-platform ISR / codeset YAML split
  - [x] IN1 — input audit
  - [x] IN2 — input HAL skeleton (alias-only, ZX-only)
  - [x] AU1 — audio audit
  - [x] AU2 — audio HAL aliases
  - [x] R1 — cpctelera submodule add (vendored as reference; never compiled)

- [x] **Phase 3 — HAL generalisation (ZX byte-identical)**
  - [x] G3 — attribute abstraction
  - [x] G4 — pixel coords widening
  - [x] G5 — sprite geometry abstraction
  - [x] G6 — tile-ID abstraction
  - [x] A3 — per-platform dispatch seam in `datagen.pl`
  - [x] A4 — overlay precedence proven end-to-end on ZX
  - [x] B3 — parameterise lowmem threshold checks
  - [x] IN3 — engine ↔ HAL migration
  - [x] IN4 — per-game `kbd.c` consolidation
  - [x] AU3 — migrate to `audio_*` names (legacy stays as permanent silent aliases per README §5.6)

- [ ] **Phase 4 — CPC bring-up (cpc-flat first, then cpc-banked)**
  > **2026-06-05 (README §5.13):** the cpctelera-tagged tasks below
  > (R2/R3/R4/A5/G7/G8/G8a) were executed and produced the **interim
  > `gfx_cpctel`** backend (cell-granular). cpctelera is revoked; the CPC
  > graphics engine is now **JSP** — see the new "Phase 4J" below. The
  > interim backend stays green until JSP-CPC reaches parity, then is
  > removed (R10).
  - [x] R2 — cpctelera + z88dk hello-world PoC (gating test) *(interim; superseded by JSP)*
  - [x] R3 — `cpct_img2tileset` asset-converter wiring *(interim; superseded by A8)*
  - [x] T2 — cpc-flat Makefile; first `.cpc`/`.cdt` build
  - [x] B4 — CPC banking config seam (cpc-flat = no banking)
  - [x] B5 — cpc-flat banking materialised
  - [x] G7 — `gfx_cpctel.c` stub skeleton *(interim; superseded by G10)*
  - [x] IN5 — input CPC skeleton (stub)
  - [x] AU4 — audio CPC skeleton + AT2 player relocation
  - [x] A5 — `datagen.pl` invokes `cpct_img2tileset` for CPC assets *(interim; superseded by A8)*
  - [x] TS2 — Caprice32 + Xvfb in dev env + Docker
  - [x] R4 — real `gfx_cpctel.c` + `games/minimal_cpc/` *(interim; superseded by G10/R9)*
  - [x] G8 — real CPC backend wiring *(interim; superseded by G10)*
  - [x] G8a — CPC 16-bit sprite/position coords + `gfx_cpctel` bounds clamp (no-debt task, surfaced by G8 review — see README §5.12)
  - [x] IN6 — real CPC input via hand-translated CPC keyboard scan (`engine/src/cpc/cpct_keyboard.asm`; no cpctelera library dep — README §5.13)
  - [x] AU5 — real CPC audio via AT2 AKG generic player
  - [x] TS3 — first CPC regression baseline *(cpctel; rebaselined for JSP at R9/G10)*
  - [ ] B6 — cpc-banked banking infrastructure
  - [ ] B7 — cpc-banked banking tooling
  - [ ] T3 — cpc-banked Makefile; first banked `.dsk` build

- [ ] **Phase 4J — CPC graphics engine: switch to JSP (cpctelera revoked; README §5.13)**
  - [x] R6 — JSP `+cpc` build integration into RAGE1 (Makefile.common CPC arm; JSP CPC flags; proven: JSP-CPC compiles+links under RAGE1 z88dk flags → bootable .dsk) — replaces R1/R2
  - [x] G10 — JSP CPC backend: `gfx_jsp` CPC platform sections (mode/palette in `gfx_init`; 16-bit coords; 40x25) + cpc-flat link wiring. ZX + cpctel-CPC builds verified green. Full game build pending A8 assets — replaces G7/G8
  - [~] A8 — JSP CPC asset pipeline. **Approach changed (Task 5; README §5.1 reversed):** in-datagen pluggable asset backends (ZX first, byte-identical; CPC Mode-1 backend copied/adapted from cpcgfx.pl into `lib/RAGE/`, byte-compat tested). NOT a subprocess/PNG-bridge. — replaces A5
  - [x] R9 — migrate `games/minimal_cpc` to `GFX_BACKEND=jsp`; converge on `games/minimal` + reuse assets (README §5.13b); prove 1 px movement; rebaseline TS3
  - [~] R10 — retire `gfx_cpctel` backend + remove `external/cpctelera` submodule (keep `engine/src/cpc/` HW-I/O asm with cpctelera credit intact)

- [ ] **Phase 5 — Hardening + CI matrix expansion**
  - [ ] R5 — ~~cpctelera hardening, upstream feedback~~ **DROPPED (README §5.13: cpctelera revoked)**; superseded by R10 (retirement)
  - [ ] G9 — CPC backend across 3+ games (blobs / crumbs / mapgen)
  - [ ] IN7 — optional `CONTROLLER` `.gdata` directive
  - [ ] AU6 — `SOUND_MAP` directive for cross-platform `SOUND` events
  - [ ] B8 — SUBs on CPC
  - [ ] TS4 — TAP-byte invariant mode
  - [ ] TS5 — CI matrix expansion

- [ ] **Phase 6 — Cleanup (docs + stub retirement; no removals per README §5.6)**
  - [ ] A6 — platform-scoped patches
  - [ ] A7 — cleanups + docs
  - [ ] T4 — matrix completion docs
  - [ ] AU7 — audio cleanup + docs
  - [ ] IN8 — input hardening, MSX sketch
  - [ ] B9 — banking cleanup + docs
  - [ ] TS6 — retire CPC-only stub games (merge `minimal_cpc` into `minimal`)

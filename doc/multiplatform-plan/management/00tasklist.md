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

## Status

- [ ] **Phase 1 — Foundation (no CPC code; pure preparation)**
  - [ ] TS1 — backfill ZX regression baselines (≥80 % of test games)
  - [ ] T0 — toolchain spike: prove z88dk `+cpc` + sdcc_iy + a tiny cpctelera build outside RAGE1
  - [ ] B1 — banking-config externalisation into `etc/rage1-config.yml` (ZX byte-identical)
  - [ ] G1 — `gfx_*` audit completion & baseline pin

- [ ] **Phase 2 — HAL & asset-pipeline scaffolding (ZX-only, additive)**
  - [ ] G2 — `SPRITE_ENGINE` → `GFX_BACKEND` mechanical rename
  - [ ] A1 — introduce `PLATFORM` directive (`zx48`, `zx128` only)
  - [ ] A2 — sibling-tree overlay copy in `make config` (mechanism only; no overlay files yet)
  - [ ] T1 — `PLATFORM` axis throughout the Makefile family; ZX-only
  - [ ] B2 — per-platform ISR / codeset YAML split
  - [ ] IN1 — input audit
  - [ ] IN2 — input HAL skeleton (alias-only, ZX-only)
  - [ ] AU1 — audio audit
  - [ ] AU2 — audio HAL aliases
  - [ ] R1 — cpctelera submodule add (vendored but not yet compiled)

- [ ] **Phase 3 — HAL generalisation (ZX byte-identical)**
  - [ ] G3 — attribute abstraction
  - [ ] G4 — pixel coords widening
  - [ ] G5 — sprite geometry abstraction
  - [ ] G6 — tile-ID abstraction
  - [ ] A3 — per-platform dispatch seam in `datagen.pl`
  - [ ] A4 — overlay precedence proven end-to-end on ZX
  - [ ] B3 — parameterise lowmem threshold checks
  - [ ] IN3 — engine ↔ HAL migration
  - [ ] IN4 — per-game `kbd.c` consolidation
  - [ ] AU3 — migrate to `audio_*` names (legacy stays as permanent silent aliases per README §5.6)

- [ ] **Phase 4 — CPC bring-up (cpc-flat first, then cpc-banked)**
  - [ ] R2 — cpctelera + z88dk hello-world PoC (gating test)
  - [ ] R3 — `cpct_img2tileset` asset-converter wiring
  - [ ] T2 — cpc-flat Makefile; first `.cpc`/`.cdt` build
  - [ ] B4 — CPC banking config seam (cpc-flat = no banking)
  - [ ] B5 — cpc-flat banking materialised
  - [ ] G7 — `gfx_cpctel.c` stub skeleton
  - [ ] IN5 — input CPC skeleton (stub)
  - [ ] AU4 — audio CPC skeleton + AT2 player relocation
  - [ ] A5 — `datagen.pl` invokes `cpct_img2tileset` for CPC assets
  - [ ] TS2 — Caprice32 + Xvfb in dev env + Docker
  - [ ] R4 — real `gfx_cpctel.c` + `games/minimal_cpc/`
  - [ ] G8 — real CPC backend wiring
  - [ ] IN6 — real CPC input via cpctelera keyboard scan
  - [ ] AU5 — real CPC audio via AT2 AKG generic player
  - [ ] TS3 — first CPC regression baseline
  - [ ] B6 — cpc-banked banking infrastructure
  - [ ] B7 — cpc-banked banking tooling
  - [ ] T3 — cpc-banked Makefile; first banked `.dsk` build

- [ ] **Phase 5 — Hardening + CI matrix expansion**
  - [ ] R5 — cpctelera hardening, upstream feedback
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

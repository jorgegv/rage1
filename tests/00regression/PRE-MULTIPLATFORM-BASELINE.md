# Pre-Multiplatform Baseline (Phase G1-1)

This file pins the screenshot regression baseline used as the canonical
reference for the cross-platform refactor. It is the "known-good" output
of RAGE1 as it stands **before** any multiplatform / HAL changes land.

## Provenance

- **Baseline merge commit**: `1017de8998938b59a6f9338a2008075b1ee38c82`
  (`Phase 1 TS1: ZX regression baselines (12 games) + make regression + docs`)
- **Branch**: `refactor_for_multiplatform`
- **Date pinned**: 2026-05-25
- **Runner**: `tests/00regression/regression.sh` (driven by JNEXT emulator,
  pixel-perfect comparison via ImageMagick `compare`)

## Suite status

`bash tests/00regression/regression.sh` was run on this baseline at the
date above. Every test that performs a screenshot comparison reported
**0 px diff** against its checked-in `reference.png`.

## Coverage matrix

Each row is one regression test under `tests/00regression/<name>/`. The
table covers all four cells of the `(BUILD_GFX_BACKEND × ZX target)`
matrix currently supported by RAGE1.

| Game           | Backend | ZX target | Status        |
|----------------|---------|-----------|---------------|
| minimal        | SP1     | 48k       | baseline pinned |
| mapgen         | SP1     | 48k       | baseline pinned |
| sub_bufs_48    | SP1     | 48k       | baseline pinned |
| default        | SP1     | 128k      | baseline pinned |
| blobs          | SP1     | 128k      | baseline pinned |
| crumbs         | SP1     | 128k      | baseline pinned |
| damage_mode    | SP1     | 128k      | baseline pinned |
| get_weapon     | SP1     | 128k      | baseline pinned |
| monochrome     | SP1     | 128k      | baseline pinned |
| sub_bufs_128   | SP1     | 128k      | baseline pinned |
| vortex2        | SP1     | 128k      | baseline pinned |
| minimal_jsp    | JSP     | 48k       | baseline pinned |
| default_jsp    | JSP     | 128k      | baseline pinned |

Backend × target coverage cells:

| Cell            | Games covering it                                  | Count |
|-----------------|----------------------------------------------------|-------|
| SP1 × 48k       | minimal, mapgen, sub_bufs_48                        | 3     |
| SP1 × 128k      | default, blobs, crumbs, damage_mode, get_weapon,    | 8     |
|                 | monochrome, sub_bufs_128, vortex2                   |       |
| JSP × 48k       | minimal_jsp                                         | 1     |
| JSP × 128k      | default_jsp                                         | 1     |

All four cells are covered; no `(backend × target)` combination is
unrepresented in the current baseline.

## Build-environment prerequisites

These are not part of the baseline itself, but the runner needs them to
reproduce the screenshots:

- `external/jsp/` git submodule must be initialised
  (`git submodule update --init --recursive`) — JSP backend builds
  depend on its headers.
- JNEXT binary at `$HOME/src/spectrum/jnext/build/gui-release/jnext`
  (override with `JNEXT=...`).
- NextZXOS SD-card image at
  `$HOME/src/spectrum/jnext/roms/nextzxos-1gb-fat32fix.img` (override
  with `JNEXT_SD_CARD=...`).
- ImageMagick `compare` on `$PATH`.
- RAGE1 build environment sourced via `env.sh` (handled automatically
  by the runner when present).

## Status policy

**This is the canonical pre-multiplatform baseline — do not refresh
without an explicit phase decision.**

Each `reference.png` in this directory is owned by the cross-platform
refactor plan. The expected churn pattern across phases is:

1. ZX-only refactor phases (Phase 1 / G1, G2): every test must remain
   at 0 px diff against this baseline — those phases are by definition
   no-op-visible on ZX.
2. Generalisation phases that change ZX rendering deliberately
   (Phase 2 onwards): each baseline refresh must be tied to a named
   phase task, visually reviewed, and committed alongside the code
   change that caused the diff (see `tests/00regression/README.md`
   §"When to update baselines").

Do not run `bash tests/00regression/regression.sh --update` against any
of these tests as a casual "the test is failing, let me fix it" action.
A failing test in a ZX-only phase is a real regression; investigate it.

## G1-3 inventory decision

The Phase G1-3 caller inventory (gfx.md spec, lines 823-828) offered two
options:

  (a) add inline `// HAL-CALLER` comments at ~45 sites in engine source.
  (b) leave the inventory in `doc/multiplatform-plan/gfx.md §1.3` only.

**Decision: option (b).** The inventory in `gfx.md §1.3` (lines 242-345)
is comprehensive, current, and already used as the single source of truth
by the Phase G2 mechanical-rename task. Adding inline comments would
duplicate it without improving discoverability — the document is the
canonical record. No inline comments are added in Phase G1.

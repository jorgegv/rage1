# Audio baseline — Phase AU1-1 status: DEFERRED to Phase AU5

**Phase**: AU1-1 (`doc/multiplatform-plan/audio.md` §5)
**Status**: deferred (no captures checked in)
**Decision date**: 2026-05-26
**Decision recorded vs HEAD**: `074c010` (post Phase 2 A1/B2)

## What AU1-1 originally asked for

Short audio captures (`.wav`-style) of four representative games —
`default` (128K Arkos2), `default_jsp` (128K Arkos2 + JSP gfx),
`vortex2` (128K Vortex2), `monochrome` (128K Arkos2) — checked into
this directory, for ear-comparison through Phase AU3.

## Why we are deferring

1. **No automated capture path.** JNEXT (the project's primary
   emulator) exposes audio capture via `--record FILE` (MP4 with
   ffmpeg). Producing a usable baseline requires running each game
   interactively, navigating menus, triggering in-game music and at
   least one SFX (BULLET_SHOT / ENEMY_KILLED) per game, then trimming
   the MP4 — a manual, per-game effort that doesn't fit the AU1
   time-box and produces baselines that are hard to re-acquire
   identically.
2. **No CPC comparison surface yet.** Phase AU3 (the actual ZX→HAL
   migration) is required to be **byte-identical** at engine binary
   level — that's verified by `tests/00regression/` (visual) plus the
   AU3 self-check that the migrated build produces the same binary
   bytes as the unmigrated build. An ear-comparison adds no value here:
   if the bytes match, the audio matches.
3. **The ear test only matters once a CPC port exists** — i.e. from
   Phase AU5 onwards, when the CPC AY backend lands and we genuinely
   need to compare CPC playback against ZX playback of the same track
   data. That's the right time to author the baselines.

## What we use instead, through Phase AU3

- **Byte-identical engine binary** before/after AU2 (alias) and AU3
  (call-site migration). Verified by re-running `make all-test-builds`
  and diffing the `.tap` files or the `.bin` payloads inside them.
- **Visual regression** via `tests/00regression/` (already green).
- **Static source inspection** of `engine/banked_code/128/tracker.c`
  and the per-backend `tracker_arkos2.c` / `tracker_vortex2.c`
  delegates — the HAL is a name-only refactor in AU2/AU3.
- **AT2 player tick-count comparison** (AU3 self-check, see audio.md
  §5 Phase AU3) — confirms the migrated build calls
  `PLY_AKG_PLAY` the same number of times per N frames as the pre-AU3
  build.

## What lifts the deferral

Phase AU5 (first real CPC AY backend) — at that point we must
re-instate AU1-1 in its full form, because:

- The CPC build can no longer be byte-identical (different
  architecture);
- Audible parity between ZX and CPC playback of the same song / FX
  becomes the *only* available verification surface;
- The baselines need to exist *before* CPC backend work starts so the
  CPC build can be ear-checked against them.

When AU5 starts, the AU5 implementer must:

1. Capture `default`, `default_jsp`, `vortex2`, `monochrome` on the
   ZX side via JNEXT `--record` (or equivalent), trim to a short
   identifiable clip including menu music, in-game music, and at
   least one SFX;
2. Check the trimmed clips into this directory as `.mp4` (or
   convert to `.wav` if smaller);
3. Update `doc/multiplatform-plan/audio.md` §5 Phase AU1 to note
   AU1-1 is now satisfied, and reference these baseline files from
   Phase AU5's audible-parity check.

## Risk acknowledged

If, between now and Phase AU5, the ZX audio behaviour silently drifts
(e.g. a Phase AU3 mistake that the regression suite misses), we will
not have an ear-baseline to catch it. This is mitigated by:

- AU3's byte-identical-binary requirement (the only legitimate way
  for audio to change is to change AT2 player code or song data —
  both visible in a diff);
- The AT2-tick-count check (catches "we forgot to call the player"
  bugs);
- `engine/banked_code/128/tracker_arkos2.c` and
  `tracker_vortex2.c` are 8-function-each thin shims — the change
  surface is small.

If during Phase AU2/AU3 implementation a developer feels uncertain
about audible parity, they can authoritatively check by recording
both pre-AU3 and post-AU3 versions of one game via JNEXT
`--record` and diffing the audio tracks — but this is an
**opt-in spot-check**, not a phase-exit gate, until AU5.

# RAGE1 screenshot regression — multi-platform

Pixel-perfect screenshot regression tests for RAGE1 games. Each test builds
a game, runs it headless in the right emulator, captures a PNG at a defined
emulated frame, and compares it against a checked-in baseline. The runner is
**platform-aware**: ZX platforms (`zx48`, `zx128`) drive the
[JNEXT](https://github.com/ZXjogv/jnext) emulator; CPC platforms (`cpc464`)
drive [Caprice32](https://github.com/ColinPitrat/caprice32). A test declares
the platforms it covers via the `PLATFORMS` key in `test.conf`, and stores one
baseline per platform under `<test>/<platform>/reference.png`.

## Quick start

```bash
# Run the full suite, every test × every platform it declares
# (also exposed as `make regression` from the repo root)
bash tests/00regression/regression.sh

# Run only specific tests
bash tests/00regression/regression.sh minimal minimal_jsp

# Run only one platform (across all tests, or named tests)
bash tests/00regression/regression.sh --platform cpc464
bash tests/00regression/regression.sh --platform cpc464 minimal_cpc

# Capture / refresh baselines (deliberate action — review before committing)
bash tests/00regression/regression.sh --update minimal
bash tests/00regression/regression.sh --update --platform cpc464 minimal_cpc
```

## Layout (multi-platform, "Option B" subdir-per-platform)

```
tests/00regression/
├── regression.sh                  # runner
├── README.md                      # this file
├── .gitignore                     # ignores actual/diff/artefacts (top-level + per-platform)
└── <test_name>/
    ├── test.conf                  # required: shell-sourceable config
    ├── zx48/reference.png         # checked-in baseline for that platform
    ├── zx128/reference.png
    ├── cpc464/reference.png
    └── <platform>/actual.png      # last run's capture (gitignored)
        <platform>/diff.png        # diff visualisation if FAIL (gitignored)
        <platform>/game.{tap,dsk}  # built artefact used for the run (gitignored)
```

Each platform's `reference.png` lives in its own subdir, so per-platform
`git status` / diffs stay cleanly scoped (changing a CPC baseline only
touches `cpc464/`).

## test.conf

```bash
TARGET_GAME=games/minimal     # arg to `make build target_game=...`
PLATFORMS="zx48"              # space-separated platform list (see below)
MACHINE=48k                   # LEGACY — kept for back-compat; derives PLATFORMS if absent
DELAY_FRAMES=150              # emulated frames before screenshot (all platforms)
DELAY_FRAMES_CPC464=300      # optional per-platform override (DELAY_FRAMES_<PLATFORM>)
TOLERANCE_CPC464=0           # optional per-platform tolerance (TOLERANCE_<PLATFORM>)
EXTRA_ARGS=""                 # optional JNEXT flags (ZX only)
SKIP_REGRESSION=true          # optional: skip the test entirely (see below)
```

- **`PLATFORMS`** — space-separated list of platforms the test covers, e.g.
  `zx48`, `zx128`, `cpc464`, or `"zx48 cpc464"` for a two-platform game.
  If absent, the runner derives it from the legacy `MACHINE` field
  (`48k → zx48`, `128k → zx128`; default `zx48`).
- **`DELAY_FRAMES_<PLATFORM>`** — per-platform frame count, overriding the
  shared `DELAY_FRAMES`. For ZX this is the JNEXT screenshot frame; for CPC
  it is cap32's `system.boot_time` (the screenshot fires at ~2× this value
  emulated frames — see the CPC section below).
- **`TOLERANCE_<PLATFORM>`** — per-platform pixel-diff tolerance, overriding
  the default (0 = pixel-perfect, or `JNEXT_TEST_TOLERANCE`). The default is
  0 on every platform; the knob exists for acknowledged-flaky tests
  (reviewed at baseline-commit time).

`SKIP_REGRESSION=true` makes the runner skip the test entirely (no build, no
emulator run, no comparison). Use it for games that have no deterministic
post-boot frame yet — see "Non-deterministic baselines" below.

### Backwards compatibility (indefinite, README §5.6)

The pre-multi-platform layout had a single top-level `<test>/reference.png`
and a `MACHINE` field. Both are honoured **indefinitely**:

- If a test has a top-level `reference.png` but no `<platform>/reference.png`,
  the top-level file is used as the implicit baseline for the test's single
  declared platform.
- If `PLATFORMS` is absent, it is derived from `MACHINE` as above.

No deprecation, no removal — old tests keep working unchanged.

## Requirements

- JNEXT built at `~/src/spectrum/jnext/build/gui-release/jnext` (override
  with `JNEXT=...`)
- NextZXOS SD-card image at
  `~/src/spectrum/jnext/roms/nextzxos-1gb-fat32fix.img` (override with
  `JNEXT_SD_CARD=...`)
- ImageMagick `compare` on `$PATH`
- RAGE1 build environment (`source env.sh`; the runner does this
  automatically if it finds `env.sh`)

## Adding a new test

1. `mkdir tests/00regression/<name>/`
2. Write `tests/00regression/<name>/test.conf`
3. `bash tests/00regression/regression.sh --update <name>`
4. **Inspect `tests/00regression/<name>/reference.png` visually** — make
   sure it shows the game in the expected state (not `LOAD ""`, not a
   tape-loading screen, not a mid-animation frame). If the capture is
   wrong, tune `DELAY_FRAMES` (or add a `--delayed-keypress-frames N KEY`
   to `EXTRA_ARGS` — see "Driving past a key wait" below) and re-run
   `--update`.
5. Re-run `bash tests/00regression/regression.sh <name>` (without
   `--update`) to confirm the new baseline reproduces against itself
   bit-for-bit (0 px diff).
6. Commit `test.conf` + `reference.png` together, one game per commit.

### Driving past a key wait

RAGE1 games configured with `LOADING_SCREEN ... WAIT_ANY_KEY=1` halt on the
loading-screen image until a key is pressed. The screenshot will sit on the
loading screen forever otherwise. Inject a keypress with JNEXT's
`--delayed-keypress-frames`:

```bash
EXTRA_ARGS="--delayed-keypress-frames 700 SPACE"
DELAY_FRAMES=1000
```

The keypress at frame 700 dismisses the loading screen on 128k builds; the
screenshot at frame 1000 captures the controller-select / first-screen state.
Tune the two numbers up if the game needs more time after the keypress, down
if it animates quickly past the desired frame.

### Non-deterministic baselines

Some games may not have any stable post-boot frame — e.g. a continuously
animated intro that never settles into a quiet state, or a state that
depends on uninitialised memory. For these, do **not** check in a baseline
that flakes. Instead, mark the test as skipped:

```bash
# tests/00regression/<name>/test.conf
# SKIP: <name> intro animates from frame 1; no quiet frame to baseline.
# Revisit once the intro has a deterministic settle point.
TARGET_GAME=games/<name>
MACHINE=128k
DELAY_FRAMES=1000
SKIP_REGRESSION=true
```

Always include a comment explaining **why** the test is skipped. Skip is
not an outage — it is a documented decision that the regression suite
should not assert on this game today. Audit `SKIP_REGRESSION` entries
periodically and convert them to real baselines as soon as the game grows
a settle point.

## When to update baselines

Update an existing `reference.png` only when the visual change is
**intentional**:

- A renderer/engine change deliberately alters output (new palette,
  new tile layout, bug fix that corrects a glyph, etc.).
- A game's `.gdata` was edited and the new content is the canonical
  rendering.
- A toolchain bump (z88dk, SDCC, JSP, SP1) produces a different but
  still-correct pixel layout, and the change has been reviewed and
  approved.

To update:

```bash
bash tests/00regression/regression.sh --update <name>
```

Then **eyeball the new `reference.png` against the old one** (e.g. with
`compare old.png new.png diff.png` or by reviewing the diff on the PR).
Commit the new baseline in the same commit as the code/data change that
caused the diff, with a message that explains the visual delta.

Do **not** update baselines to mask a regression: if a test starts failing
and you don't understand why, the answer is to investigate, not to
re-capture.

## How DELAY_FRAMES works

The screenshot is taken at *emulated* frame `DELAY_FRAMES`, not wall-clock
time. Results are independent of host CPU speed. In `--headless` mode
JNEXT runs the emulator at full host speed, so a 700-frame delay costs
only a couple of seconds wall-clock.

**Minimums for screenshotting an already-running game** (per JNEXT):

| Machine | Minimum DELAY_FRAMES |
|---------|----------------------|
| 48k     | ~150                 |
| 128k    | ~500 (menu adds time) |
| plus3   | ~700 (disk-probe pause adds more) |

Below these floors the BASIC ROM hasn't finished its boot + auto-load
sequence; you'll capture a `LOAD ""` mid-typing or mid-load screen.

If `reference.png` shows `LOAD ""` text, the delay is too low. If the game
has visible animation at the capture point, the test will flake — capture
earlier or drive past it via keypress.

---

## CPC regression baselines

The runner drives CPC tests through the same `regression.sh` as ZX tests;
the `run_emulator_cpc()` helper wraps the verified Caprice32 recipe below.

- **Platform**: the first CPC baseline is **`cpc464`** (cpc-flat). The
  spec's TS3-3 names `cpc6128`, but the cpc6128 (cpc-banked) toolchain is
  Phase T3 and does not build yet; `games/minimal_cpc` builds as cpc464 via
  `make build-minimal_cpc` (G8). The `cpc6128` baseline is added after T3.
- **Artefact**: CPC tests produce `game.dsk` (cpc-flat). The runner RUNs the
  AMSDOS binary `GAME` inside the dsk (`run"game.`).
- **Capture frame**: `DELAY_FRAMES_CPC464` is passed to cap32 as
  `system.boot_time`; the screenshot fires after the boot wait plus one
  `CAP32_DELAY` (≈2× that value emulated frames). This is **frame-counted**,
  not wall-clock — so the capture is deterministic and byte-reproducible
  run-to-run and across rebuilds, even though `minimal_cpc` has a moving
  enemy. `TOLERANCE_CPC464=0` (pixel-perfect) is therefore safe; the moving
  enemy lands on the same pixels every time at a fixed frame.
- **Determinism note**: verified by capturing `minimal_cpc/cpc464` twice and
  after a fresh rebuild — all three captures were 0 px diff (identical SHA).

To add or refresh a CPC baseline:

```bash
bash tests/00regression/regression.sh --update --platform cpc464 minimal_cpc
# then eyeball tests/00regression/minimal_cpc/cpc464/reference.png
bash tests/00regression/regression.sh --platform cpc464 minimal_cpc   # 0 px diff
```

## CPC emulator (Caprice32) — headless screenshot

### Install

Caprice32 is built from source and installed at `~/src/cpc/caprice32/`.
The binary is `~/src/cpc/caprice32/cap32`; the config is
`~/src/cpc/caprice32/cap32.cfg`.  The CI Docker `:test` image also includes
Caprice32 (built from the same pinned commit at image-build time).

Verified version: **post-v4.6.0 master HEAD, commit `93486f8`** (tag
`v4.6.0` = `0eb07f5`, ~647 commits earlier; the `VERSION_STRING` in
`cap32.h` still reads `v4.6.0` because it was never bumped — so
`cap32 -V` prints `v4.6.0` even though the binary is well past that tag).

### Headless invocation (verified recipe)

```bash
DISP=:99
SCRNDIR=/tmp/cap32-scrnshots
mkdir -p "$SCRNDIR"

Xvfb "$DISP" -screen 0 640x480x24 &
XVFB_PID=$!

DISPLAY="$DISP" SDL_VIDEODRIVER=x11 WAYLAND_DISPLAY= \
  cap32 -c ~/src/cpc/caprice32/cap32.cfg \
  -O "system.boot_time=300" \
  -O "file.sdump_dir=$SCRNDIR" \
  -a $'run"<binary>.\r' \
  -a "CAP32_DELAY" \
  -a "CAP32_SCRNSHOT" \
  -a "CAP32_EXIT" \
  game.dsk

kill "$XVFB_PID"
# Screenshot is at: $SCRNDIR/screenshot_<YYYYMMdd_HHmmss>.png
```

Key points:

- `SDL_VIDEODRIVER=x11 WAYLAND_DISPLAY=` forces SDL to use the Xvfb
  X11 server.  Without this SDL2 follows `WAYLAND_DISPLAY` to the live
  compositor and the Xvfb root returns a black image.
- The `-O` flag overrides config values: `system.boot_time` and
  `file.sdump_dir` are the two that matter for headless automation.
- `CAP32_SCRNSHOT` saves `screenshot_<date>.png` to `sdump_dir`.
  There is no way to specify the filename directly; collect with `ls
  sdump_dir/screenshot_*.png | sort | tail -1`.

### OQ-TS1 resolution — verified autocmd token spellings

Verified against pinned Caprice32 v4.6.0 source (`src/argparse.cpp`,
`src/keyboard.cpp`, `src/cap32.cpp`) and confirmed working in a live
headless Xvfb test run on 2026-05-31:

| Token | Present | Parameterisation | Notes |
|-------|---------|-----------------|-------|
| `CAP32_SCRNSHOT` | Yes | No argument | Saves `screenshot_<date>.png` to `file.sdump_dir` from config. Output filename cannot be specified directly. |
| `CAP32_DELAY` | Yes | **No argument** | Pauses for `system.boot_time` frames (config value). The spec sketch `CAP32_DELAY=300` is WRONG for this version — the `=300` suffix would be typed as CPC keyboard input. Control the delay via `-O system.boot_time=<frames>` instead. |
| `CAP32_WAITBREAK` | Yes | No argument | Sets a Z80 breakpoint at address 0 and waits for it. `CAP32_DELAY` is simpler for frame-counted timing. |
| `CAP32_EXIT` | Yes | No argument | Calls `cleanExit(0)` — cap32 exits with code 0. |
| `CAP32_NEXTDISKA` | Yes | No argument | Switches to next disk in a zip. Not needed for single-dsk use. |
| `CAP32_SNAPSHOT` | Yes | No argument | Saves a `.sna` snapshot (different from screenshot). |

**CONFIRMED WORKING sequence** (verified 2026-05-31):

```
cap32 -O system.boot_time=300 -O file.sdump_dir=/tmp/out \
  -a $'run"poc.\r' \
  -a CAP32_DELAY \
  -a CAP32_SCRNSHOT \
  -a CAP32_EXIT \
  poc.dsk
```

This exits 0 and produces a PNG showing the running CPC binary.

**Tokens that do NOT exist** in v4.6.0 (from source survey):
- There is no combined "screenshot-and-exit" shortcut token.
- There is no `CAP32_SCRNSHOT=<filename>` parameterisation.

**Workaround for `CAP32_DELAY <N>`**: Use `-O system.boot_time=<N>` to
set the per-DELAY wait in frames before the `-a CAP32_DELAY` token.
Multiple `CAP32_DELAY` tokens in one autocmd sequence each wait
`boot_time` frames.

### Why not `import -window root` (the R2 Xvfb-grab approach)?

The existing `tools/cap32-shot.sh` uses `import -window root` + `xdotool
key F3` as a dual-grab approach.  The `CAP32_SCRNSHOT` autocmd path is
strictly cleaner:

- No `ImageMagick import` dependency for capture (only needed for `compare`
  in regression).
- No `xdotool` focus + F3 dance; the screenshot happens inside the emulator
  at the exact frame the autocmd fires.
- Deterministic: the screenshot fires at `boot_time` frames after
  `CAP32_DELAY`; not dependent on `sleep` wall-clock timing.
- cap32 exits 0 cleanly; the script does not need to `kill` a lingering
  process.

The `import -window root` fallback remains documented in `cap32-shot.sh`
for reference, but is superseded by the autocmd approach.

# RAGE1 screenshot regression — JNEXT-driven

Pixel-perfect screenshot regression tests for RAGE1 games. Each test builds
a game, runs it headless in the [JNEXT](https://github.com/ZXjogv/jnext)
emulator, captures a PNG at a defined emulated frame, and compares it
against a checked-in baseline.

## Quick start

```bash
# Run the full suite (also exposed as `make regression` from the repo root)
bash tests/00regression/regression.sh

# Run only specific tests
bash tests/00regression/regression.sh minimal minimal_jsp

# Capture / refresh baselines (deliberate action — review before committing)
bash tests/00regression/regression.sh --update minimal
```

## Layout

```
tests/00regression/
├── regression.sh           # runner
├── README.md               # this file
├── .gitignore              # ignores actual.png, diff.png, game.tap
└── <test_name>/
    ├── test.conf           # required: shell-sourceable config
    ├── reference.png       # checked-in baseline
    ├── actual.png          # last run's capture (gitignored)
    ├── diff.png            # diff visualisation if FAIL (gitignored)
    └── game.tap            # built TAP used for the run (gitignored)
```

## test.conf

```bash
TARGET_GAME=games/minimal     # arg to `make build target_game=...`
MACHINE=48k                   # 48k | 128k | next
DELAY_FRAMES=300              # emulated frames before screenshot
EXTRA_ARGS=""                 # optional JNEXT flags
SKIP_REGRESSION=true          # optional: skip the comparison (see below)
```

`SKIP_REGRESSION=true` makes the runner skip the test entirely (no build, no
emulator run, no comparison). Use it for games that have no deterministic
post-boot frame yet — see "Non-deterministic baselines" below.

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

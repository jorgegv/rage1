---
name: jnext-regression
description: Activates the RAGE1 screenshot-regression workflow driven by the JNEXT emulator. Use when running, updating, or adding pixel-perfect regression tests for RAGE1 games under tests/00regression/.
---

You are now operating the **RAGE1 JNEXT screenshot regression framework**. It builds a RAGE1 game, runs it headless in the JNEXT ZX Spectrum Next emulator, captures a PNG screenshot at a defined emulated frame, and pixel-diffs it against a checked-in baseline.

## The Contract

- Reference PNGs (`tests/00regression/<name>/reference.png`) are **the source of truth**. Tests fail unless the captured screenshot matches the reference at **0 pixel difference** (configurable via `JNEXT_TEST_TOLERANCE`).
- Reference images are **only updated by deliberate action** — never silently bring a baseline in line with the current output. A baseline update is an admission that the visual is intentionally different.
- Tests are run **sequentially** (each rebuilds `./game.tap` from scratch). This is by design — parallelisation is a future enhancement that requires per-game build dirs.

## Layout

```
tests/00regression/
├── regression.sh         # the runner
├── .gitignore            # ignores actual.png, diff.png, game.tap
├── README.md
└── <test_name>/
    ├── test.conf         # required: TARGET_GAME, MACHINE, DELAY_FRAMES, EXTRA_ARGS
    ├── reference.png     # baseline (committed)
    ├── actual.png        # gitignored, last run's screenshot
    ├── diff.png          # gitignored, present only on FAIL
    └── game.tap          # gitignored, the built TAP that was tested
```

## test.conf format (shell-sourceable)

```bash
TARGET_GAME=games/minimal     # path relative to project root, passed to `make build target_game=...`
MACHINE=48k                   # 48k | 128k | next
DELAY_FRAMES=150              # emulated frames before screenshot (see "Tuning DELAY_FRAMES" below)
EXTRA_ARGS=""                 # optional JNEXT flags, e.g. "--delayed-keypress-frames 200 ENTER"
```

## Key tools and paths

- **Runner**: `bash tests/00regression/regression.sh`
- **JNEXT binary** (auto-detected): prefers `~/src/spectrum/jnext/build/gui-release/jnext`, falls back to `gui-debug` then `build/jnext`. Override with `JNEXT=<path>`.
- **SD card** (NextZXOS image, required by JNEXT): default `~/src/spectrum/jnext/roms/nextzxos-1gb-fat32fix.img`. Override with `JNEXT_SD_CARD=<path>`.
- **Diff tool**: ImageMagick `compare -metric AE` (pixel-perfect at AE==0). Tolerance overridable via `JNEXT_TEST_TOLERANCE=N`.

## Workflows

### Run all tests (the standard pre-commit check)

```bash
bash tests/00regression/regression.sh
```

Each test rebuilds its game, runs JNEXT headless, and pixel-diffs against the reference. Exit 0 = all green; exit 1 = at least one FAIL.

### Run a specific test

```bash
bash tests/00regression/regression.sh minimal minimal_jsp
```

Positional args filter by directory name under `tests/00regression/`.

### Add a new test

1. Pick a name (typically matches the target game name).
2. `mkdir tests/00regression/<name>/`
3. Write `tests/00regression/<name>/test.conf` with `TARGET_GAME`, `MACHINE`, `DELAY_FRAMES`. Start with `DELAY_FRAMES=300` for 48K and tune from there (see "Tuning DELAY_FRAMES" below).
4. Capture the baseline: `bash tests/00regression/regression.sh --update <name>`
5. **Inspect `tests/00regression/<name>/reference.png` visually** before committing — make sure it shows the game in the expected state (not a boot screen, not a glitched frame, no stale artifacts).
6. Commit `test.conf` + `reference.png` together.

### Update a baseline after intentional visual change

```bash
bash tests/00regression/regression.sh --update <name>
```

**Before committing:** review the new `reference.png` against the previous one (or against `diff.png` from a prior FAIL) and explain in the commit message *why* the visual changed.

### Investigate a FAIL

1. The runner writes `tests/00regression/<name>/actual.png` (current capture) and `tests/00regression/<name>/diff.png` (visual highlight of differing pixels).
2. Read all three (`reference.png`, `actual.png`, `diff.png`) to localise the regression.
3. Decide: real regression → fix the code; intended change → update the baseline (see workflow above).
4. The TAP that was loaded is left in `tests/00regression/<name>/game.tap` for reproduction with JNEXT GUI:
   ```bash
   ~/src/spectrum/jnext/build/gui-release/jnext --sd-card ~/src/spectrum/jnext/roms/nextzxos-1gb-fat32fix.img --machine 48k --load tests/00regression/<name>/game.tap
   ```

### Tuning DELAY_FRAMES

The screenshot is taken at *emulated* frame `DELAY_FRAMES`, not wall-clock time — results are host-CPU-independent. In `--headless` mode JNEXT runs the emulator at full host speed (no vsync throttling), so even a 700-frame delay costs only a couple of wall-clock seconds.

**Minimums for a screenshot of an already-running game** (authoritative, per JNEXT):
- **48K**: ~150 frames minimum
- **128K**: ~500 frames (boot menu adds time)
- **+3 (plus3)**: ~700 frames (disk-probe pause adds more)

Below these floors the BASIC ROM hasn't finished its boot + auto-load sequence yet and you'll capture a `LOAD ""` mid-typing or a mid-load screen instead of the game.

- If `reference.png` shows the BASIC `LOAD ""` text or a mid-load screen, `DELAY_FRAMES` is too low — raise it.
- If the game has visible animation at the capture point (sprite flashing, animated tile), the test will flake — either pick an earlier delay before the animation starts, or use `EXTRA_ARGS="--delayed-keypress-frames N <key>"` to drive the game past it into a deterministic state.

### Driving input (menus, "press any key", etc.)

Use `EXTRA_ARGS` with JNEXT's keypress flags:

```bash
EXTRA_ARGS="--delayed-keypress-frames 200 SPACE --delayed-keypress-frames 250 ENTER"
```

`KEY` is a single character or symbolic `ENTER` / `RETURN` / `SPACE` (case-insensitive).

## Pitfalls

- **Don't run with `--update` unless you intend to overwrite baselines.** It accepts whatever JNEXT produced as truth.
- **Don't commit `actual.png`, `diff.png`, or `game.tap`** — `.gitignore` covers them but verify if you stage manually.
- **`make clean` runs between tests** — sequential is intentional because `./game.tap` is overwritten by each build. Tests interleaved or parallel would race; don't try.
- **Animation = flake.** If the game has any frame-counter-driven movement at the capture point, two captures may not match pixel-perfectly. Either capture before animation starts or drive the game to a deterministic state via keypress.
- **48K vs 128K machine type** is per test, not per game. The same game source can produce different binaries via `make build48` / `make build128`; the runner uses plain `make build`, which respects the game's `ZX_TARGET`. If you need to test both targets, that's two tests with two different `target_game=` values (or, eventually, a `BUILD_TARGET=` field in test.conf — not yet implemented).
- **`reference.png` is 640×512** (JNEXT's native output resolution for ZX Spectrum modes). Don't scale or convert it.
- **SP1 vs JSP visual parity**: per [[project-jsp-sprite-format]], the two sprite engines share the same sprite data format and are expected to render identically. A `minimal` reference and a `minimal_jsp` reference *should* match pixel-for-pixel for the same game scene — that property is itself a useful regression check.

## When asked to…

- **"Add a regression test for game X"** → create `tests/00regression/X/test.conf`, capture baseline with `--update`, inspect the PNG, commit both files together. Report the baseline image to the user before committing if non-obvious.
- **"The regression failed"** → read `actual.png` and `diff.png`, localise the change, then ask the user whether to fix code or update baseline. Never silently update a baseline.
- **"Update all baselines"** → flag this as unusual and ask *why* before running `--update` without test filters. A blanket baseline update wipes out the test suite's safety net.
- **"Run the regression suite"** → `bash tests/00regression/regression.sh`; report pass/fail counts; for each FAIL, show the diff path so the user can inspect.

# RAGE1 screenshot regression — JNEXT-driven

Pixel-perfect screenshot regression tests for RAGE1 games. Each test builds
a game, runs it headless in the [JNEXT](https://github.com/ZXjogv/jnext)
emulator, captures a PNG at a defined emulated frame, and compares it
against a checked-in baseline.

## Quick start

```bash
# Run the full suite
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
```

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
   sure it shows the game in the expected state
5. Commit `test.conf` + `reference.png` together

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

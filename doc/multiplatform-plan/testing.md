# Testing: per-platform emulators + regression framework + CI matrix

This document is the **testing** chapter of the RAGE1 cross-platform plan
(see `doc/multiplatform-plan/` for the wider plan, in particular `gfx.md`,
`assets.md`, `toolchain.md`, `cpc-renderer.md`, `banking.md`, `audio.md`,
`input.md`). It covers the existing CI / regression / `make`-driven
testing surface; what changes are needed to extend that surface to the
Amstrad CPC (CPC464 and CPC6128 as build identities; CPC664 runs the
CPC464 binary as a runtime target); the emulator choice for CPC
screenshot regression; the CI matrix the team should land; and the
phased plan to get there.

Architectural anchors from the parent plan that constrain this
document:

- ZX back-compat is **best-effort, green at phase boundaries**. Each
  phase ends with `make all-test-builds` green for ZX **and**
  `tests/00regression/` ZX screenshot tests green. Mid-phase ZX
  regressions are tolerable.
- The asset model is "shared core `.gdata` + per-platform overlays"
  (`assets.md`). One game directory can produce both a ZX binary and a
  CPC binary. The CI matrix exercises **per-game × per-platform**.
- The build matrix is parameterised by `PLATFORM` (`toolchain.md` §3.1)
  with 4 values: `zx48 | zx128 | cpc464 | cpc6128`. CPC664 is not a
  separate `PLATFORM` value — it runs the `cpc464` binary as a
  runtime target.
- The CPC graphics backend wraps cpctelera, vendored as a submodule under
  `external/cpctelera/` (`cpc-renderer.md` §4.1). The first runnable CPC
  RAGE1 game (`games/minimal_cpc/`) appears in Phase R4 of
  `cpc-renderer.md` and matches Phase G8 of `gfx.md`.

This is a living document. Phase IDs use `TS` (Testing Subsystem) to
avoid collision with `gfx.md`'s `G*`, `assets.md`'s `A*`, `toolchain.md`'s
`T*`, `cpc-renderer.md`'s `R*`, `banking.md`'s `B*`, and so on.

Out of scope for this document (referenced where load-bearing):

- The shape of the `gfx_*` / `audio_*` / `input_*` HALs themselves
  (owned by `gfx.md`, `audio.md`, `input.md`). We only describe what
  HAL changes need new tests.
- Makefile / `PLATFORM` plumbing internals (owned by `toolchain.md`).
  We only describe CI Docker image deltas at the level of "what tools
  must be installed" — the actual Dockerfile rewrites belong to that
  doc.
- Banking design (owned by `banking.md`). We only describe per-platform
  memory tests at the orchestration level.
- cpctelera library selection rationale (owned by `cpc-renderer.md`).
  We only describe how the PoC binaries produced in `cpc-renderer.md`
  R2 / R4 feed into the regression infrastructure.

References use `file_path:line_number` form.

---

## 1. Current state audit

### 1.1 `make all-test-builds` — what it builds

The top-level entry point is `Makefile:145-157`. The implementation:

```
ALL_TEST_GAMES = $(shell cd $(TEST_GAMES_DIR)/ && ls -1 )       # Makefile:88
test-build-%:                                                   # Makefile:141
    if ( ! $(MYMAKE) build-$* >/tmp/build-$*.log 2>&1 ) then ...
all-test-builds:                                                # Makefile:145
    for i in $(ALL_TEST_GAMES); do $(MYMAKE) test-build-$$i; done
```

The set is **whatever subdirectory exists under `games/`**, picked up at
runtime by `ls -1`. There is no explicit list of "which games are in CI"
checked into the repo — adding a directory under `games/` opts it in
automatically. Each game needs a hand-written `build-<name>` target in
`Makefile:91-135`, which in practice maps to either:

- a plain `$(MYMAKE) build target_game=$(TEST_GAMES_DIR)/<name>` (most
  games), or
- a custom recipe (e.g. `build-mapgen` runs `btilegen.pl` + `mapgen.pl`
  first; see `Makefile:100-111`).

The games present today (`ls games/`):

```
blobs        damage_mode    default        default_jsp   get_weapon
mapgen       minimal        minimal_jsp    monochrome    sub_bufs_128
sub_bufs_48  vortex2        crumbs
```

The actual build target — 48 vs 128 — is **read out of each game's own
`game_config/*.gdata`** by the `build` rule at `Makefile:60-65`:

```
$(MYMAKE) ZX_TARGET=$(shell grep -E 'ZX_TARGET.+(48|128)$$' \
    $(TARGET_GAME)/game_data/game_config/*.gdata ...) ...
```

So today a single game declares a single ZX target, and the test-build
loop builds exactly one ZX binary per game. There is no per-game
multi-target expansion. **Crucially: this is the structural axis that
must change for the multi-platform plan** — every game must be buildable
against multiple `PLATFORM` values; today most are not. The mechanics of
that change live in `toolchain.md` Phase T1 (introducing the `PLATFORM`
axis) and `assets.md` Phase A2 (sibling-tree overlays). This document
adds the **orchestration** to actually drive multiple builds per game in
CI (§4) and the **per-platform regression baselines** to verify
correctness (§3).

A small ZX-specific subtlety: `make all-test-builds` rebuilds everything
serially (`Makefile:148`) — `for i in ...; do $(MYMAKE) test-build-$$i;
done`. The build artefacts overlap (each leaves `game.tap` in the project
root) so it is **not** parallel-safe. Any matrix expansion that builds
several platforms of the same game must respect this; the existing
regression script (`tests/00regression/regression.sh:133`) does the same
`make clean; make build` dance per test for the same reason.

### 1.2 `tests/00regression/` framework — how it runs

The runner is `tests/00regression/regression.sh` (210 lines, documented
in `tests/00regression/README.md`). The pattern:

1. Discover every `tests/00regression/<name>/` subdirectory that contains
   a `test.conf` (regression.sh:81-84).
2. Per test, source `test.conf`. Required keys: `TARGET_GAME`, `MACHINE`,
   `DELAY_FRAMES`; optional: `EXTRA_ARGS` (regression.sh:120-130).
3. `make clean && make build target_game=$TARGET_GAME` (regression.sh:133).
   Sequential per test, because `game.tap` is overwritten.
4. Drive JNEXT in headless mode, with `--delayed-screenshot`,
   `--delayed-screenshot-frames`, and `--delayed-automatic-exit`
   (regression.sh:158-166):

   ```
   "$JNEXT" --headless \
       --sd-card "$JNEXT_SD_CARD" \
       --machine "$MACHINE" \
       --load "$test_dir/game.tap" \
       --delayed-screenshot "$out_img" \
       --delayed-screenshot-frames "$DELAY_FRAMES" \
       --delayed-automatic-exit "$exit_delay" ...
   ```

5. Compare resulting PNG to a checked-in `reference.png` using
   ImageMagick's `compare -metric AE` (regression.sh:188-197). Tolerance
   defaults to 0 (pixel-perfect); overridable via
   `JNEXT_TEST_TOLERANCE` env var (regression.sh:43).
6. `--update` mode rewrites `reference.png` from the latest run
   (regression.sh:176-181) for deliberate baseline refresh.

Per-test layout (regression.sh:113-117):
```
tests/00regression/<name>/
├── test.conf           # required
├── reference.png       # checked-in baseline
├── actual.png          # gitignored
├── diff.png            # gitignored, only on FAIL
└── game.tap            # gitignored, built per run
```

The framework is JNEXT-specific by construction (the binary path, SD
card and headless flag set are JNEXT's). Two consequences for the
multi-platform plan:

- JNEXT is and will remain the ZX-side driver. No portability concern
  there.
- For CPC the runner needs to learn a **second emulator path**, with a
  different but isomorphic flag set. The shape "build → load binary →
  wait N emulated frames → capture PNG → exit" is the right abstraction;
  the runner just needs to choose the emulator binary based on the test's
  `PLATFORM`. Design in §3.

The framework's correctness properties to **preserve**:

- Wall-clock independence: capture happens at *emulated frame N*, not
  after *N wall-clock seconds*. The CPC equivalent (§2) must support the
  same.
- Reproducibility: pixel-perfect tolerance is the default. Any tolerance
  policy change must be a per-test override in `test.conf`, not a global
  loosening.
- Single-binary discovery: the runner finds tests by `find */test.conf`,
  not by an explicit list. Extending to per-platform baselines must
  preserve that property — `assets.md` and this doc agree the baselines
  are co-located with the test directory.

### 1.3 CI: `.github/workflows/` + `rage1-z88dk` Docker image

Two workflows live at `.github/workflows/`:

- **`build-test-games.yaml`** (28 lines, pushed-on-master and
  workflow-dispatch). Runs `make all-test-builds` inside the
  `zxjogv/rage1-z88dk:latest` container, mounting the repo at
  `/src/rage1`. Checks out submodules recursively (for JSP today; will
  be needed for cpctelera tomorrow).
- **`build-z88dk-docker.yaml`** (33 lines, triggered only by changes
  under `docker/`). Builds and pushes the Docker image to Docker Hub.

The Docker image (`docker/Dockerfile`, 41 lines) is a Fedora-based
container that installs:

- Fedora baseline + Perl + every CPAN module the build needs
  (`docker/Dockerfile:13-17`).
- z88dk pinned at tag `v2.3` (`docker/Dockerfile:8,19-25`) built from
  source with `BUILD_SDCC=1 BUILD_SDCC_HTTP=1` — i.e. SDCC bundled with
  z88dk, not system SDCC.
- `bas2tap` from `speccyorg/bas2tap` (`docker/Dockerfile:27-32`), copied
  into z88dk's bin.

The image notably **does not** contain:

- Any CPC tooling (cpctelera tools, `2cdt`, `iDSK`).
- Any emulator (FUSE, JNEXT, Caprice32). CI today is build-only — there
  is no CI-driven screenshot regression yet. `tests/00regression/`
  exists, but is run locally by developers, not in CI.

That last point is a structural gap, not a multi-platform issue, but
the multi-platform plan is a natural moment to close it (Phase TS3
below).

`build-test-games.yaml` consumes `submodules: recursive`
(`.github/workflows/build-test-games.yaml:22`) so any new submodule
(`external/cpctelera`) is picked up automatically.

### 1.4 Per-test-game baselines (current ZX coverage)

`ls tests/00regression/` today reveals **one** test directory:
`minimal/`. Its `test.conf` declares `TARGET_GAME=games/minimal,
MACHINE=48k, DELAY_FRAMES=150`. So the current regression coverage is:

| Game | Platform | Baseline |
|------|----------|----------|
| `games/minimal` | zx48 | `tests/00regression/minimal/reference.png` |

That's it. The framework is set up to scale (the runner discovers
tests by directory existence) but no other test games are wired in yet.
This is a deliberate choice — the framework was introduced as a
single-game proof and the team is expected to add baselines per game as
each game settles.

For the multi-platform plan this is **both a problem and an
opportunity**: the baseline coverage is too thin to detect mid-phase ZX
regressions reliably (any HAL refactor could break `blobs`, `crumbs`,
`mapgen`, etc. silently). Phase TS1 below addresses this directly by
adding ZX baselines for every existing `games/*` before the CPC work
starts — so that "best-effort green at phase boundaries" has teeth.

### 1.5 FUSE + JNEXT integration (manual + scripted)

Two emulators are wired into the build:

- **FUSE** — `make run` at `Makefile.common:236-237`:
  `fuse $(FUSE_RUN_OPTS) $(FINAL_TAP) --debugger-command ''`. Plus
  `make debug` at `Makefile.common:239-240` which feeds the FUSE
  debugger a script generated by `tools/r1sym.pl`. FUSE is interactive
  only; there is no headless-screenshot path through it. Used for
  developer manual testing.
- **JNEXT** — `make run-jnext` at `Makefile.common:246-247`:
  `$(JNEXT) --sd-card $(JNEXT_SD_CARD) --machine $(ZX_TARGET)k --load
  $(FINAL_TAP)`. GUI run, again primarily developer-driven. The headless
  scripted path is exercised exclusively by `tests/00regression/`
  (§1.2).

There is also a `runz` target at `Makefile.common:242-243` for ZEsarUX
— legacy, no scripting integration. **Out-of-scope for cleanup in this
plan**: `runz` is left as-is; it does not gate any phase exit and is
not migrated under the per-platform `make run-*` family. If it becomes
a maintenance burden later, retirement can be filed separately under
OQ-TS8's `make run-*` symmetry discussion.

For the multi-platform plan we **keep FUSE and JNEXT for ZX**
(unchanged). We add an analogous pair for CPC in §2: one **interactive**
emulator (developer's choice) for `make run` and a **scriptable**
emulator for `tests/00regression/`.

### 1.6 Memory tests (`make mem`)

`Makefile.common:314-315`:
```
mem:
    ./tools/mem-summary-$(BUILD_SPRITE_ENGINE)-$(ZX_TARGET).sh
```

Four scripts exist in `tools/`:
`mem-summary-sp1-48.sh`, `mem-summary-sp1-128.sh`,
`mem-summary-jsp-48.sh`, `mem-summary-jsp-128.sh`.

The naming convention is `mem-summary-<gfx_backend>-<target>.sh`. This
is the precedent for per-platform mem reports under the multi-platform
matrix; the new dimension is `<platform>` in place of (or in addition
to) `<target>`. See §5.

---

## 2. CPC emulator strategy

### 2.1 Candidate survey

Five CPC emulators are credible candidates for both interactive use and
scripted screenshot regression. The gate property is **headless /
scripted screenshot output**: the emulator must run without user
interaction, load a CDT/DSK/SNA, run the emulated machine for N frames,
emit a PNG, and exit.

| Emulator | Repo / origin | Platforms | Headless / scripted capability | Verdict |
|---|---|---|---|---|
| **Caprice32** | `github.com/ColinPitrat/caprice32` | Linux / macOS / Windows | **Yes** — `--autocmd` with `CAP32_SCRNSHOT`, `CAP32_DELAY`, `CAP32_WAITBREAK` tokens (autocmd added in v4.5.0; `CAP32_DELAY` added in v4.6.0); SDL2-based, runs under `xvfb-run` for true headless CI | **Recommended** |
| **ACE-DL** (RouDouDou) | `roudoudou.com/ACE-DL` | Linux / macOS / Windows | No — SDL-based GUI port of ACE; explicitly "no scripting capabilities, no plugins" per RouDouDou's own description; the original ACE (MorphOS) has ARexx scripting, but ACE-DL strips it | Rejected for CI |
| **Retro Virtual Machine (RVM)** | `retrovirtualmachine.org` | Linux / macOS / Windows | Unknown — no public CLI/screenshot docs surfaced; closed-source; primarily a polished interactive emulator with CRT effects | Rejected for CI (interactive-only) |
| **Caprice Forever** | windows-only | Windows | No — Windows-only GUI emulator | Rejected (platform) |
| **Arnold** | `github.com/rofl0r/arnold` | Linux (X11/SDL) | Partial — `-drivea`, `-tape`, `-snapshot`, `-frameskip` flags exist; no documented PNG/screenshot CLI option | Rejected for CI |
| **Xcpc** | `xcpc-emulator.net` | Linux / BSD (X11) | No documented headless mode; F3 snapshot is interactive only | Rejected for CI |
| **CPCEC** | `cngsoft.no-ip.org/cpcec.htm` (upstream, CNGSOFT); `github.com/cpcitor/cpcec` (script-generated mirror) | Linux / Windows | Partial — accepts CLI parameters incl. autorun, but no documented PNG-on-frame-N + exit pattern | Rejected for CI (insufficient automation) |
| **libretro `cap32` core** | `github.com/libretro/libretro-cap32` | Anywhere RetroArch runs | Possible via RetroArch `--max-frames` + screenshot-on-exit, but the core is pinned to Caprice32 4.2.0 which **predates** the autocmd / CAP32_* tokens — same upstream codebase, older. Adds a RetroArch dependency for no functional gain over running Caprice32 directly | Considered but rejected |

### 2.2 Headless / scripted screenshot capability evaluation

Only **Caprice32** has documented, repo-source-confirmed support for
the precise pattern RAGE1's regression framework needs:

- **`--autocmd` (`-a`)**: pass a sequence of commands to execute against
  the emulated machine. Repeatable; commands execute after CPC boot.
  (Auto-command machinery added in Caprice32 v4.5.0; v4.4.0 added IPF /
  Plus range / autopause / virtual keyboard / screenshots, **not**
  auto-commands.)
- **`CAP32_DELAY <frames>`**: emulate N frames before processing the
  next autocmd. Added in Caprice32 v4.6.0. This is the exact equivalent
  of JNEXT's `--delayed-screenshot-frames` — wall-clock-independent,
  frame-counted screenshot timing.
- **`CAP32_WAITBREAK`**: pause until the emulated program executes a
  break-like trap, useful for "screenshot when the game settles" without
  hard-coding a frame number. (Caprice32 issue #110 + master source.)
- **`CAP32_SCRNSHOT`**: take a PNG screenshot of the emulated screen.
- **`boot_time`** config parameter: how many frames CPC needs to boot
  before autocmd takes effect — Caprice32 handles boot offsetting
  automatically.
- **Exit-on-completion**: the autocmd sequence can end with `CAP32_EXIT`
  (documented alongside `CAP32_DELAY`, `CAP32_SCRNSHOT`, and
  `CAP32_WAITBREAK` in the Caprice32 issue #110 example). Phase TS2 must
  verify the token still exists in the pinned version, confirm its
  parameterisation, and check whether a combined screenshot-and-exit
  shortcut is offered.

Caprice32 is SDL2-based and can run under `xvfb-run` for true-headless
Docker CI (`xvfb-run caprice32 -a CAP32_DELAY=300 -a CAP32_SCRNSHOT=out.png
-a CAP32_EXIT game.dsk` — sketch). This pattern is exactly analogous to
JNEXT's headless mode.

Caprice32 supports loading `.dsk`, `.cdt`, `.sna`, `.cpr`, `.voc`, and
`.m3u` files natively (libretro core docs; same set in standalone) —
matches the CPC outputs that the RAGE1 build will produce
(`toolchain.md` §4.2).

The libretro `cap32` core is pinned at Caprice32 4.2.0, **before** the
autocmd/screenshot tokens, so going through RetroArch buys nothing.

### 2.3 Recommendation + justification

**Recommendation: Caprice32 v4.6.0 or newer, driven via `--autocmd`,
running under `xvfb-run` in CI.**

Justification:

- It is the **only** CPC emulator in the survey with a
  source-confirmed headless / frame-deterministic / PNG-output path.
  Every other open-source candidate either lacks the screenshot-on-frame
  primitive (Arnold, Xcpc, CPCEC) or is GUI-only (ACE-DL, RVM, Caprice
  Forever).
- The autocmd + `CAP32_DELAY` + `CAP32_SCRNSHOT` pattern is
  **isomorphic** to JNEXT's `--delayed-screenshot-frames` +
  `--delayed-screenshot` flag pair. The regression-script abstraction
  generalises cleanly with no new conceptual machinery.
- Active maintenance: master had a v4.6.0 release on 14 March 2026 with
  the `CAP32_DELAY` improvements specifically motivated by automation
  use cases.
- Open-source (LGPL v2/v3 family); permissively licensed for use as a CI
  tool (we don't link against it, we just run it).
- Linux/macOS/Windows builds. The CI image needs only the Linux build.
- It is the **same** emulator most cpctelera users develop against
  (cpctelera ships Caprice32 as its bundled emulator in
  `cpctelera/tools/`). Aligning our test platform with cpctelera's
  reference emulator reduces "works in the emu, fails on real hardware"
  surface.

Trade-offs accepted:

- **Not the most accurate CPC emulator** in the community — that title
  belongs to ACE-DL / RVM / WinAPE. Pixel-perfect regression against a
  less-accurate emulator means we are testing "what Caprice32 thinks
  the CPC would do" rather than "what a real CPC does". Mitigation: a
  per-platform tolerance policy (§3.4) and an explicit cross-check
  against a second emulator at phase boundaries.
- **SDL2 + Xvfb in Docker**: requires an `xvfb-run` wrapper. This is a
  well-trodden CI pattern but adds one moving part to the image.

Fallback if Caprice32's `--autocmd` machinery proves insufficient
during Phase TS2:

1. Patch Caprice32 to add any missing CAP32_* token (small C++ patch,
   upstreamable).
2. Drop to `arnold` with a Lua/Python wrapper that drives `xdotool` to
   simulate F3 — last-resort and brittle; flagged as Risk R3.

### 2.4 Integration sketch (binary in → PNG out)

The CPC equivalent of the existing JNEXT regression invocation:

```sh
# what regression.sh runs today for ZX (JNEXT):
"$JNEXT" --headless \
    --sd-card "$JNEXT_SD_CARD" \
    --machine "$MACHINE" \
    --load "$test_dir/game.tap" \
    --delayed-screenshot "$out_img" \
    --delayed-screenshot-frames "$DELAY_FRAMES" \
    --delayed-automatic-exit "$exit_delay"

# what regression.sh runs after Phase TS2 for CPC (Caprice32):
xvfb-run -a "$CAPRICE32" \
    --override "screen_filename=$out_img" \
    --autocmd "CAP32_DELAY=$DELAY_FRAMES" \
    --autocmd "CAP32_SCRNSHOT" \
    --autocmd "CAP32_EXIT" \
    "$test_dir/game.dsk"
```

(Exact `--override` key for screenshot path is subject to in-source
confirmation at TS2 implementation time; the `CAP32_EXIT` token is
documented in Caprice32 issue #110 but TS2 will still confirm it remains
in the pinned version. The sketch shows the shape.)

The integration sketch deliberately mirrors the JNEXT call shape so the
regression script can dispatch via a small per-platform helper function
(see §3.2).

---

## 3. Regression framework extension

### 3.1 Per-platform baseline layout

Today each test directory contains one `reference.png`. After the
multi-platform plan, **multiple baselines per test** are required: a
game can target both ZX and CPC from the same source tree (per
`assets.md`'s sibling-overlay model), so each test must declare which
platforms it covers and store a baseline for each.

Two layout options:

**Option A — flat per-platform suffixes**:
```
tests/00regression/<name>/
├── test.conf
├── reference_zx48.png
├── reference_zx128.png
├── reference_cpc464.png
├── reference_cpc6128.png
├── actual_zx48.png      # gitignored
├── actual_cpc464.png    # gitignored
└── diff_<platform>.png  # gitignored
```

**Option B — subdirectory per platform** (chosen):
```
tests/00regression/<name>/
├── test.conf
├── zx48/reference.png
├── zx48/actual.png      # gitignored
├── zx48/diff.png        # gitignored
├── zx128/reference.png
├── cpc464/reference.png
├── cpc6128/reference.png
└── ...
```

We choose **Option B** because:

- **Better scaling with the number of platforms.** 4 platforms × 3
  file types (reference + actual + diff) = 12 top-level files per
  test under Option A; Option B groups them naturally per platform.
- **Clean per-platform `git status` / diff scoping.** Changing a
  CPC baseline only touches `cpc464/`; ZX baselines stay untouched
  in their own subdir. Reviewers can spot per-platform changes at
  a glance.
- **Easier wholesale operations.** `rm -rf tests/00regression/*/cpc464/`
  deletes every CPC baseline in one command; under Option A the
  equivalent is a `find` invocation matching `reference_cpc464.png`.
- **Simpler `.gitignore`.** Per-platform `actual.png` / `diff.png`
  become plain filenames inside the platform subdir; the globs are
  `tests/00regression/*/*/actual.png` and
  `tests/00regression/*/*/diff.png`.
- **Symmetric with the assets-md sibling-tree convention.** The
  project's established per-platform layout pattern
  (`<platform>/game_data/`) already uses subdirectories;
  consistency wins.

Option A (file-name suffix convention, matching
`tools/mem-summary-<engine>-<target>.sh`) was considered and
rejected — the suffix idiom doesn't scale as cleanly with 4+
platforms, and a single test directory ending up with a dozen
`.png` files at the top level becomes hard to eyeball.

The migration of existing `reference.png` files into per-platform
subdirectories happens in Phase TS1-2 below. Per the project-wide
backwards-compat-indefinite policy (README §5.6), the top-level
`reference.png` is **retained indefinitely** as an implicit-zx48
fallback; tests that haven't migrated yet (or that only ever
needed a single ZX baseline) keep working unchanged.

### 3.2 Script changes (`regression.sh`)

The runner becomes platform-aware. Concrete changes:

1. **`test.conf` schema extension**. New required key `PLATFORMS`
   (space-separated list); legacy `MACHINE` becomes per-platform-derived
   (zx48 → 48k, zx128 → 128k, cpc464/664 → cpc464, cpc6128 → cpc6128).
   `DELAY_FRAMES` becomes either a single value (applied to every
   platform) or a per-platform map (e.g. `DELAY_FRAMES_ZX48=150
   DELAY_FRAMES_CPC464=200`). Frame timings differ across emulators —
   the CPC frame rate is 50 Hz like ZX, but cpctelera + AMSDOS boot
   takes more frames than the ZX 48 ROM.

   Backwards-compat: if `PLATFORMS` is absent, default to
   `PLATFORMS="zx48"` and fall back to the historical `MACHINE` field.

2. **Per-test inner loop**. For each platform in `PLATFORMS`:
   - Build the game for that platform:
     `make clean && make build target_game=$TARGET_GAME PLATFORM=$PLATFORM`
     (the `PLATFORM=` knob comes from `toolchain.md` Phase T1).
   - Locate the produced artefact: `game.tap` (zx48/zx128) or
     `game.dsk` (cpc*) or `game.cdt` (also cpc*, but the regression
     framework prefers `.dsk` because it boots more deterministically).
   - Dispatch to the right emulator: a helper function
     `run_emulator_<platform>(artefact, frames, out_png)` that hides
     the JNEXT-vs-Caprice32 difference.
   - Compare against `$PLATFORM/reference.png`.
   - Accumulate pass/fail counts per platform; final report breaks down
     pass/fail by platform.

3. **`--update` mode**. Today refreshes a single `reference.png`;
   becomes per-platform — refreshes `<platform>/reference.png` under
   every selected test, for every platform the test declares, or
   restricted to one platform if `--platform $PLATFORM` is passed.

4. **New CLI filters**: `--platform zx48 minimal_jsp` runs only that
   platform of the named test. Default is all-platforms-all-tests.

5. **Emulator dispatch helpers** (new functions in the script):

   ```bash
   # ZX path — unchanged in shape
   run_emulator_zx48()  { ... JNEXT ... --machine 48k ... }
   run_emulator_zx128() { ... JNEXT ... --machine 128k ... }

   # CPC path — Caprice32
   run_emulator_cpc464() { ... xvfb-run caprice32 -a CAP32_DELAY=... }
   run_emulator_cpc6128() { ... xvfb-run caprice32 --override "model=6128" ... }
   ```

6. **Caprice32 binary discovery**. Mirror the JNEXT discovery
   (`regression.sh:27-37`): probe a small list of candidate paths,
   honour `CAPRICE32` env override, refuse to start if not found.

7. **Tolerance per platform**. The default tolerance is still 0
   (pixel-perfect); but `test.conf` may declare
   `TOLERANCE_CPC=<N>` (overriding `JNEXT_TEST_TOLERANCE` for the
   CPC lane) to acknowledge that emulator-accuracy differences may
   make pixel-perfect CPC regression flaky in practice. See §3.4.

8. **Artefact cleanup**. `<platform>/actual.png`, `<platform>/diff.png`,
   `game.tap`, `game.dsk`, `game.cdt` all added to the test-local
   `.gitignore` (the actual/diff globs become
   `tests/00regression/*/*/actual.png` and
   `tests/00regression/*/*/diff.png`).

### 3.3 First CPC test game (coordination with `gfx.md` / `cpc-renderer.md`)

The first runnable CPC RAGE1 game is `games/minimal_cpc/` — created in
`cpc-renderer.md` Phase R4-3 and `gfx.md` Phase G8-3. It is the
**minimum** game that exercises CPC `gfx_*` init, a sprite, a tile, and
a `gfx_*` flush, with no enemies / no music / no flow rules beyond the
required minimum.

This document does not own that game; it owns its first regression
baseline. Concretely (in Phase TS3 below):

- `tests/00regression/minimal_cpc/` is created with `test.conf`
  declaring `TARGET_GAME=games/minimal_cpc`, `PLATFORMS=cpc6128`,
  `DELAY_FRAMES_CPC6128=<TBD>`.
- A `cpc6128/reference.png` is captured by running the regression
  script with `--update --platform cpc6128 minimal_cpc`.
- The reviewer eyeballs the captured PNG against the expected state of
  the game on a CPC mode-1 screen before committing it.

Because `games/minimal_cpc/` is CPC-only by design (no shared `.gdata`
yet), `PLATFORMS=cpc6128` is the only entry. As `assets.md` Phase A2-3
matures (sibling overlays + auto-conversion of shared assets), the
existing `games/minimal/` will gain a CPC overlay and become a
two-platform test (`PLATFORMS="zx48 cpc6128"`); at that point
`tests/00regression/minimal/` grows a `cpc6128/reference.png`
alongside its existing `zx48/reference.png`, and `minimal_cpc/`
**will be retired in Phase TS6 once the CPC overlay on
`games/minimal/` matures** (see TS6-1).

### 3.4 Tolerance / comparison policy (pixel-exact vs perceptual)

Today the policy is **pixel-perfect**, with a configurable
`JNEXT_TEST_TOLERANCE` env-var override. That works for the ZX side
because JNEXT's rendering of the SP1 / JSP backends is deterministic
across runs and (more importantly) across host CPUs.

For CPC the situation is less clear:

- Caprice32 is **deterministic per-build** — same ROM, same input
  binary, same frame number → same pixels. Pixel-perfect is achievable.
- Caprice32 is **not necessarily deterministic across versions**: minor
  CRTC / Gate Array timing fixes between releases may shift pixels at
  the edges of scan lines. Pinning the Caprice32 version in the CI
  image (§4.2) is therefore mandatory.
- cpctelera's sprite blits, on top of which `gfx_cpctel.c` lives
  (`cpc-renderer.md` §4.2), are byte-deterministic. The pipeline is
  reproducible end-to-end.

Policy:

- **Default tolerance is 0 (pixel-perfect)** on every platform.
- The CI image **pins** specific Caprice32 + JNEXT versions; bumping
  them is a deliberate maintenance event that may require updating
  baselines.
- Per-test `test.conf` may set `TOLERANCE_<platform>=<int>` for
  acknowledged-flaky tests (e.g. a screen with animated palette cycles
  where a frame race is unavoidable). This must be reviewed during
  baseline commit.
- No perceptual-similarity comparison (`compare -metric SSIM` or
  similar). Stick with `-metric AE` (absolute error count, pixel-exact)
  because:
  - It detects real engine bugs that perceptual metrics would mask
    (one-pixel-off sprite movement, off-by-one BTile placement).
  - It keeps the policy line simple — "any pixel difference is a
    failure unless explicitly marked".

The corollary, recorded as an open question (§8 OQ-TS3), is whether the
CPC tolerance default should rise to a small non-zero value during the
early phases (TS3, TS4) to absorb cpctelera-version churn. The
recommendation is **no**: keep the default at 0 and update baselines
deliberately when cpctelera is bumped.

### 3.5 ZX byte-identical invariant interaction

`assets.md` describes an invariant: **the ZX TAP output of a game must
be byte-identical before and after introducing the sibling-tree overlay
machinery**, as long as no overlay actually adds CPC content. This is
verified by a byte-compare of `game.tap` against a pre-overlay
checked-in baseline.

**Determinism prerequisite.** The TAP-byte invariant assumes the
build pipeline is deterministic — same sources → same bytes, every
time. In principle this holds, but `banktool.pl` / `loadertool.pl`'s
bank-packing has not been audited for determinism (e.g. iteration
order of Perl hashes when assigning datasets / codesets to banks).
**If a TAP-byte mismatch surfaces in practice, the first response is
to investigate and fix any non-determinism in tooling**, not to
treat the mismatch as a legitimate regression. Non-determinism in
the build is a bug worth fixing; the invariant is the contract that
forces that bug to surface. Phase TS4 below adds a determinism
pre-flight check (rebuild N times, compare SHAs) so the invariant
gains a stable foundation before being wired into CI as a gate.


This invariant complements the screenshot regression: screenshot regression
proves visual behaviour; the TAP-byte invariant proves no compiled-output
drift. The testing framework should run **both** at phase boundaries.

Concretely the regression script grows a TAP-byte mode (Phase TS4):

```bash
bash tests/00regression/regression.sh --tap-byte-check
```

Which after each build runs `sha256sum` on the produced `game.tap` and
compares it to a checked-in `zx48/reference.tap.sha256` (or similar)
under the test's per-platform subdir. This is **distinct from** the
screenshot test.

The two knobs play distinct roles:

- **`--tap-byte-check` (CLI switch)** — enables the byte-check **mode**
  globally for the run. Without it, `regression.sh` performs only
  screenshot regression, exactly as today.
- **`TAP_BYTE_CHECK_<platform>=true` (per-test flag in `test.conf`)** —
  the **per-test opt-in** that selects which tests participate when the
  mode is enabled. A test without this flag is silently skipped by the
  byte-check pass even when `--tap-byte-check` is on the command line.

So `--tap-byte-check` turns the mode on; `TAP_BYTE_CHECK_<platform>=true`
gates which tests it applies to. Both must be present for a given test
to be byte-checked on a given platform.

Owned conceptually by `assets.md`; orchestrated by this document.

---

## 4. CI matrix design

### 4.1 Per-game × per-platform table

The matrix is "every game × every platform it opts into". Today's
games and their post-multi-platform-plan target set (proposed, to be
refined by `assets.md` per-game during Phase A2):

| Game                | zx48 | zx128 | cpc464 | cpc6128 | Notes                                                                |
|---------------------|------|-------|--------|---------|----------------------------------------------------------------------|
| `minimal`           | ✓    | —     | ✓      | ✓       | core happy-path; "the" reference (cpc464 binary also runs on CPC664) |
| `minimal_jsp`       | ✓    | —     | —      | —       | ZX-only — JSP is a ZX sprite library; no CPC analogue                |
| `default`           | —    | ✓     | —      | ✓       | bigger demo game; 128/6128 only                                      |
| `default_jsp`       | —    | ✓     | —      | —       | ZX-128 only — JSP                                                    |
| `blobs`             | ✓    | —     | ✓      | ✓       | enemy interactions; good for collision tests                         |
| `crumbs`            | ✓    | —     | —      | ✓       | item-pickup logic                                                    |
| `mapgen`            | ✓    | —     | ✓      | ✓       | exercises mapgen.pl + btilegen.pl pipeline                           |
| `damage_mode`       | ✓    | —     | —      | —       | ZX-only feature, may port later                                      |
| `get_weapon`        | ✓    | —     | —      | —       | ZX-only feature, may port later                                      |
| `monochrome`        | ✓    | —     | —      | ✓       | colour-model edge case; CPC mode-1 monochrome equivalent useful      |
| `vortex2`           | —    | ✓     | —      | —       | ZX-128 specific (banking-heavy)                                      |
| `sub_bufs_48`       | ✓    | —     | —      | —       | SUB infrastructure test, ZX                                          |
| `sub_bufs_128`      | —    | ✓     | —      | ✓       | SUB + banking, CPC analogue useful but late                          |
| `minimal_cpc` (new) | —    | —     | ✓      | ✓       | first CPC RAGE1 game; created by `cpc-renderer.md` R4                |
| `cpc_hello` (new)   | —    | —     | ✓      | ✓       | toolchain smoke from `toolchain.md` T2-10 — engine-stub level        |
| `00cpc-compile-test` (new) | — | — | ✓ | ✓ | gfx.md G7 compile-only target; **not** a regression test            |

CPC664 is not a separate column because it is a runtime target of
the `cpc464` build, not a build identity (see [README.md §1](README.md)
and OQ-TS9 below).

A "✓" means: that game is in the build matrix for that platform; CI
attempts to build it and (if a baseline exists) screenshot-regress it.

Some entries are aspirational — e.g. `monochrome` on CPC requires
deciding what the CPC monochrome equivalent *is* (a one-pen mode-2
build? a forced palette mapping?). Owned by `assets.md` per-game
during Phase A4 / Phase A5.

**Compile-only entries** (`00cpc-compile-test`): these games build but
their binary is not expected to run meaningfully — they exist solely
to exercise the C compilation surface (`gfx.md` Phase G7-4). They are
**excluded from screenshot regression**. CI must distinguish "build
expected to produce a runnable artefact" from "build expected only to
compile clean". Enforced by a `RUNNABLE=false` (or absent `PLATFORMS`)
in their `test.conf`.

The matrix is intentionally **sparse** at first — not every game runs
on every platform — to make CPC bring-up tractable. Phase TS6 below
expands coverage iteratively.

### 4.2 Docker image additions

The `rage1-z88dk` Docker image (`docker/Dockerfile`) needs the
following additions to support CPC build + regression. The Dockerfile
edits themselves are owned by `toolchain.md` Phase T0-5 and T2-9; this
document captures the **list of what must be installed** for the
testing side.

| Tool | Purpose | When added | Owner doc |
|---|---|---|---|
| `2cdt` | CDT generation (CPC tape image) | Phase TS2 / T0-5 | toolchain.md §5 |
| `iDSK` (optional) | DSK manipulation; cpctelera bundles it | Phase TS2 / T0-5 | toolchain.md |
| cpctelera asset tools (`cpct_img2tileset`, `Img2CPC`) | PNG → CPC pixel data | Phase TS2 / R3-1 | cpc-renderer.md §5 |
| **Caprice32** ≥ v4.6.0 | CPC emulator for headless screenshot regression | Phase TS2 | **this doc** |
| **`xvfb-run` / `xvfb`** | Virtual X server for Caprice32 in Docker | Phase TS2 | **this doc** |
| **ImageMagick `compare`** | Required by `regression.sh:68-71`; not currently installed in the image — must be added in TS3 | Phase TS3 | **this doc** |
| **JNEXT binary + SD-card image** | ZX screenshot regression in CI (today only run locally) | Phase TS3 | **this doc** |
| z88dk **version bump** | Verify `+cpc` works at the pinned v2.3, possibly bump to v2.4+ | Phase T0 | toolchain.md §5 |

The list of mandatory additions just for this document's scope (CI
running screenshot regression) is:

- Caprice32 v4.6.0+ — pinned by version, built from source in the
  Dockerfile (or installed via the snap if reproducible).
- `xvfb-run` + Xvfb dependencies.
- ImageMagick `compare`.
- A JNEXT binary baked into the image (or, alternatively, downloaded
  from a release artefact at CI-job time — see §4.3).
- A NextZXOS SD-card image consumed by JNEXT.

Risk: image size. Adding all this plus cpctelera tooling could push
the image from ~1 GB to several GB. `toolchain.md` Risk R-T8 notes
this; mitigation is to **split the image into tagged variants**:

- `zxjogv/rage1-z88dk:build` — build tools only (z88dk + bas2tap +
  cpctelera asset tools + 2cdt). Used by `build-test-games.yaml`.
- `zxjogv/rage1-z88dk:test` — adds JNEXT, Caprice32, Xvfb, ImageMagick,
  SD-card image. Used by a new `regression.yaml` workflow.

Split decided in Phase TS2-3 (and toolchain.md T0-5). The `:latest` tag becomes an alias for
`:test` (the superset) for developer convenience.

### 4.3 Build-vs-regression split per CI job

Today there is one CI workflow (`build-test-games.yaml`) that runs
`make all-test-builds`. After the multi-platform plan we want
explicitly **separated** workflows:

1. **`build-test-games.yaml`** (existing, evolved). Builds every game ×
   every platform-it-opts-into. Fast, no emulator needed.
   `make all-test-builds` is extended (per toolchain.md §3.2) to drive
   `PLATFORM=X` for each game's declared platform set. The job uses
   the `:build` image variant.

2. **`regression.yaml`** (new, added in Phase TS3). Runs
   `tests/00regression/regression.sh` against every test that has a
   baseline. Uses the `:test` image variant. Slower; runs per PR and
   on master push.

3. **`build-z88dk-docker.yaml`** (existing, evolved). Builds the
   image. Triggers on changes to `docker/`. After splitting, the
   workflow builds **both** `:build` and `:test` variants from the
   same Dockerfile (using build args / multi-stage builds).

A matrix-style strategy inside `build-test-games.yaml` is recommended
to make per-platform failures attributable (per `toolchain.md` §5):

```yaml
strategy:
  fail-fast: false
  matrix:
    target_group: [zx, cpc]
steps:
  - run: cd /src/rage1 && make all-test-builds-${{ matrix.target_group }}
```

Where `make all-test-builds-zx` / `make all-test-builds-cpc` are new
filter targets (defined in toolchain.md §3.4). This makes "CPC build
broken" and "ZX build broken" appear as separate red checks in PRs.

For `regression.yaml`, the matrix is per-platform similarly:

```yaml
strategy:
  matrix:
    platform: [zx48, zx128, cpc464, cpc6128]
steps:
  - run: bash tests/00regression/regression.sh --platform ${{ matrix.platform }}
```

This shape makes baseline failures cleanly attributable to a platform.

---

## 5. Memory tests + per-platform mem-summary scripts

The current `make mem` target dispatches to a shell script named by
`<gfx_backend>-<target>`: e.g. `tools/mem-summary-sp1-48.sh`,
`tools/mem-summary-jsp-128.sh` (`Makefile.common:314-315`).

After the multi-platform plan the dimension expands. The naming scheme
becomes `tools/mem-summary-<gfx_backend>-<platform>.sh`:

| Existing | New (renamed) |
|---|---|
| `mem-summary-sp1-48.sh` | `mem-summary-sp1-zx48.sh` |
| `mem-summary-sp1-128.sh` | `mem-summary-sp1-zx128.sh` |
| `mem-summary-jsp-48.sh` | `mem-summary-jsp-zx48.sh` |
| `mem-summary-jsp-128.sh` | `mem-summary-jsp-zx128.sh` |
| (new) | `mem-summary-cpctel-cpc464.sh` (also serves CPC664 — same memory map) |
| (new) | `mem-summary-cpctel-cpc6128.sh` |

The CPC variants report:

- Code section size (`main.bin` size, sections from `.map`).
- Per-bank size on CPC6128 (analogous to ZX128's per-bank section
  report).
- Free space below the cpctelera-managed firmware reserve.
- Per-dataset / per-codeset / per-SUB size (mirror of the ZX128
  layout from `Makefile-128:51-57` via `z88dk-z80nm`).

The scripts share the bulk of their logic with the ZX equivalents
(both run `z88dk-z80nm` over a `.map` and `awk` the result); the
deltas are the memory-region layout constants. Concretely we should
**refactor**: one script `tools/mem-summary.sh` parameterised by
`<gfx_backend>` and `<platform>`, with a small per-platform region
table — that's the right shape but introducing a refactor adds churn.
The phased plan below picks the **simpler "one script per combination"**
path matching today's pattern, deferring refactor to a later cleanup.

Tied to `toolchain.md` Phase T1-9 (Makefile variable rename) and
Phase T3-1 (CPC banked memory model) and `banking.md` (region
definitions).

Phase-exit criterion for the per-platform mem tests:

- `make mem PLATFORM=cpc6128` works against a built `games/minimal_cpc/`
  and produces a coherent report.
- The four ZX-equivalent scripts have been renamed without behaviour
  change.

---

## 6. Phased work plan

Each phase ends with the parent-plan invariant restored: `make
all-test-builds` green for ZX and `tests/00regression/` (ZX subset)
green. Mid-phase regressions are tolerable. Phase IDs use the `TS`
prefix.

### Phase TS1 — Backfill ZX regression coverage (preparatory)

**Goal**: before any structural changes to the framework or any CPC
work, give the existing ZX test games a baseline screenshot apiece so
the rest of the plan has something to regress against. This is the
single most leveraged piece of work in the document — every later
phase relies on these baselines to detect ZX regressions.

- **TS1-1** Add baseline screenshots for every existing `games/*` test
  game. For each game in
  `blobs, crumbs, damage_mode, default, default_jsp, get_weapon, mapgen,
  minimal, minimal_jsp, monochrome, sub_bufs_128, sub_bufs_48, vortex2`
  (13 games; `minimal` already has a baseline so the bulk of TS1-1's
  work is the other 12):
  - Create `tests/00regression/<name>/test.conf` with the right
    `TARGET_GAME`, `MACHINE` (from the game's own `.gdata` `ZX_TARGET`),
    and a `DELAY_FRAMES` derived per the table in
    `tests/00regression/README.md:67-81`.
  - Run `bash tests/00regression/regression.sh --update <name>`.
  - **Eyeball each `reference.png`** — confirm it shows the game in
    the expected state, not `LOAD ""` mid-boot or a transient frame.
  - Commit `test.conf` + `reference.png` together, one game per commit
    for easy review.
- **TS1-2** Decide game-by-game whether the captured baseline is
  meaningful. Some games (e.g. `damage_mode`) may not have a
  deterministic post-boot screen; for those, either find a stable
  frame (use `DELAY_FRAMES` to land before any animation), or mark
  them with `SKIP_REGRESSION=true` in `test.conf` for now and revisit
  later. Document each `SKIP_REGRESSION` decision with a comment in
  the conf file.
- **TS1-3** Wire `regression.sh` into a local-developer convenience
  target: `make regression` runs `bash tests/00regression/regression.sh`.
  Update `Makefile` and `Makefile.common` accordingly. (Mechanics
  trivial; the visibility improvement is the point.)
- **TS1-4** Document the workflow in `tests/00regression/README.md` —
  expand the "Adding a new test" section to cover what to do when the
  baseline is non-deterministic. Add a short "When to update
  baselines" section.
- **Phase-exit criteria**:
  - At least 11 of the 13 existing test games (>=80%) have committed
    `reference.png` baselines. This matches the >=80% coverage gate in
    Risk R7's mitigation.
  - `bash tests/00regression/regression.sh` exits 0 on master.
  - `make regression` is documented.
  - All test games still build via `make all-test-builds`.

### Phase TS2 — Add CPC emulator to the local environment + Docker image

**Goal**: get a working Caprice32 + Xvfb stack into the developer
environment **and** the CI image. No RAGE1 code changes; the test is
"can a hand-built CPC binary be screenshotted by the framework".
Coordinated with `toolchain.md` Phase T0 (z88dk `+cpc` spike) and
`cpc-renderer.md` Phase R2 (cpctelera PoC).

- **TS2-1** Locally install Caprice32 v4.6.0+ on the developer host.
  Verify by hand that `caprice32 -a CAP32_DELAY=300 -a CAP32_SCRNSHOT
  -a CAP32_EXIT <some.dsk>` produces a PNG with no user interaction.
  Document the install + invocation in
  `tests/00regression/README.md` under a new "CPC emulator" section.
- **TS2-2** Verify that `CAP32_SCRNSHOT`, `CAP32_DELAY`,
  `CAP32_WAITBREAK`, and `CAP32_EXIT` (all documented in Caprice32
  issue #110) still exist in the pinned Caprice32 version, confirm
  their exact parameterisation (e.g. how `CAP32_DELAY` takes its
  frame-count argument), and check whether the pinned version offers
  a combined screenshot-and-exit shortcut. Caprice32 master source is
  the authoritative reference; `man cap32` is currently out of date.
  Record the verified syntax in `tests/00regression/README.md`.
- **TS2-3** Add Caprice32 + Xvfb + ImageMagick `compare` to the
  `rage1-z88dk` Dockerfile, as a new build stage (multi-stage
  Dockerfile) tagged `:test`. The existing single image becomes
  `:build`. Update `build-z88dk-docker.yaml` to build and push both
  tags. **Owned mechanically by `toolchain.md` Phase T0-5**; this
  document specifies the test-side ingredients.
- **TS2-4** Verify Caprice32 runs headless under Xvfb inside the
  `:test` image: build the image, run `docker run --rm -it ... xvfb-run
  caprice32 -V`. Iterate until the binary starts cleanly.
- **TS2-5** Smoke-test end-to-end: take the cpctelera PoC binary
  produced by `cpc-renderer.md` Phase R2 (or a fresh trivial CPC
  hello-world .dsk if R2 hasn't landed), feed it to Caprice32 with the
  autocmd sequence, get a PNG. Commit the PNG as an interim artefact
  under `tests/00regression/cpc-emulator-smoke/` to prove the chain
  works. (This test is **not** a RAGE1 regression test; it is an
  emulator-infrastructure test, and will be removed at phase exit
  after TS3 ships the real first CPC regression.)
- **Phase-exit criteria**:
  - Caprice32 runs headless in CI image, takes a screenshot of a
    user-provided `.dsk`, exits 0.
  - The `:build` and `:test` image variants exist, are pushed, and CI
    workflows reference them by tag.
  - ZX regression unchanged, still green.

### Phase TS3 — Extend `regression.sh` for multi-platform; first CPC baseline

**Goal**: rewrite the regression runner to be platform-aware, dispatch
to JNEXT vs Caprice32 per test, and land the first CPC baseline for
`games/minimal_cpc/`. Depends on `gfx.md` G8 / `cpc-renderer.md` R4 /
`toolchain.md` T2 (which together produce the first runnable CPC RAGE1
binary).

- **TS3-1** Extend `tests/00regression/regression.sh` for the
  per-platform schema (§3.1, §3.2). Specifically:
  - New `PLATFORMS` field in `test.conf` (defaults to `zx48` if
    absent).
  - Per-platform inner loop over the test.
  - Emulator dispatch helpers (`run_emulator_<platform>`).
  - Per-platform reference baselines:
    `<test>/<platform>/reference.png`.
  - CLI: `--platform <name>` filter.
  - Move existing `reference.png` files to `<test>/zx48/reference.png`
    in every test directory checked in during TS1.
  - Keep backwards-compat **indefinitely** (README §5.6): if
    top-level `reference.png` exists and `zx48/reference.png` does
    not, use the former as the implicit zx48 baseline and continue
    to support it for tests that haven't migrated.
- **TS3-2** Update the `:test` Docker image and `regression.yaml`
  workflow (Phase TS2 leftover): create `regression.yaml` (new
  workflow) that runs `bash tests/00regression/regression.sh` after
  building. Triggers on PR and master push. Uses `:test` image. Runs
  per-platform matrix as in §4.3.
- **TS3-3** Add `tests/00regression/minimal_cpc/`:
  - `test.conf` with `TARGET_GAME=games/minimal_cpc`,
    `PLATFORMS=cpc6128`, suitable `DELAY_FRAMES_CPC6128` (probably
    600+; cpctelera + AMSDOS boot is slower than ZX 48 ROM — tune
    empirically).
  - Capture `cpc6128/reference.png` via `--update`.
  - Eyeball it: it must show the `games/minimal_cpc/` hero + tile.
- **TS3-4** Confirm `regression.yaml` is green on master with the new
  CPC test.
- **TS3-5** Add CPC tolerance default and `TOLERANCE_<platform>` per
  `test.conf` per §3.4. Default stays 0; the knob exists for
  per-test acknowledgement.
- **TS3-6** Delete the interim `tests/00regression/cpc-emulator-smoke/`
  from TS2-5.
- **Phase-exit criteria**:
  - `bash tests/00regression/regression.sh` runs every ZX baseline
    and the one CPC baseline, all green.
  - `regression.yaml` CI workflow is green on master.
  - Every moved `zx48/reference.png` matches its predecessor
    `reference.png` byte-for-byte (we verify via git history).
  - `games/minimal_cpc/` has a committed baseline.

### Phase TS4 — TAP-byte invariant for ZX + multi-platform `make mem`

**Goal**: add the byte-identical TAP invariant (per `assets.md`) and
generalise `make mem` to per-platform scripts.

- **TS4-1a** **Determinism pre-flight** (per §3.5). Before wiring
  `--tap-byte-check` into CI as a gate, verify the build pipeline
  is deterministic on a stable source tree: rebuild N times (e.g.
  5), `sha256sum` each `game.tap`, confirm all SHAs match. If any
  mismatch surfaces, file a determinism bug (likely `banktool.pl`
  hash-iteration / map-ordering — see banking.md) and **block
  TAP-byte mode** until the tooling fix lands. This makes the
  invariant land on a stable foundation.
- **TS4-1** Add `--tap-byte-check` mode to `regression.sh` per §3.5.
  Per test, after building, compute `sha256sum game.tap` and compare
  to a checked-in `zx48/reference.tap.sha256`. The mode is gated by
  the existence of the reference hash file AND by TS4-1a's
  determinism pre-flight passing.
- **TS4-2** Land the TAP-byte hashes for every ZX test that has a
  baseline today. (Some games' TAPs may not be byte-stable due to
  timestamp embedding or similar; investigate per-game and only commit
  the hash for the deterministic ones.)
- **TS4-3** Rename `tools/mem-summary-{sp1,jsp}-{48,128}.sh` to
  `tools/mem-summary-{sp1,jsp}-zx{48,128}.sh`. Keep one-line
  forwarding stubs at the old names **indefinitely** per the
  project-wide backwards-compat policy (README §5.6) — silent
  acceptance, no deprecation banner. Update `Makefile.common:315`
  accordingly.
- **TS4-4** Add `tools/mem-summary-cpctel-cpc464.sh` and
  `tools/mem-summary-cpctel-cpc6128.sh`, modelled on the ZX equivalents
  but with CPC memory-region constants. The CPC464 script also
  applies to CPC664 (memory-identical); no separate file needed.
- **TS4-5** Wire CI to optionally run `make mem` per platform and
  publish the report as a build artefact (no pass/fail gate at this
  phase; informational).
- **Phase-exit criteria**:
  - `make mem PLATFORM=cpc6128` works.
  - Every existing ZX game with a baseline has a TAP-byte hash where
    feasible.
  - `regression.yaml` runs both screenshot and TAP-byte modes;
    failures attribute correctly.

### Phase TS5 — CI matrix expansion (sparse → full)

**Goal**: bring more games into per-platform CI coverage as
`assets.md`'s sibling-overlay machinery (Phase A2-A4) lands.

- **TS5-1** For each game in the §4.1 table marked with a ✓ in a
  CPC column, once `assets.md` has produced the CPC overlay for that
  game and the CPC build is at least compile-clean, add the matching
  `PLATFORMS=<...>` entry to its `test.conf` and capture its
  per-platform baseline.
- **TS5-2** Identify which ZX-only games are "structurally CPC-able"
  vs "feature-locked to ZX" (e.g. `damage_mode` may be portable;
  `default_jsp` is JSP-only and stays ZX). Document the decision per
  game with a `PORTABILITY` comment in its `Game.gdata` (or a sibling
  doc).
- **TS5-3** Phased rollout per game. Each game brought up follows:
  - Add CPC overlay (owned by `assets.md`).
  - Verify CPC build compiles and runs (developer eyeballs in
    Caprice32 once).
  - Capture baseline; commit; CI now regresses it.
- **TS5-4** Add `--platform <name>` matrix expansion to
  `regression.yaml` per §4.3.
- **Phase-exit criteria**:
  - At least 5 distinct games have CPC baselines.
  - The CI matrix attributes per-platform failures cleanly.
  - The §4.1 table is updated in this document to reflect actual
    coverage.

### Phase TS6 — Convergence: retire CPC-only test stubs; harden

**Goal**: tidy up after the bring-up.

- **TS6-1** As `games/minimal_cpc/` becomes redundant with
  `games/minimal` (CPC-overlay) — i.e. once `assets.md` Phase A2
  matures and `games/minimal/` can produce both ZX and CPC binaries
  from one `.gdata` set — retire `games/minimal_cpc/`. Move its CPC
  baseline into `tests/00regression/minimal/cpc6128/reference.png`.
  Delete the stub game directory.
- **TS6-2** Same for `games/cpc-hello/` (created by `toolchain.md`
  T2-10) once the toolchain Makefile rewrite settles.
- **TS6-3** Same for `games/00cpc-compile-test/` (created by `gfx.md`
  G7-4) once a real CPC test game covers the same compilation surface
  and more.
- **TS6-4** Add a "tolerance budget" review: per `regression.yaml`
  run, summarise tests with non-zero tolerances and report drift.
  Goal: zero non-zero tolerances in steady state.
- **TS6-5** Cross-emulator sanity check (manual, one-off at phase
  exit). Run the CPC baselines through ACE-DL or RVM by hand; spot-
  check that the rendered output matches Caprice32. Document any
  diffs. This is the corollary to §2.3's accepted trade-off ("we test
  against one emulator's idea of CPC"). If a baseline differs
  *significantly* across emulators we have a real bug; if it differs
  in pixels-at-the-edge it confirms tolerance policy is right.
- **Phase-exit criteria**:
  - Stub CPC-only test games are retired in favour of overlay-based
    tests.
  - The CI matrix is the §4.1 table (or its evolved successor).
  - `tests/00regression/` has between 8 and 13 tests, each with
    appropriate per-platform baselines.

---

## 7. Risks

- **R1 — Caprice32 autocmd token spelling / behaviour drifts across
  versions**.  
  *Impact*: TS2's hand-verified autocmd sequence breaks on a later
  Caprice32 release.  
  *Mitigation*: pin Caprice32 version in the `:test` Docker image
  (Phase TS2-3). Treat bumps as deliberate maintenance events that
  may require updating baselines and possibly the autocmd sequence.
  Cross-link the pinned version in `tests/00regression/README.md`.

- **R2 — Caprice32 misses the headless screenshot use case in a future
  release**.  
  *Impact*: emulator-driven CI fails entirely.  
  *Mitigation*: pin a version we know works (TS2-3). If upstream
  removes the capability, fork: Caprice32 is open-source and the
  autocmd patch surface is small. Worst case, fall back to
  `xdotool`-driven F3 screenshots in a GUI session (brittle but
  workable).

- **R3 — Caprice32 + Xvfb instability under load in Docker**.  
  *Impact*: flaky CI on parallel runs.  
  *Mitigation*: use `xvfb-run -a` (auto-allocates display number);
  configure Xvfb screen size to a fixed 800×600; pin SDL2 version in
  the image (already implicit since the SDL2 install pulls from
  Fedora repos at image-build time — consider pinning the Fedora
  release).

- **R4 — JNEXT in CI requires NextZXOS SD-card image distribution**.  
  *Impact*: licensing / hosting question for the SD-card image.  
  *Mitigation*: confirm distribution rights of the NextZXOS image
  (the `1gb-fat32fix.img` file). If permitted, bake into the `:test`
  Docker image; if not, fetch from a known URL at workflow-start time
  via the workflow checkout. The JNEXT project itself is open source.

- **R5 — Per-platform baselines proliferate to thousands of PNGs**.  
  *Impact*: repo size growth; review cost.  
  *Mitigation*: keep the §4.1 matrix **sparse** by intent — not every
  game runs on every platform. Use Git LFS only if total PNG size
  exceeds ~50 MB at steady state (each PNG is 1-5 KB; 100 baselines
  is ~500 KB — under threshold).

- **R6 — CPC frame timing causes flakiness**.  
  *Impact*: CPC tests fail intermittently because cpctelera + AMSDOS
  boot takes a variable number of frames depending on bus state on
  reset.  
  *Mitigation*: prefer `CAP32_WAITBREAK` (wait for the emulated
  program to hit a known break/trap) over `CAP32_DELAY` for tests
  where boot timing is variable. Engine-side support: emit a known
  trap instruction (e.g. `RST $38` then a magic byte) in
  `gfx_cpctel.c`'s post-init path that Caprice32 can wait on. Coordinate
  with `gfx.md` Phase G8.

- **R7 — Mid-phase ZX regression goes unnoticed because not every
  game has a baseline**.  
  *Impact*: subtle ZX rendering regression slips into a phase exit
  that nominally passes.  
  *Mitigation*: TS1 is explicitly front-loaded for this reason. The
  goal is high baseline coverage **before** any HAL refactor (Phases
  G2, G3, etc.) begins. The plan reviewer should resist allowing
  Phase G-* to start before TS1-1/TS1-2 reach >=80% game coverage —
  concretely, at least 11 of the 13 existing test games, matching
  TS1's phase-exit criterion.

- **R8 — TAP-byte invariant impossible to maintain through HAL
  refactors**.  
  *Impact*: TS4-1 mode fails as soon as `gfx.md` G2 rename causes a
  one-byte difference in compiled output, despite no visual
  regression.  
  *Mitigation*: TAP-byte mode is gated per-test and primarily
  intended to validate **the asset-pipeline refactor** in
  `assets.md` (which explicitly aims for byte-identical TAPs).
  HAL refactors will normally invalidate TAP hashes; they get
  refreshed alongside the HAL change. The screenshot regression
  remains the primary correctness gate; TAP-byte is the asset-side
  belt-and-braces.

- **R9 — Image size growth blocks PR throughput**.  
  *Impact*: `:test` image is many GB; CI cold-start becomes slow.  
  *Mitigation*: the `:build` vs `:test` split (TS2-3) keeps the
  fast-path PR build on the smaller image; only the regression job
  pulls `:test`. Layer caching applies. Re-evaluate at end of TS3.

- **R10 — Caprice32 is not the most accurate CPC emulator** (see
  §2.3 accepted trade-offs).  
  *Impact*: a bug that Caprice32 masks will not be caught by
  regression but might appear on real hardware.  
  *Mitigation*: TS6-5 builds in a one-off manual cross-emulator
  sanity check per phase. Encourage the team to run the binaries on
  real hardware periodically (developer-driven, not CI).

- **R11 — `make all-test-builds` is not parallel-safe**.  
  *Impact*: matrix expansion in CI (§4.3) requires running multiple
  build invocations concurrently per worker; with shared `game.tap`
  in the project root this conflicts.  
  *Mitigation*: short-term, the CI matrix uses **separate runner
  containers per platform** (one runner = one container = one shared
  filesystem with no concurrent builds). Long-term, refactor the
  build to write artefacts into per-platform output directories
  (owned by `toolchain.md`, currently filed as an implicit TODO).

---

## 8. Open Questions

- **OQ-TS1** — Caprice32 autocmd token availability in the pinned
  version. **Deferred (2026-05-26)**: do not pre-emptively
  investigate. If TS2-2 (or any later phase) finds a needed token
  has been removed or renamed in the pinned Caprice32, handle the
  problem when it surfaces — patch upstream, fork, or accept the
  limitation depending on the specifics. No work scheduled now.

- **OQ-TS2** ✅ — CI `regression.yaml` workflow gating.
  **Resolved (2026-05-26)**: **gate PR merges by default**, with
  a `[skip-regression]` PR-title escape hatch for emergency fixes.

- **OQ-TS3** ✅ — CPC tolerance default. **Resolved (2026-05-26)**:
  **default tolerance 0 (pixel-perfect) on CPC**, same as ZX. The
  per-test `TOLERANCE_<platform>` knob exists for explicit
  per-test acknowledgement when a CPC test genuinely needs slack.

- **OQ-TS4** ✅ — NextZXOS SD-card image distribution.
  **Resolved (2026-05-26)**: **download `nextzxos-1gb-fat32fix.img`
  at CI start time** from a known URL rather than redistributing
  it inside our Docker image. Sidesteps the licensing question.
  TS2-3 records the download URL.

- **OQ-TS5** ✅ — Caprice32 binary source. **Resolved (2026-05-26)**:
  **option (a) — build from source in the Dockerfile**, pinning a
  specific commit / tag. Gives us version control and avoids
  package-availability surprises.

- **OQ-TS6** ✅ — Cycle-deterministic capture. **Resolved
  (2026-05-26): explore in the future.** Not blocking for Phase 1;
  flagged as a future research item once Phase 1 is stable. Today's
  frame-N capture is sufficient for the screenshot regression
  contract.

- **OQ-TS7** ✅ — Mapgen / btilegen test coverage on CPC.
  **Resolved (2026-05-26)**: **handle via the existing overlay
  machinery; no separate `games/cpc-mapgen` analogue is needed.**
  `games/mapgen` gains a CPC overlay through the standard
  `assets.md` sibling-tree mechanism when `tools/mapgen.pl` /
  `tools/btilegen.pl` learn to emit CPC-shaped outputs. The
  regression test grows a `cpc6128/reference.png` alongside the
  ZX baseline at that point. No new test directory required.

- **OQ-TS8** ✅ — `make run-cpc`. **Resolved (2026-05-26)**:
  **yes, add `make run-cpc`** (Caprice32 GUI) for developer
  interactive testing, symmetric with `make run` (FUSE) and
  `make run-jnext` (JNEXT). One-line recipe. Implementation owned
  by `toolchain.md`.

- **OQ-TS9 — CPC664 distinct testing**.
  Phase 1 treats CPC664 as a *runtime target* of the CPC464 build,
  not as a separate `PLATFORM` identity (per `toolchain.md` §3.1
  and `README.md` §1). The OQ remains: do we want any explicit
  CPC664-on-emulator smoke testing in CI to catch a firmware-boot
  divergence the cpc464 build might trip over? Recommend: no
  separate baselines in Phase 1 — add CPC664 smoke testing only if
  a 664-specific bug surfaces; cross-link to `toolchain.md` R-T9.

- **OQ-TS10** ✅ — Image variant split versus single image.
  **Resolved (2026-05-26)**: **split `:build` / `:test` Docker
  image variants** per §4.2. Saves ~hundreds of MB of pull time
  per PR build job; the slightly more complex multi-stage
  Dockerfile is acceptable.

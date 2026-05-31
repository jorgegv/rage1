# Caprice32 Automation & Scripting Guide

## What this guide is about

This guide is written for **CPC game and software developers** who want to use
Caprice32 as an **automated testing tool**. The goal is to let you launch the
emulator from a script or CI pipeline, drive it without touching the keyboard,
run your program, capture a result (a screenshot or a printer dump), and exit —
all unattended and repeatably.

It is **not** a guide to interactive use of the emulator (for that, run `cap32`
and press F1, or read the [man page](doc/man.html)), and it does **not** describe
how the feature is implemented inside Caprice. Everything here is about *what you
type on the command line* and *what you get back*, so you can wire Caprice into a
`make test`, a shell script, or a GitHub Actions job.

If you just want the shape of it, here is a complete, self-contained test:

```bash
cap32 -c test.cfg \
      -a 'run"mygame' \
      -a CAP32_WAITBREAK \
      -a CAP32_SCRNSHOT \
      -a CAP32_EXIT \
      mygame.dsk
```

This boots the CPC, types `RUN"MYGAME` + ENTER, waits until the program returns
to BASIC, takes a screenshot, and quits. The rest of this document explains every
piece of that and the options around it.

---

## 1. The core idea: `-a` / `--autocmd`

The whole automation feature is driven by one repeatable command-line option:

```
-a <command>      (or --autocmd=<command>)
```

Each `-a` you pass is a *step* in a script that runs automatically as soon as the
emulator starts. A step is **one of two things**:

1. **Text to type into the emulated CPC** — e.g. `-a 'run"mygame'` types those
   characters as if you were at the CPC keyboard.
2. **An emulator command** — e.g. `-a CAP32_SCRNSHOT` tells Caprice itself to do
   something (take a screenshot, quit, wait, reset…). These all start with
   `CAP32_`.

You can pass as many `-a` options as you like; they execute in order, left to right.

### ENTER is added for you

**Every `-a` step automatically presses ENTER at the end.** So:

```bash
-a 'mode 1' -a 'print "hello"'
```

types `MODE 1` ⏎ then `PRINT "HELLO"` ⏎. You do **not** add a trailing newline
yourself. This is why each BASIC line goes in its own `-a`.

### Quoting and shell escaping

CPC BASIC uses `"` a lot. Mind your shell quoting — single-quote the whole step
so the shell leaves the double-quotes alone:

```bash
-a 'run"mygame'           # good: shell passes  run"mygame  to cap32
-a "run\"mygame"          # also works, but uglier
```

A CPC string like `PRINT"HELLO"` only needs the *opening* quote to be balanced
for the typed line to work; you can write `-a 'print"hello'` and ENTER closes it.

### Timing: the CPC needs to boot first

Caprice waits for the CPC firmware to finish booting before it starts feeding
your steps (otherwise the keystrokes would be lost during the boot screen). How
long it waits is controlled by the `boot_time` configuration setting (see §6).
On the Plus range there is an extra F1/F2 nag screen — see `CAP32_DELAY` (§4) for
how to wait past it.

---

## 2. Typing into the CPC

Regular characters in an `-a` step are typed straight into the emulated machine,
so you can drive BASIC, a loader menu, or your own program's input routine:

```bash
-a 'mode 1'                       # a BASIC command
-a 'load"data.bin",&8000'         # type a command with arguments
-a '10 print"hi":goto 10'         # enter a BASIC line
-a run                            # RUN the program
```

### Special keys

Most printable characters work directly. For function keys, use these keywords
inside an `-a` step:

| Keyword  | Types              |
|----------|--------------------|
| `CPC_F1` | the CPC **f1** key |
| `CPC_F2` | the CPC **f2** key |

These are useful for programs that respond to the function keys (for example to
start a game from a title screen). They are replaced wherever they appear in the
step text, so you can mix them with other typing.

> Tip: ENTER is automatic at the end of each `-a`. If your program reads single
> keypresses rather than full lines (e.g. an in-game menu), put each keystroke in
> its own `-a` step so each one is delivered and released cleanly.

---

## 3. Capturing results for verification

Automated tests need a **deterministic artifact** to compare against a known-good
reference. Caprice gives you two:

### A) Screenshot (PNG) — `CAP32_SCRNSHOT`

`-a CAP32_SCRNSHOT` writes a PNG of the current screen into the directory set by
`sdump_dir` (see §6). The file is named:

```
screenshot_<timestamp>.png
```

The timestamp makes the filename **unpredictable**, so in a test script you
normally rename the newest file to a fixed name before comparing:

```bash
mv output/screenshot_*.png output/screenshot.png
diff output/screenshot.png model/screenshot.png
```

Screenshots capture the raw emulated frame (the CPC's actual pixels), which is
ideal for verifying that your game renders the right thing.

### B) Printer output — the most reliable text channel

If you enable the emulated printer, **anything the CPC prints to the printer port
is appended to a plain file** (`printer_file`, see §6). This is the most robust
way to capture *textual* output for diffing, because it is exact bytes with no
rendering involved.

From CPC BASIC you send text to the printer with stream `#8`:

```bash
-a 'print #8,"test passed"'       # writes  test passed  to printer_file
```

A test then just diffs the printer file against an expected file:

```bash
diff output/printer.dat expected.dat
```

This pattern — have your program `PRINT #8` its results, then diff the printer
file — is the backbone of reliable, text-based automated tests for the CPC.

---

## 4. Emulator command reference (`CAP32_*`)

These are the commands you can issue from `-a`. The ones marked **batch-friendly**
are the ones you will actually use in unattended test scripts; the rest toggle
interactive UI and are listed for completeness.

| Command           | Batch | What it does                                                                                                                                                      |
|-------------------|:-----:|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `CAP32_EXIT`      |   X   | Quit the emulator. **Always end a test with this** so the process terminates.                                                                                     |
| `CAP32_WAITBREAK` |   X   | Pause the script until your program returns to BASIC (hits address 0, e.g. via `CALL 0`). The key synchronization primitive — see §5.                             |
| `CAP32_DELAY`     |   X   | Wait a fixed extra delay (one `boot_time` worth of frames) before the next step. Use to get past the Plus F1/F2 nag screen or to give a loader time. No argument. |
| `CAP32_SCRNSHOT`  |   X   | Save a PNG screenshot to `sdump_dir` (see §3A).                                                                                                                   |
| `CAP32_RESET`     |   X   | Reset the emulated CPC (like a hardware reset).                                                                                                                   |
| `CAP32_SPEED`     |   X   | Toggle the speed limiter. Turning the limit **off** makes the CPC run as fast as the host can — useful to make long tests finish quicker (see §7).                |
| `CAP32_TAPEPLAY`  |   X   | Toggle the tape "play" button (press play on a loaded tape). Needed to start tape loading.                                                                        |
| `CAP32_MF2STOP`   |   X   | Trigger the Multiface 2 stop button (if a Multiface 2 is enabled).                                                                                                |
| `CAP32_FPS`       |       | Toggle the on-screen FPS / performance display.                                                                                                                   |
| `CAP32_DEBUG`     |       | Toggle verbose logging on/off.                                                                                                                                    |
| `CAP32_JOY`       |       | Cycle joystick-emulation mode (keyboard ↔ none ↔ mouse).                                                                                                          |
| `CAP32_PHAZER`    |       | Cycle light-gun (phazer) emulation mode.                                                                                                                          |
| `CAP32_FULLSCRN`  |       | Toggle fullscreen.                                                                                                                                                |
| `CAP32_GUI`       |       | Open the F1 menu (interactive).                                                                                                                                   |
| `CAP32_VKBD`      |       | Open the on-screen virtual keyboard (interactive).                                                                                                                |
| `CAP32_DEVTOOLS`  |       | Open the developer tools (debugger / disassembler / memory editor).                                                                                               |
| `CAP32_PASTE`     |       | Paste host clipboard text as typed input (interactive).                                                                                                           |

> Saving/restoring machine snapshots (`.sna`) during a run is available
> interactively from the GUI, but is not exposed as an `-a` keyword. For
> automated tests, load a snapshot at startup as a slot file instead (see §8),
> and capture results with screenshots or the printer file.

---

## 5. Waiting for your program: `CAP32_WAITBREAK`

The single hardest part of automating an emulator is **timing**: you can't take a
screenshot until your program has actually drawn the screen, and you can't quit
until it has finished. Wall-clock delays are fragile. Caprice gives you a
program-driven way to synchronize: `CAP32_WAITBREAK`.

`CAP32_WAITBREAK` **stops the script from advancing until the emulated program
returns to BASIC** — concretely, until execution reaches address 0, which happens
when your program does `CALL 0` (or a reset/`RST 0`). At that point the next `-a`
step runs.

So the idiomatic "run to completion, then capture" sequence is:

```bash
cap32 -c test.cfg \
      -a 'run"mygame' \      # start the program
      -a CAP32_WAITBREAK \   # block until it does CALL 0 (returns to BASIC)
      -a CAP32_SCRNSHOT \    # now it's safe to capture
      -a CAP32_EXIT \
      mygame.dsk
```

To make this work, **have your program end with `CALL 0`** (assembly: `JP 0` /
`RST 0`, or just return to BASIC which then runs `CALL 0`). A common test harness
pattern in BASIC:

```basic
10 MODE 1
20 CALL &8000        : REM run the routine under test
30 PRINT #8,"done"   : REM emit a result to the printer file
40 CALL 0            : REM signal "finished" to CAP32_WAITBREAK
```

When you need a *fixed* pause instead (e.g. there is no clean return point, or you
need to step past the Plus nag screen), use `CAP32_DELAY` — but prefer
`CAP32_WAITBREAK` whenever your code has a definite end point, because it is
deterministic regardless of host speed.

---

## 6. Configuration for testing (`-c` and the relevant settings)

Pass a dedicated config file with `-c <file>` (or `--cfg_file=<file>`) so your
tests don't depend on the user's personal `cap32.cfg`. The settings that matter
for automation:

| Setting                                              | Section | Why it matters for tests                                                                                                |
|------------------------------------------------------|---------|-------------------------------------------------------------------------------------------------------------------------|
| `model`                                              | system  | Which CPC to emulate (e.g. `2` = CPC6128). Pin it so results are stable.                                                |
| `boot_time`                                          | system  | Frames Caprice waits before sending your first step (and the unit `CAP32_DELAY` waits). Tune if steps are lost on boot. |
| `printer`                                            | …       | Set to `1` to enable the printer so `PRINT #8` output is captured.                                                      |
| `printer_file`                                       | file    | Where printer output is written, e.g. `output/printer.dat`.                                                             |
| `sdump_dir`                                          | file    | Directory for `CAP32_SCRNSHOT` PNGs. Point it at your test output dir.                                                  |
| `rom_path`                                           | file    | Path to the ROMs — set relative to your test so it's self-contained.                                                    |
| `resources_path`                                     | file    | Path to resources (fonts, icons).                                                                                       |
| `dsk_path` / `tape_path` / `cart_path` / `snap_path` | file    | Default directories for each media type.                                                                                |

A minimal test config typically pins the model, enables the printer to a known
file, and points the screenshot/printer paths into a per-test `output/` folder.

### Overriding single settings without a new file: `-O`

You can override individual config items on the command line, repeatably, with
`-O section.item=value`:

```bash
cap32 -O system.model=3 -O file.printer_file=output/run.dat -a ... game.dsk
```

This is handy for matrix testing (e.g. run the same script across several CPC
models) without maintaining one config file per case.

---

## 7. Making tests fast

By default Caprice limits emulation to real CPC speed (so games are playable). In
a test you usually want it to run flat out:

- `-a CAP32_SPEED` toggles the speed limiter off, so the emulated CPU runs as fast
  as the host allows. Combined with `CAP32_WAITBREAK` (which finishes the moment
  your program returns, not after a fixed time), long-running tests complete in a
  fraction of the wall-clock time.

If you don't need to *see* anything and only verify printer output, you can keep
the run short and let `CAP32_WAITBREAK` end it as soon as your program signals
completion.

---

## 8. Loading your program

The files to load are listed at the end of the command line (the "slots"). Caprice
picks the right virtual port by file extension:

| Extension      | Loaded as                                                 |
|----------------|-----------------------------------------------------------|
| `.dsk`         | Disk image (drive A)                                      |
| `.cdt`, `.voc` | Tape image                                                |
| `.cpr`         | Cartridge (Plus / GX4000)                                 |
| `.sna`         | Snapshot (a saved machine state — boots straight into it) |
| `.zip`         | Archive containing one of the above                       |

```bash
cap32 -c test.cfg -a 'run"game' -a CAP32_WAITBREAK -a CAP32_EXIT game.dsk
cap32 -c test.cfg -a CAP32_SCRNSHOT -a CAP32_EXIT savedstate.sna
```

Loading a `.sna` snapshot is a great way to **start a test from a known mid-game
state** without scripting the whole way there: save the state once interactively,
commit the `.sna`, then in CI load it and assert on a screenshot.

### Injecting a raw binary: `-i` / `-o`

For a tight edit-build-test loop on a machine-code program, you can inject a raw
binary directly into CPC memory after boot, skipping disk/tape entirely:

```
-i <file>      (--inject=<file>)   binary to load into memory after the CPC boots
-o <address>   (--offset=<addr>)   address to load it at (default 0x6000)
```

```bash
cap32 -c test.cfg -i build/mygame.bin -o 0x4000 \
      -a 'call &4000' -a CAP32_WAITBREAK -a CAP32_SCRNSHOT -a CAP32_EXIT
```

This injects your freshly built binary at `&4000`, calls it, waits for it to
return, screenshots, and exits — no disk image to rebuild between iterations.

The address accepts hex (`0x4000` or, in BASIC when you `CALL` it, `&4000`).

---

## 9. Other useful command-line options

| Option                           | Meaning                                                                                                                        |
|----------------------------------|--------------------------------------------------------------------------------------------------------------------------------|
| `-c <file>` / `--cfg_file`       | Use this config file instead of the default.                                                                                   |
| `-O sec.item=val` / `--override` | Override one config setting (repeatable).                                                                                      |
| `-s <file>` / `--sym_file`       | Load a symbol file (labels/entry points) for the debugger/disassembler — handy when debugging a failing test in the dev tools. |
| `-v` / `--verbose`               | Verbose logging — useful to see what each `-a` step did and why a test failed.                                                 |
| `-V` / `--version`               | Print version/build info and exit (also reports the number of video plugins).                                                  |
| `-h` / `--help`                  | Show usage.                                                                                                                    |

---

## 10. Recipes

### Run a BASIC program and check its text output

`mygame` `PRINT #8`s its results and ends with `CALL 0`:

```bash
cap32 -c test.cfg \
      -a 'run"mygame' \
      -a CAP32_WAITBREAK \
      -a CAP32_EXIT \
      mygame.dsk
diff output/printer.dat expected.dat
```

### Visually verify a rendered screen

```bash
cap32 -c test.cfg \
      -a 'border 13:ink 0,13:ink 1,0:mode 1:gosub 1000:call 0' \
      -a CAP32_WAITBREAK \
      -a CAP32_SCRNSHOT \
      -a CAP32_EXIT
mv output/screenshot_*.png output/screenshot.png
diff -u model/screenshot.png output/screenshot.png   # or an image-compare tool
```

### Test the same program across CPC models

```bash
for model in 0 1 2 3; do
  cap32 -c test.cfg -O system.model=$model \
        -a 'run"mygame' -a CAP32_WAITBREAK \
        -a "print #8,\"model=$model ok\"" -a CAP32_EXIT \
        mygame.dsk
  mv output/printer.dat output/printer.dat.$model
  diff output/printer.dat.$model model/printer.dat.$model || echo "FAIL model=$model"
done
```

### Skeleton CI test script

```bash
#!/bin/bash
set -e
OUT=output
rm -rf "$OUT"; mkdir -p "$OUT"

cap32 -c test.cfg \
      -a 'run"mygame' \
      -a CAP32_WAITBREAK \
      -a CAP32_SCRNSHOT \
      -a CAP32_EXIT \
      mygame.dsk > "$OUT/run.log" 2>&1

mv "$OUT"/screenshot_*.png "$OUT/screenshot.png"

if diff -q "$OUT/screenshot.png" model/screenshot.png; then
  echo "PASS"; exit 0
else
  echo "FAIL — see $OUT/run.log"; cat "$OUT/run.log"; exit 1
fi
```

You can see real, working examples of all of this in the repository under
[test/integrated/](test/integrated/) — each `*/test.sh` is a self-contained
automated test built exactly with the options above.

---

## 11. Gotchas & tips

- **Always finish with `CAP32_EXIT`.** Without it the emulator keeps running and
  your script/CI job hangs.
- **ENTER is auto-appended to every `-a`.** Put each line of input in its own
  `-a`; don't add trailing newlines yourself. (One consequence: chaining several
  `CAP32_*` commands as separate `-a` steps can interact awkwardly with the
  auto-ENTER in some sequences — if a multi-command tail misbehaves, try combining
  the commands into a single `-a` step, e.g. `-a 'CAP32_WAITBREAK CAP32_SCRNSHOT CAP32_EXIT'`.)
- **Prefer `CAP32_WAITBREAK` over fixed delays.** End your program with `CALL 0`
  so the script advances exactly when the program is done, independent of host
  speed. Reserve `CAP32_DELAY` for cases with no clean return point (e.g. the Plus
  F1/F2 nag screen).
- **Screenshot filenames contain a timestamp** and are therefore not predictable —
  rename the newest PNG to a fixed name before diffing.
- **Use a dedicated `-c` config** (or `-O` overrides) so tests don't depend on a
  developer's personal settings, and point `sdump_dir` / `printer_file` into a
  per-test output directory you can clean between runs.
- **Pin the `model`** so a test that passes on a CPC6128 doesn't silently change
  behaviour on a CPC464.
- **For text assertions, prefer the printer file over screenshots** — it's exact
  bytes and immune to rendering differences.
- **Run headless faster** by toggling `CAP32_SPEED` to disable the speed limit.
- **Debugging a failing test?** Add `-v` for verbose logs, and `-s symbols.sym`
  plus the dev tools if you need to inspect what the CPU is doing.
```

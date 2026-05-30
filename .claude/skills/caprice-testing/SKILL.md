---
name: caprice-testing
description: Build and visually test Amstrad CPC programs in the Caprice32 (cap32) emulator, headless. Use when running, screenshotting, or eyeball-verifying a CPC .dsk/.cdt build, driving cap32 in this environment, or building a CPC PoC/test with z88dk +cpc. Covers the cap32-shot.sh driver and the CPC-side gotchas learned in Phase 4 R2.
---

You are operating the **RAGE1 Caprice32 (CPC) test workflow**: build a CPC
program with z88dk's `+cpc` target, run it headless in the `cap32` emulator,
and capture a PNG of the emulated screen for eyeball / pixel verification.

This is the CPC analogue of the JNEXT ZX workflow (the `jnext-regression`
skill / `tests/00regression/`). It is currently an **interim driver** — the formal
Caprice32+Xvfb/Docker regression harness is plan task **TS2** (`testing.md`),
not yet built. Until then, `tools/cap32-shot.sh` is the way to get a CPC
screenshot in this dev environment.

## The screenshot driver: `tools/cap32-shot.sh`

```bash
cd tools/cpc-poc            # or any dir containing the .dsk
../cap32-shot.sh [DISKFILE] [CPC_RUN_NAME]
#   DISKFILE     defaults to poc.dsk
#   CPC_RUN_NAME defaults to POC (the AMSDOS binary name on the disk)
# -> writes ./shot.png (full emulator framebuffer grab)
```

What it does, and **why each step is needed in this environment**:

- Starts a **dedicated Xvfb** (`:99`, rootful X) and runs cap32 inside it.
  The live desktop session here is **Wayland** (`WAYLAND_DISPLAY=wayland-0`,
  rootless Xwayland on `:0`): grabbing the `:0` root returns **all black**, and
  GNOME's D-Bus screenshot is **access-denied**. A private Xvfb is the only
  reliable capture surface.
- Forces SDL's X11 backend for cap32: `SDL_VIDEODRIVER=x11 WAYLAND_DISPLAY=`.
  Without this, SDL2 follows `WAYLAND_DISPLAY` to the live compositor and the
  Xvfb root stays black.
- Waits for Xvfb with `xdotool getdisplaygeometry` (this box has **no
  `xdpyinfo`**; `Xvfb`, `xdotool`, `import` from ImageMagick **are** installed).
- Launches `cap32 -c <cfg> -a 'run"NAME.' DISK`, sleeps for boot, then
  `import -window root shot.png`. Also sends **F3** via xdotool (cap32's own
  clean-framebuffer dump to its `sdump_dir`) as a secondary capture.

## cap32 essentials (this machine)

- Binary: `~/src/cpc/caprice32/cap32`. The interactive `cap32` shell function is
  `"$CAP32DIR/cap32" -c "$CAP32DIR/cap32.cfg" "$@"` with
  `CAP32DIR=/home/jorgegv/src/cpc/caprice32`.
- **Always pass `-c <cap32.cfg>`** or cap32 can't find its ROMs
  (`rom/cpc6128.rom not found`). The cfg also sets `model=2` (CPC6128) and
  `sdump_dir` (where F3 dumps land).
- Useful flags: `-a/--autocmd '<BASIC cmd>'` runs a command after boot (injected
  into the firmware, so it bypasses the host keymap — quotes are safe);
  `-c <cfg>`; loads `.dsk` / `.cdt` / `.sna` / `.cpr` / `.zip` (**not** the raw
  z88dk `.cpc`). In-emulator: **F3** = save screenshot, **F10** = quit.

## Building a CPC test program (z88dk `+cpc`)

```bash
zcc +cpc -compiler=sdcc -zorg=0x4000 -create-app -subtype=dsk -o NAME \
    main.c engine/src/cpc/*.asm
```
- **`-compiler=sdcc`** is mandatory: cpctelera's C-binding ABI is SDCC's, and
  z88dk's SDCC `__z88dk_callee`/`__z88dk_fastcall` match it exactly.
- **`-zorg=0x4000` is mandatory for anything that draws text / reads the
  firmware font.** `cpct_drawStringM1` pages in the **lower ROM (0x0000–0x3FFF)**
  to read the 0x3800 font; any code/data below 0x4000 is masked during that
  window → the call crashes into ROM. z88dk's `+cpc` default org is 0x1200.
- Link the **translated** cpctelera primitives from `engine/src/cpc/*.asm`.
  **Never compile cpctelera itself** — it is pure `sdas` asm and z88dk has no
  `sdasz80` (the whole Option (b) translation model; see `cpc-renderer.md`
  §4.2/§6 and `engine/src/cpc/README.md`).
- `-subtype=dsk` → `.dsk` (cap32-loadable). `-subtype=none` → tape/`.cpc`.

## Launch gotcha: AMSDOS blank extension

z88dk writes the disk file with an **empty extension** (catalog shows
`POC     .`). `RUN"POC` fails (AMSDOS auto-appends `.BAS`/`.BIN` and finds
nothing) — launch with **`RUN"POC.`** (trailing dot = explicit empty ext).
`cap32-shot.sh` already appends the dot.

## Analysing the capture (ImageMagick)

```bash
convert shot.png -format "mean=%[fx:mean]\n" info:                 # 0 = all black (capture failed)
convert shot.png -depth 8 -format %c histogram:info: | sort -rn | head   # dominant colours
convert shot.png -crop WxH+X+Y +repage -scale 200% crop.png        # zoom a text region
```
CPC mode-1 boot/default palette is **bright yellow on dark blue** — don't
mistake a clean boot banner for your program's output. If you see the
`Amstrad 128K Microcomputer … BASIC 1.1 … Ready` banner, your program **didn't
run** (or crashed back to firmware). To bisect a crash, build staged versions
that end in `__asm di __endasm; for(;;){}` after each call and check whether the
screen shows your output (ran) vs the banner (crashed/never ran).

## Reference PoC

`tools/cpc-poc/` (`main.c` + `Makefile`) is the worked example from Phase 4 R2:
mode-1 init + palette + 4 lines of text via the translated primitives. Committed
evidence: `tools/cpc-poc/r2-poc-mode1-text.png`. Cross-refs:
`doc/multiplatform-plan/cpc-renderer.md` (R2 outcome + §4.2/§6),
`engine/src/cpc/README.md`. Durable facts also in the auto-memories
`project_cpc_poc_findings` and `project_build_nondeterminism`.

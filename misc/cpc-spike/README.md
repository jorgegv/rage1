# CPC toolchain spike — Phase T0 (cross-platform plan)

Throwaway smoke-test for **Phase T0** of the RAGE1 cross-platform plan
(see `doc/multiplatform-plan/toolchain.md` §6 Phase T0). The job is to
prove the toolchain stack — z88dk `+cpc`, SDCC C backend, banking,
AMSDOS/DSK packaging — actually works end-to-end before any RAGE1
plumbing is changed.

**This entire directory will be deleted before Phase T1.** Do not grow
it; do not depend on it.

## Files

- `hello.c` — Single-source CPC program. Sets video mode 1, sets a red
  border, then hangs. Used for T0-2 (AMSDOS `.cpc`) and T0-3 (`.dsk`).
- `hello_banked.c` — Same idea, plus a `#pragma bank 4` function called
  from `main()`. Used for T0-4 (proves z88dk recognises `#pragma bank`
  on `+cpc` and produces a separate `_BANK_4.bin` artifact).
- `hello.cpc`, `hello-dsk.dsk`, `hello_banked.cpc`, `hello_banked_BANK_4.bin`
  — checked-in build artifacts (kept *only* so the gating phase
  produces visible deliverables; they go away with the rest of this
  directory at the start of T1).

## Build commands

`zcc` must be on PATH (`source env.sh` from the repo root).

**T0-2 — AMSDOS binary**:
```bash
zcc +cpc -compiler=sdcc -lndos hello.c -create-app -o hello
# produces:  hello       (raw 721-byte binary)
#            hello.cpc   (849-byte AMSDOS-headed binary, ORG=0x1200)
```

**T0-3 — DSK image**:
```bash
zcc +cpc -compiler=sdcc -subtype=dsk -lndos hello.c -create-app -o hello-dsk
# produces:  hello-dsk       (raw binary)
#            hello-dsk.dsk   (194 816-byte CPC 40-track DSK image)
```

**T0-4 — Banked binary**:
```bash
zcc +cpc -compiler=sdcc -lndos hello_banked.c -create-app -o hello_banked
# produces:  hello_banked              (raw binary, main code only)
#            hello_banked.cpc          (AMSDOS-headed main binary)
#            hello_banked_BANK_4.bin   (banked function, 23 bytes)
```

## Why not cpctelera primitives?

The plan (toolchain.md §T0-2 and cpc-renderer.md) assumed the spike
would call a cpctelera draw primitive, with the C source compiled by
z88dk and the cpctelera library sources linked in alongside. **This
does not work as a drop-in.**

### Findings (these are the T0 gating signals)

1. **`-clib=sdcc_iy` is not defined for `+cpc` in this z88dk install**
   (`v23854-4d530b6eb7-20251005`).
   `lib/config/cpc.cfg` exposes only `default` (sccz80) and `ansi`.
   `sdcc_iy` is defined only in `zx.cfg`. The toolchain.md §2.1 line
   ~218 claim that "`-clib=sdcc_iy` is the default for `+cpc` exactly
   as for `+zx`" is **incorrect** for the current z88dk tree.

   **Workaround used here**: pass `-compiler=sdcc` explicitly. This
   uses the SDCC backend with the default `+cpc` C library
   (`cpc_clib`). It is *not* the `sdcc_iy` flavour RAGE1 uses on `+zx`.
   Implication for the cross-platform plan: either the SDCC-IY
   variant needs to be ported to `+cpc` in z88dk (filing upstream), or
   the toolchain spec needs to drop the IY-flavour assumption for CPC.

2. **cpctelera assembly files use SDCC/sdas dialect, not z88dk/z80asm**.
   Verified by feeding `external/cpctelera/cpctelera/src/video/cpct_setVideoMode.asm`
   to `zcc +cpc`: z80asm rejects `.module`, `#0xFC` immediates, and the
   `_cbindings.s` `.include /file.s/` syntax. cpctelera's C-binding
   stubs (`*_cbindings.s`) are also sdas dialect, so the boundary at
   the C/asm seam is unusable as-is.

   **Implication for Phase R1**: cpctelera cannot be linked as a
   "drop the source files into z88dk's compile line" library. Phase R1
   needs to decide between (a) pre-building cpctelera with its own
   SDCC+sdasz80 to a `.lib` and linking that into the z88dk build, or
   (b) translating the handful of primitives we need into z80asm
   syntax under `engine/src/cpc/` (cpctelera being LGPL, both are
   permissible). Both are heavier than the doc currently implies.

### What the spike actually uses

The spike uses **z88dk's bundled `<arch/cpc/cpc.h>`** API:
- `cpc_SetMode(mode)` — direct gate-array video-mode write (mode 0..3).
- `cpc_SetBorder(colour)` — sets border colour via firmware.

These are the z88dk-native analogues of cpctelera's `cpct_setVideoMode`
and border-colour primitives. They prove that the C toolchain, the
linker, AMSDOS/DSK packaging, and `#pragma bank` all work on `+cpc` —
which is the *real* gating signal of Phase T0.

## Emulator verification

**Not performed.** Caprice32 is exposed as a `cap32` shell function on
this dev environment but `$CAP32DIR` is empty in non-interactive shells
and the binary location is unknown. Task spec explicitly permits
skipping emulator runs at T0 ("If you can find Caprice32 already
installed locally, run it for visual confirmation; otherwise skip the
run step and document that"). Visual verification is deferred to Phase
TS2 (testing/screenshot harness) per the plan.

## Cleanup

This directory exists only to anchor the T0 deliverables. Before Phase
T1 starts, delete:
```
rm -rf misc/cpc-spike/
```
The compile recipes proven here are recorded in `toolchain.md`; the
actual CPC build will live under `engine/src/cpc/` and a new
`Makefile-cpc` in Phase T2.

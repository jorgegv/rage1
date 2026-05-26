# misc/au-spike — Phase AU1-3 Arkos2 dual-target spike

**Phase**: AU1-3 (`doc/multiplatform-plan/audio.md` §5 Phase AU1)
**Goal**: confirm that ONE Arkos2 AKG player source can be assembled to
target both ZX Spectrum and Amstrad CPC, by toggling the
`PLY_AKG_HARDWARE_SPECTRUM` / `PLY_AKG_HARDWARE_CPC` define, using a
toolchain that is realistic for the engine's build pipeline.

This spike is intentionally **outside the engine**: standalone, asm-only,
no z88dk C glue, no link with RAGE1. It just demonstrates the dual-target
build mechanism that Phase AU3 will lean on.

## Files

| File                         | Role                                                                          |
|------------------------------|-------------------------------------------------------------------------------|
| `spike_zx.asm`               | Tiny wrapper — defines `PLY_AKG_HARDWARE_SPECTRUM=1`, then `INCLUDE`s player. |
| `spike_cpc.asm`              | Tiny wrapper — defines `PLY_AKG_HARDWARE_CPC=1`, then `INCLUDE`s player.      |
| `PlayerAkg.asm`              | Arkos2 AKG player source (copied verbatim from `tests/arkos/binary-tests/PlayerAkg.asm`, with the hardcoded `PLY_AKG_HARDWARE_SPECTRUM = 1` line stripped — the hardware define is now injected by the wrapper). |
| `PlayerAkg_SoundEffects.asm` | Arkos2 sound-effect engine source (copied verbatim from `tests/arkos/binary-tests/`). |
| `Makefile`                   | `make` builds both targets and prints sizes.                                  |

## Build

```sh
make                # builds spike_zx.bin and spike_cpc.bin
make clean
```

The build uses **RASM** at `/home/jorgegv/src/spectrum/rasm/rasm.exe` (same
path the project's own `other/arkos2player/Makefile` and
`tests/arkos/binary-tests/Makefile` use). See "Toolchain note" below.

## Results

```
=== AU1-3 dual-target spike — sizes ===
-rw-r--r--. 1 jorgegv jorgegv 3411 May 26 02:01 spike_cpc.bin
-rw-r--r--. 1 jorgegv jorgegv 3299 May 26 02:01 spike_zx.bin

ZX vs CPC byte delta (CPC is typically slightly larger):
  zx   : 3299 bytes
  cpc  : 3411 bytes
  diff : 112 bytes
```

`cmp spike_zx.bin spike_cpc.bin` confirms the two binaries diverge from
byte 76 onwards — the `PLY_AKG_HARDWARE_*` define really does steer the
code generation, not just headers/comments. CPC is 112 bytes (~3.4%)
larger than ZX: the player emits CPC-specific PSG-port I/O paths under
`IFDEF PLY_AKG_HARDWARE_CPC` (PSG via PPI ports `&F4xx` on CPC vs ULA-out
on Spectrum). The Spectrum/Pentagon/MSX variants share more code via the
`PLY_AKG_HARDWARE_SPECTRUM_OR_PENTAGON` / `_OR_MSX` derived flags.

Both `.sym` files are 20537 bytes (identical symbol set, divergent
addresses on the hw-specific routines).

### Symbol sanity check

The five public entry points the engine consumes
(`PLY_AKG_INIT`, `PLY_AKG_STOP`, `PLY_AKG_PLAY`,
`PLY_AKG_INITSOUNDEFFECTS`, `PLY_AKG_PLAYSOUNDEFFECT`) are exported by
both builds and resolve to the expected start-of-binary addresses (e.g.
`PLY_AKG_INIT = 0x014D`, `PLY_AKG_INITSOUNDEFFECTS = 0x0009`,
`PLY_AKG_PLAYSOUNDEFFECT = 0x000D`) — checked via
`grep PLY_AKG_INIT spike_zx.sym spike_cpc.sym` and inspecting
`spike_*.sym` directly.

## Conclusions

- The dual-target `PLY_AKG_HARDWARE_*` mechanism in the Arkos2 player
  source **works as documented** — a single source file produces two
  hardware-specific binaries with no fork required. Phase AU3 can rely on
  this for the CPC port.
- Sizes are sensible (3.2–3.4 KB) for an AKG player without song data.
  The ~110-byte ZX→CPC delta matches expectations (CPC PSG-via-PPI path
  is slightly more code than ZX bitbanged-AY-port path).
- The same source assembles cleanly under RASM **with no edits other
  than the per-target define** — this is the contract Phase AU3 will need.

## Toolchain note (important for Phase AU3 planning)

The original task spec for AU1-3 asks for assembly via `z80asm` from
z88dk. I attempted that first; **z88dk-z80asm cannot assemble the
original Arkos2 RASM source directly**. The RASM dialect uses:

- multiple `=` assignments to the same symbol as overrides (`PLY_AKG_HardwareCounter = PLY_AKG_HardwareCounter + 1`) — z80asm treats `=` as a one-shot `defc`, so the second hit is "duplicate definition";
- `FAIL 'message'` directive with single-quoted strings — z80asm sees this as an invalid character constant;
- `IF expr` / `IFDEF` semantics that differ in a few places (e.g. value-vs-presence tests);
- conditional `IFDEF ... ENDIF` blocks that re-bind config flags — see above.

The project already handles this via the
`other/arkos2player/Makefile` recipe, which is:

> RASM → assemble the original source → Disark → re-emit pasmo-syntax
> source → `pasmo-to-z88dk.pl` → z88dk-z80asm-syntax `.inc` (the file
> that ships under `engine/banked_code/128/arkos2-player_asm.inc`).

In other words: **the engine never feeds raw RASM source to z80asm.** It
ships a Disark-converted, z88dk-flavoured snapshot. For Phase AU3 the
realistic options are:

1. **Snapshot path (recommended)** — extend the
   `other/arkos2player/Makefile` recipe with a per-target define
   (currently hardcoded `PLY_AKG_HARDWARE_SPECTRUM = 1`) and ship TWO
   pre-converted `arkos2-player_asm.inc` flavours under
   `engine/banked_code/128/` (or just regenerate at engine build time
   via a make rule). Picks at link time via existing
   `BUILD_FEATURE_PLATFORM_*`.
2. **RASM-at-build path** — make RASM a build-time dependency and
   assemble the player binary as a separate object, linking the raw
   `.bin` into the bank via `binary` / `incbin`. Cleaner but adds a
   non-z88dk tool to the toolchain.

This is the **same dialect-mismatch finding as T0's cpctelera spike**.
Document it as a Phase AU3 / Phase R1 follow-up. The dual-target
mechanism itself is proven; only the integration path needs to be
chosen.

## Skipped

- No engine link — out of scope for AU1-3.
- No song / FX data — out of scope for AU1-3.
- No z88dk `+cpc` runtime — out of scope; CPC C runtime work lives in
  Phase R1 (separate plan track).

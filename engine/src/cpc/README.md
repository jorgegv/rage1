# `engine/src/cpc/` — translated cpctelera primitives

Per the cross-platform plan **Option (b)** decision
(`doc/multiplatform-plan/cpc-renderer.md` §4.2 / §6, Phase R1-5):
cpctelera is **all `sdas`-dialect Z80 assembly**, and z88dk ships no
`sdasz80` (its `z80asm` cannot parse `sdas`). So the CPC primitives RAGE1
needs are **hand-translated `sdas` → z88dk-`z80asm`** and committed here,
then built as ordinary engine asm by `zcc +cpc -compiler=sdcc`. cpctelera
itself (`external/cpctelera/`) is pinned **reference only** and never
compiled.

Each translation is an LGPL-3.0-derived work (cpctelera © ronaldo /
Fremos / Cheesetea / ByteRealms); cpctelera's copyright + LGPL notice are
retained, and the upstream commit SHA each file derives from is recorded
below.

## Upstream pin

cpctelera submodule commit: **`662fc885`** (all translations below derive
from this revision).

## Translated shortlist (R2 PoC + R4 renderer + IN6 input)

| File | C symbol(s) | Translated from (cpctelera `src/…`) |
|---|---|---|
| `cpct_video.asm` | `cpct_setVideoMode`, `cpct_setPALColour`, data `_cpct_mode_rom_status` | `video/cpct_setVideoMode.asm`+`_cbindings.s`, `video/cpct_setPALColour.asm`+`_cbindings.s`, `video/videomode.s`, `firmware/cpc_mode_rom_status.s` |
| `cpct_strings_m1.asm` | `cpct_setDrawCharM1`, `cpct_drawStringM1`, internal `cpct_drawCharM1_inner_asm`, tables `dc_mode1_ct` / `cpct_char2pxM1` | `strings/cpct_setDrawCharM1.asm`+`_cbindings.s`, `strings/cpct_drawCharM1_inner.s`, `strings/cpct_drawStringM1.asm`+`_cbindings.s`, `strings/cpct_dc_mode1_ct.s`, `strings/strings.s` |
| `cpct_gfx_m1.asm` (R4) | `cpct_getScreenPtr`, `cpct_drawSprite`, `cpct_setBorder` | `video/cpct_getScreenPtr.asm`+`_cbindings.s`, `sprites/cpct_drawSprite.asm`+`_cbindings.s` (clean loop re-derivation, see note), GA border-ink set |
| `cpct_keyboard.asm` (IN6) | `cpct_scanKeyboard`, `cpct_scanKeyboard_f`, `cpct_isKeyPressed` (fastcall), `cpct_isAnyKeyPressed_f`, data `_cpct_keyboardStatusBuffer` (10 bytes) | `keyboard/cpct_scanKeyboard.s`, `keyboard/cpct_scanKeyboard_f.s`, `keyboard/cpct_isKeyPressed.s`, `keyboard/cpct_isAnyKeyPressed_f.s`, `keyboard/keyboard.s` |

**Note on `cpct_drawSprite` (R4):** cpctelera's original is a 63-LDI
self-modifying unroll (cannot run from ROM, bloats the binary). The R4
translation keeps the **load-bearing CPC video-memory address stepping
EXACTLY** (`0x0800` between the 8 pixel lines of a char row, `0xC050` wrap
to the next char row) but copies each sprite line with a plain `LDIR` loop.
Visible output is byte-identical; only the inner copy strategy differs.
This is the cpc-renderer.md R-1 mitigation ("hand-write the equivalent
z80asm from cpctelera's API docs"). These primitives back the real CPC gfx
backend `engine/src/gfx_cpctel.c` (Phase R4).

**Note on `cpct_keyboard.asm` (IN6):** faithful translations (no behavioural
change) of cpctelera's keyboard primitives. They back the real CPC input HAL
bodies in `engine/src/input.c` and the `input_*` macros in
`rage1/input_cpc.h` (Phase IN6). `cpct_isKeyPressed` keeps the
`__z88dk_fastcall` ABI (keyID in HL: high byte = bit mask, low byte = matrix
line); the scan routines self-manage DI/EI, so they are safe to call from the
main-loop call site (`input_scan()` in `check_controller()`).

## Translation conventions (sdas → z80asm)

- `.module X` → `MODULE X`; `.globl s` → `PUBLIC s` (definer) / `EXTERN s` (user).
- sdas global label `_sym::` → `PUBLIC _sym` + `_sym:`.
- Immediate prefix dropped: `ld a,#0x07` → `ld a,0x07`; binary `#0b…` → hex.
- `.equ N,v` → `defc N = v`; `.db`→`DEFB`; `.ds n`→`DEFS n`.
- Implicit-A arithmetic made explicit where required: `add l`→`add a,l`,
  `adc h`→`adc a,h` (`sub`/`and`/`or`/`xor r` keep their single-operand form).
- `ld a,(iy)` → `ld a,(iy+0)`.
- The `cpct_drawStringM1` IY save/restore self-modifying idiom
  (`saveiy = .+2`) is translated to a plain RAM word
  (`ld (strm1_saveiy),iy` / `ld iy,(strm1_saveiy)`) — behaviourally
  identical, cleaner. The `cpct_setDrawCharM1` NOP/RET self-modifying
  loop terminator is kept verbatim (it is the routine's loop counter).

The C-callable ABI (`__z88dk_fastcall` / `__z88dk_callee`) is preserved
exactly, so no symbol renaming is needed at the C boundary.

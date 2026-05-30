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

## Translated shortlist (R2 PoC)

| File | C symbol(s) | Translated from (cpctelera `src/…`) |
|---|---|---|
| `cpct_video.asm` | `cpct_setVideoMode`, `cpct_setPALColour`, data `_cpct_mode_rom_status` | `video/cpct_setVideoMode.asm`+`_cbindings.s`, `video/cpct_setPALColour.asm`+`_cbindings.s`, `video/videomode.s`, `firmware/cpc_mode_rom_status.s` |
| `cpct_strings_m1.asm` | `cpct_setDrawCharM1`, `cpct_drawStringM1`, internal `cpct_drawCharM1_inner_asm`, tables `dc_mode1_ct` / `cpct_char2pxM1` | `strings/cpct_setDrawCharM1.asm`+`_cbindings.s`, `strings/cpct_drawCharM1_inner.s`, `strings/cpct_drawStringM1.asm`+`_cbindings.s`, `strings/cpct_dc_mode1_ct.s`, `strings/strings.s` |

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

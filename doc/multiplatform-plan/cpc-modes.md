# Phase 7 — CPC video modes (Mode 0 / Mode 2) + palette

> **Status: APPROVED (2026-06-07). No code written yet (plan only).**
> The user reviewed this plan and **accepted all decisions D1–D7** and resolved
> every open question (§6). **Phase 7 must be completed in full — no work is
> deferred to a later phase** (the MONO/FAST variants are included as the final
> sub-phase CM8). Sub-phases CM1–CM8 are now the agreed scope.
>
> Cross-refs: builds on `cpc-renderer.md` §0 (CPC gfx = JSP), `gfx.md` (the two-
> layer colour model §5.5), `assets.md` (CPC byte format), and Task 5's
> `lib/RAGE/` asset-backend seam. Management entry: `management/00tasklist.md`
> **Phase 7**.

## 1. Goal

RAGE1's CPC port currently runs **only JSP `CPC_MODE1`** (4 pens, 320×200, 1-px
horizontal movement) with a **hardcoded 4-pen palette** and **2-colour assets**
(pen 0 = background, pen 1 = foreground). Phase 7 extends this to:

1. **Mode 0** (16 pens, 160×200) and **Mode 2** (2 pens, 640×200), selectable
   per game, alongside the existing Mode 1.
2. A **per-game palette specification** (a default palette in the game data) plus
   **runtime change-palette rules** (swap pens during play, e.g. per screen).
3. **Multi-pen (colour) art** so Mode 0 / Mode 1 can use more than two colours.
4. **Demos** for each mode + palette rule, and **documentation** for all of it.

## 2. What already exists (the leverage — why this is an *extension*, not a rewrite)

| Layer | State | Evidence |
|---|---|---|
| JSP geometry | All 7 CPC modes (0/1/2 + MONO/FAST) exist at compile time, mode-parametric | `external/jsp/lib/cpc/jsp_cpc_geom.inc`, `external/jsp/include/jsp_config.h` |
| RAGE1 HAL constants | `GFX_SCREEN_COLS=JSP_GRID_COLS` (20/40/80), `GFX_JSP_CELL_BYTECOLS=8/JSP_SPRITE_PPB` already vary by mode | `engine/include/rage1/gfx_jsp.h` |
| datagen packing | `RAGE::CPCGfx` is mode-generic (`_geom` already handles mode 0 & 1) | `lib/RAGE/CPCGfx.pm` |
| Plan reservation | Mode 0/2 reserved "for later without API change"; two-layer colour model isolates CPC palette from ZX attributes | `README §5.13a`, `cpc-renderer.md §0.2`, `gfx.md §5.5` |
| Palette keywords | `CPC_PALETTE` + `CPC_COLOR_MAP` already PARSED in datagen (currently inert) | `tools/datagen.pl` (~1132, ~1392) |

**Mode-1-only seams to make parametric** (the actual work surface):
- Build flag: `Makefile.common` `JSP_CPC_CFLAGS` hardcodes `-DCPC_MODE1`.
- Runtime: `engine/src/gfx_jsp.c` `gfx_init` hardcodes `cpct_setVideoMode(1)` + 4 pens.
- datagen: `RAGE::AssetBackend::create` always returns `CPCMode1`; `CPCMode1.pm` hardcodes `mode=>1`.
- Colour depth: `RAGE::CPCGfx` only emits 2-colour (pen 0/1) bytes.

## 3. Decisions (**all ACCEPTED by the user 2026-06-07**; open questions resolved in §6)

**D1 — Mode selection axis = PER-GAME, via `.gdata`, default Mode 1.** *(ACCEPTED;
the per-game axis is wanted now — see §6 Q-C — not a per-build flag.)*
A game declares `CPC_MODE 0|1|2` in `game_config` (default `1` if absent). The
`Makefile` greps it from the game config to set `-DCPC_MODE$(N)` (exactly as it
already greps `GFX_BACKEND` and `ZX_TARGET`), and `datagen` reads it to pick the
asset backend. *Rationale:* RAGE1 is data-driven — visual mode is a property of
the game, not the build host; this reuses the existing "config drives build +
datagen" pattern and lets different games target different modes. (Alternative:
a per-build Makefile `CPC_MODE=` flag — simpler but one-mode-per-build; rejected
as less RAGE1-idiomatic, but cheap to also support for quick demo builds.)

**D2 — Stage colour depth; don't big-bang.** Structural mode enablement (modes
selectable, existing 2-colour art) lands first and stays green; per-game palette,
then multi-pen colour, then runtime palette changes layer on top. Matches the
project's incremental/gated/"no big-bang" rule. (Sub-phases in §4.)

**D3 — Palette schema = `CPC_PALETTE` ink list, emitted to game data.** *(ACCEPTED,
with Q-B refinement on spelling.)* `CPC_PALETTE <ink>,<ink>,...` (one CPC ink per
pen; length 2/4/16 by mode; a `BORDER` ink too). **Each ink accepts both forms,
freely mixed: a colour NAME (`BLACK`, `BRIGHT_RED`, …) or a firmware-colour NUMBER
in decimal (`13`) or hex (`0x0D`)** — datagen normalises all three to the gate-
array hardware ink (the name→ink table already lives in `cpcgfx.pl`). datagen emits
the resolved inks as a `game_data.h` constant (`game_cpc_palette[]`) consumed by
`gfx_init` instead of today's hardcoded pens. A **default per-mode palette** is
used when the game omits it (today's black/white/yellow/red for Mode 1).
`CPC_COLOR_MAP` (already parsed) maps symbolic colour tokens → pen indices for
multi-pen art authoring (D4).

**D4 — Multi-pen art authored as PNG ONLY; port cpcgfx.pl's multicolour encoder
into `RAGE::CPCGfx`.** *(ACCEPTED — Q-A resolved: PNG-only for multicolour; no
ASCII+colour-map path.)* 2-colour ASCII art stays for simple/shared assets
(pens 0/1). For >2-colour assets the game provides a colour **PNG**; datagen maps
each pixel to the nearest CPC ink and to a pen (the logic already in
`external/jsp/tools/cpcgfx.pl --multicolor` + its 27-colour table), emitting
mode-N multi-pen bytes + the palette. *Rationale:* 16 colours aren't expressible
in readable ASCII; PNG is how real CPC art is drawn; the byte-compat test
(`tests/datagen/cpcgfx_sprite_compat.t`) extends to guard the multicolour bytes
too. (This is the one genuinely new datagen capability.)

**D5 — One mode-parametric CPC backend, not three classes.** Since `RAGE::CPCGfx`
is already mode-generic, make `RAGE::AssetBackend::CPC` take `mode => 0|1|2`
(replacing the `CPCMode1`-only class, kept as a thin alias for back-compat) and
have `AssetBackend::create` read the game's `CPC_MODE`. *Rationale:* avoids
~3× duplicated geometry; the per-mode differences are already parameters.

**D6 — Runtime change-palette = CPC-only gfx API + a flow-rule action.** *(ACCEPTED;
Q-E resolved: a **flow action only** for now — NOT a per-screen palette baked into
the map data.)* Add `gfx_cpc_set_palette(pens, n)` / `gfx_cpc_set_pen(i, ink)`
(ZX: no-op) and a flow **action** (e.g. `SET_CPC_PALETTE`) so games swap pens per
screen/event — the "change-palette rules". Palette stays static (set in
`gfx_init`) unless a rule fires. *Rationale:* matches RAGE1's flow-rule model;
keeps ZX untouched.

**D7 — Demos = per-mode minimal games + a multicolour Mode-0 demo; add RAGE1-level
CPC regression baselines.** Reuse `games/minimal`'s assets where 2-colour; add a
small multicolour asset for the Mode-0 demo. Capture cap32/JNEXT reference shots
per mode under the regression harness (today CPC has none at the RAGE1 level).

## 4. Staged sub-phases (each gated: `make all-test-builds` green + a CPC cap32
screenshot; **ZX output byte-identical** throughout; `external/jsp` stays read-only)

- **CM1 — `CPC_MODE` parametric build + datagen dispatch + Mode 2.**
  Make the `-DCPC_MODE$(N)` flag come from the game's `CPC_MODE` config; wire
  `AssetBackend::create` to the mode (D5). Prove **Mode 2** (2-colour, 640×200)
  rendering `minimal_cpc`. *Gate:* minimal_cpc builds in Mode 1 (unchanged) **and**
  Mode 2; ZX byte-identical.
- **CM2 — Mode 0 (2-colour first).** Prove **Mode 0** (160×200) rendering the same
  2-colour `minimal_cpc` (pens 0/1 of 16). *Gate:* as CM1.
- **CM3 — Per-game static palette.** `CPC_PALETTE` → emitted game-data constant →
  dynamic `gfx_init` (replaces hardcoded pens); per-mode defaults. *Gate:* default
  palette byte-identical to today's hardcoded one (no visual change when omitted).
- **CM4 — Multi-pen colour art.** Port the multicolour encoder into `RAGE::CPCGfx`
  (+ extend the byte-compat test vs `cpcgfx.pl --multicolor`); PNG authoring path;
  a Mode-0 multi-pen demo asset. *Gate:* byte-compat test green; demo shows colour.
- **CM5 — Runtime change-palette.** `gfx_cpc_set_palette` + the `SET_CPC_PALETTE`
  flow action; a demo that changes palette between screens. *Gate:* ZX no-op
  (byte-identical); demo shows the swap.
- **CM6 — Demos + regression baselines.** Per-mode demo games + committed RAGE1
  CPC reference shots (Mode 0/1/2 + a palette-change shot).
- **CM8 — MONO + FAST mode variants** *(Q-F resolved: included in Phase 7 as the
  final sub-phase, NOT deferred).* Wire the remaining JSP CPC configs —
  `CPC_MODE1_MONO` (1bpp assets on a Mode-1 screen) and the byte-aligned `*_FAST`
  variants (`CPC_MODE0/1/2_FAST`, no shift table → coarser X step, smaller/faster)
  — into the same per-game `CPC_MODE` selector and the asset-backend dispatch.
  Add a demo + regression shot for each. *Gate:* each variant builds + renders;
  ZX byte-identical. *(MONO reuses the existing 2-colour asset path; FAST is a
  pure runtime/JSP-flag change — both are small once CM1–CM5 exist.)*
- **CM7 — Documentation.** Update `gfx.md` (mode/palette HAL), `assets.md` (multi-
  pen byte format + PNG authoring), `cpc-renderer.md` §0 (mode matrix now active),
  `README` (§5.13a: Mode 0/2 + MONO/FAST now implemented, not deferred), and a
  `.gdata` keyword reference for `CPC_MODE` / `CPC_PALETTE` / `CPC_COLOR_MAP` /
  `SET_CPC_PALETTE`. *(Do CM7 last, after CM8, so the docs describe the full set.)*

## 5. Invariants & constraints

- **ZX byte-identical** at every gate (all CPC changes behind `GFX_JSP_CPC` /
  CPC platform guards or CPC-only datagen backends; ZX `game_data.c`/asm unchanged).
- **`external/jsp` read-only** — consume JSP's existing mode support; do not modify
  the submodule (any JSP gap → raise upstream + bump pin, not patch in place).
- **Incremental & gated** — one sub-phase at a time, each independently green; no
  big-bang. Design the per-mode regression shots early (CM6 fixtures defined in CM1).
- **Backwards compatible** — a game with no `CPC_MODE` / `CPC_PALETTE` builds
  exactly as today (Mode 1, default palette), byte-for-byte.

## 6. Open questions — RESOLVED (user, 2026-06-07)

- **Q-A — multi-pen art authoring → PNG ONLY** for multicolour assets (no
  ASCII+`CPC_COLOR_MAP` path). Drives CM4.
- **Q-B — palette ink spelling → accept BOTH colour NAMES and firmware NUMBERS,
  the numbers in either decimal OR hex**, freely mixed in `CPC_PALETTE`. datagen
  normalises all to the hardware ink. Drives CM3.
- **Q-C — per-game mode selection (D1) is wanted NOW.** And **Phase 7 must be
  completed in full — nothing deferred** (this removed all "defer to Phase 8"
  framing from this plan).
- **Q-D — Mode 2 first, then Mode 0** (CM1 = Mode 2, CM2 = Mode 0).
- **Q-E — change-palette = a flow action only** for now (no per-screen palette in
  the map data). Drives CM5.
- **Q-F — MONO + FAST variants ARE in Phase 7**, added as the final sub-phase CM8
  (not deferred).

## 7. Sequencing & risk

All sub-phases CM1–CM8 are **in scope for Phase 7 — none deferred** (Q-C). CM1→CM2
are low-risk (compile-flag + dispatch; JSP already renders those modes). CM3 is
low-risk (data plumbing). **CM4 is the real new work** (the multicolour PNG
encoder + palette emission) and the main schedule risk — it is isolated so a
problem there doesn't block CM1–CM3, but it must still land for the phase to be
complete. CM5 (flow action) and CM8 (MONO/FAST flags) are small. CM6 (demos +
baselines) and CM7 (docs, done last) are verification. Natural milestones:
CM1–CM3 (modes + palette), then CM4–CM5 (colour + runtime), then CM6–CM8 (demos,
variants, docs). Multi-session phase.

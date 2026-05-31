# CPC Sprite Engine Analysis — Pixel-Smooth Sprite Movement on the Amstrad CPC

**Status:** Analysis complete; implementation **parked** pending the JSP-CPC project.
**Date:** 2026-05-31
**Context:** RAGE1 multiplatform port (ZX Spectrum + Amstrad CPC), Phase 4 CPC bring-up.
**Origin:** Debug session investigating "hero moves in 8-pixel jumps on CPC".

> This document is deliberately comprehensive and self-contained. It is the
> reference for the most important open quality problem in the RAGE1 CPC port:
> **how to achieve pixel-smooth sprite movement on the Amstrad CPC.** It captures
> the symptom, the root cause, the full library/technique survey (local sources
> + wider CPC ecosystem), the CPC-specific technical mechanics, the economics,
> and the final strategic decision.

---

## 1. Executive summary (TL;DR)

- On CPC, RAGE1's current renderer (`engine/src/gfx_cpctel.c`) moves sprites in
  **8-pixel, cell-aligned steps** (`col = x>>3`, `row = y>>3`). This is the
  documented G8 "functional bar", **not a bug** — but it is **not acceptable**
  for a quality game. Pixel-smooth movement is a baseline requirement, not polish.
- **The current plan never contemplated pixel-smooth CPC sprites.** The only
  movement-quality task, gfx.md **G8-5**, sets a *functional* acceptance bar
  ("same game logic → same gameplay state"), explicitly *not* visual parity.
  This gap was never surfaced as a decision; it must be corrected.
- **No CPC sprite library gives 1-pixel HORIZONTAL positioning for free.**
  Verified directly against cpctelera, z88dk's CPCRSLib, z88dk's `<graphics.h>`,
  meesterturner/cpcsprite, and AMSprite, plus the wider CPC scene (CPCWiki). All
  reusable libraries draw **byte-aligned** horizontally (Mode 0 = 2px, Mode 1 =
  4px, Mode 2 = 8px). **Vertical 1-pixel is free** in all of them (scanline
  addressing).
- The only ways to get 1px horizontal are **pre-shifted sprites** (N× memory),
  **realtime bit-shifting** (CPU per draw), or **compiled sprites** (code+memory).
  These are always built by the game/engine — never a drop-in library call.
- **Decision:** pre-shift is **rejected** (memory-prohibitive for an engine with
  many frames). RAGE1 will use **realtime shifting + masking — the SP1/JSP model**
  already proven on ZX (fixed cost, not per-sprite).
- **Strategic plan:** *park* RAGE1 CPC sprite work; **add CPC support to JSP**
  (Jorge's own sprite library) as a parallel project; then return to RAGE1 and
  wire **JSP-in-CPC-mode as the CPC sprite engine** — mirroring exactly how RAGE1
  already consumes SP1/JSP on ZX. **JSP's high-level architecture stays unchanged;
  only its thin low-level layer (per-mode shift tables/functions, pixel encoding,
  screen-address math, mask format) is added for CPC** (§11.1). The current
  `gfx_cpctel` cell-granular renderer stays as the **interim** CPC backend until
  JSP-CPC lands.

---

## 2. The symptom and why it is not a bug

On `games/minimal_cpc` the hero responds to QAOP but visibly **steps in ~8-pixel
jumps** instead of gliding 1–2px/frame as it does on ZX.

Trace of the cause ([engine/src/gfx_cpctel.c](../engine/src/gfx_cpctel.c),
`gfx_cpctel_move_sprite_clipped`):

```c
uint8_t new_row = (uint8_t)( y >> 3 );   // quantise Y to the 8x8 cell grid
uint8_t new_col = (uint8_t)( x >> 3 );   // quantise X to the 8x8 cell grid
```

The hero's fixed-point position is updated smoothly (HSTEP = 2px/frame, 16.8
fixed-point on CPC), and the integer pixel coordinate is correct — but the
renderer **discards the low 3 bits of both axes** and blits whole 8×8 cells.
So the sprite only moves when it crosses a cell boundary: every 4 frames at
2px/frame → an 8px jump.

This is intentional. The renderer's own comment documents it as the **G8
"functional bar"**: a direct-write, cell-aligned blitter that proves the engine
loop is live (the enemy visibly steps across the screen), with "sub-cell-smooth
masked shifting" named as a later refinement. The acceptance criterion in
gfx.md **G8-5** is *functional*, not visual:

> "Crisp parity with the ZX reference screenshot is *not* required … the
> acceptance criterion is **functional**: same game logic produces same gameplay
> state."

So: **correct against the plan as written, but the plan set the bar too low.**

---

## 3. The gap in the plan

On ZX, the engine never had to answer *"how do I move a sprite by one pixel?"* —
**SP1 (and JSP) give pixel-smooth, masked sprites for free.** The CPC port is the
first time that question must be answered explicitly. Instead of answering it,
the plan deferred it under "visual parity not required" (G8-5) and moved on.

The consequence — *"this permanently means no pixel-smooth sprites on CPC until
someone builds a shifting, masked sprite renderer"* — was buried inside an
acceptance criterion rather than raised as a decision for sign-off. That is the
miss this document corrects. **Pixel-smooth sprite movement is a core renderer
capability and must be an explicit, named requirement**, with the work costed in.

---

## 4. CPC graphics fundamentals (needed for everything below)

The CPC has three display modes. The screen is a byte array; each byte holds a
fixed number of pixels, and **the pixels are bit-interleaved within the byte**
(planar-in-byte), *not* stored as contiguous bit-fields. This interleaving is the
root reason CPC horizontal shifting is harder than ZX.

| Mode | Resolution | Colours | Pixels/byte | Horizontal byte-step |
|------|------------|---------|-------------|----------------------|
| 0    | 160×200    | 16      | **2**       | **2 px**             |
| 1    | 320×200    | 4       | **4**       | **4 px**             |
| 2    | 640×200    | 2       | **8**       | **8 px**             |

Within a byte (`b7..b0`), the pixel-to-bit mapping is:

- **Mode 2** (1 bit/pixel, linear): `b7` = leftmost pixel … `b0` = rightmost.
  Identical model to the ZX Spectrum.
- **Mode 1** (2 bits/pixel): two bit-planes.
  - Plane A (LSB of each pixel): bits **7,6,5,4** = pixels 0,1,2,3
  - Plane B (MSB of each pixel): bits **3,2,1,0** = pixels 0,1,2,3
  - i.e. pixel *n* value = { bit(7−n), bit(3−n) }.
- **Mode 0** (4 bits/pixel): the two pixels interleave on odd/even bits.
  - Pixel 0 (left) occupies the **odd** bit positions {7,5,3,1}
  - Pixel 1 (right) occupies the **even** bit positions {6,4,2,0}

Vertical addressing: a pixel row's screen address is computed per scan-line
(`cpct_getScreenPtr` y is `[0-199]`), so **vertical positioning is 1-pixel in
every mode for free**. The hard axis is **horizontal**.

---

## 5. Why 1-pixel *horizontal* is the hard problem

Every reusable CPC sprite routine plots a sprite by copying its bytes to a
**byte-aligned** screen address. The horizontal coordinate fed to the
screen-pointer helper is *in bytes, not pixels* — confirmed verbatim from
cpctelera's `cpct_getScreenPtr.asm`:

> "Returns a byte-pointer to a screen memory location, given its X, Y coordinates
> (in **bytes**, NOT in pixels!). x = `[0-79]` Byte-aligned column … y = `[0-199]`."

So a byte-aligned blit can only place a sprite at multiples of the mode's
pixels-per-byte: **2px (M0), 4px (M1), 8px (M2)**. To place at an arbitrary pixel
column you must **shift the sprite's bit pattern within/across bytes** before (or
while) writing it — which, because of the planar-in-byte encoding (§4), is *not*
a single Z80 rotate except in Mode 2.

---

## 6. Survey of existing CPC sprite libraries

All checked directly against local source where available.

### 6.1 cpctelera (`external/cpctelera`, pinned reference)

The richest sprite set available, and RAGE1's existing translation source:
`cpct_drawSprite` (opaque), `cpct_drawSpriteMasked`, `cpct_drawSpriteMaskedAlignedTable`,
`cpct_drawSpriteBlended`, `cpct_drawSpriteColorizeM0/M1`, H/V flips,
`cpct_drawToSpriteBuffer*`, `IMG2SPRITES` asset conversion (emits pixel + mask
arrays).

- **Horizontal granularity: byte (2/4/8px).** Every draw routine takes a
  byte-aligned screen pointer and byte-copies the sprite. No within-byte shift.
- **No sub-byte horizontal shift routine exists** anywhere in `cpctelera/src/`
  (searched for `HShift`/`hScroll`/`pixel-shift`/`subpixel` — none).
- The well-known *"CPCtelera smooth 1-pixel Mode 0 movement"* demos achieve it by
  the developer building **pre-shifted sprite sets on top of** `cpct_drawSprite`
  — it is **not** a library capability.

### 6.2 z88dk CPCRSLib (`libsrc/target/cpc/cpcrslib/sprites/`)

The Artaburu (Raúl Simarro) CPC game library, bundled in z88dk's `+cpc` target.
Routines: `cpc_PutSp` (opaque), `cpc_PutMaskSp` (masked), `cpc_PutSpTr`
(transparent), `cpc_PutSpXOR` (xor), `cpc_GetSp` (save background), plus `…0`
double-buffer variants.

- `cpc_PutSp(sprite, alto, ancho, posicion)` = height(lines), width(**bytes**),
  precomputed **destination screen pointer**; copies `ancho` bytes/line.
- **Byte-aligned horizontal, per-line vertical. No sub-byte shift.** Same wall as
  cpctelera.

### 6.3 z88dk generic `<graphics.h>` (`libsrc/target/cpc/graphics/`)

- `plot_MODE0/1/2` — single-pixel plot. **1px, but per-pixel call → far too slow
  to move sprites.**
- `w_putsprite` — the generic monochrome XOR sprite (Patrick Davidson's TI-85
  code, "high-res"/Mode 2). **1bpp, no colour, no real masking.**

### 6.4 meesterturner/cpcsprite (GitHub)

- **2px horizontal** (Mode 0 only), 1px vertical, character-block-aligned capture,
  **no masking**. Explicitly: "X co-ordinates … can anchor to every second pixel
  due to screen memory."

### 6.5 AMSprite (CPCWiki)

- An **asset/GUI generator** (emits ready-to-use sprite + mask assembly and
  loading screens). A tool, **not a runtime pixel-shift engine**.

### 6.6 Verdict

| Source                         | Horizontal       | Vertical | Masked colour sprites?       |
|--------------------------------|------------------|----------|------------------------------|
| cpctelera                      | byte = 2/4/8px   | 1px      | yes (byte-aligned)           |
| z88dk CPCRSLib                 | byte = 2/4/8px   | 1px      | yes (byte-aligned)           |
| z88dk `<graphics.h>` plot      | 1px              | 1px      | no — per-pixel, too slow     |
| z88dk `<graphics.h>` putsprite | byte             | 1px      | no — 1bpp mono XOR           |
| meesterturner/cpcsprite        | 2px (M0 only)    | 1px      | no                           |
| AMSprite                       | n/a (asset tool) | n/a      | generates sprite+mask assets |

**No reusable CPC library provides 1-pixel horizontal sprite movement.**

---

## 7. Survey of techniques (wider CPC ecosystem)

The standard CPC techniques for pixel-precise horizontal positioning, confirmed
against CPCWiki ("Fast Sprites") and cpctech docs:

1. **Pre-shifted sprites** — store N byte-shifted copies per frame: **2 (M0),
   4 (M1), 8 (M2)** = pixels-per-byte. Split pixel-X into `byte_col + offset`;
   pick the matching shifted image; blit byte-aligned.
   - *Cost:* **N× sprite memory.** "Pre-shifted sprites can consume a lot of memory."
2. **Realtime (runtime) bit-shift plot** — store **one** copy; shift the bits into
   place at draw time. *Cost:* CPU per blit. This is the memory-saving alternative
   the docs explicitly name. **This is the SP1/JSP model.**
3. **Compiled sprites** — pixel + mask baked into the plot *instructions*, one
   routine per image; fastest, combined with pre-shift gives pixel-precise + fast.
   *Cost:* heavy code + memory.

Practical note worth recording: **Mode 0 at 2px steps is widely accepted as
"smooth enough"** for player movement without any shifting ("reasonably smooth …
at 2px steps without the need to use pre-shifted sprites"). Mode 1 byte-steps are
4px (borderline); true 1px in Mode 1 essentially *requires* shifting.

---

## 8. The realtime-shift mechanism, per CPC mode (the core technique)

This is the heart of the chosen approach. Because of the planar-in-byte encoding
(§4), a 1-pixel right shift is a **mask + shift + cross-byte carry**, not a plain
rotate (except Mode 2). For a sprite **row** of W bytes shifted by `k` pixels you
process bytes left→right, each source byte contributing to the output byte at the
same index **and** spilling into the next — the output row is `W+1` bytes wide.

> The masks below are derived from the §4 bit layout. They are **structurally
> correct by derivation but MUST be unit-tested against the asset converter's
> exact byte format** before relying on them — CPC bit-ordering conventions vary
> between tools, and the engine's shift must match RAGE1/JSP's own sprite byte
> format.

### 8.1 Mode 2 — trivial, ZX-identical

1bpp linear (`b7` = leftmost). A 1-pixel right shift is a rotate-through-carry
across bytes:

```
carry_in  = (prev_spill)            ; bit from the byte to the left
out_byte  = (src >> 1) | carry_in   ; carry_in occupies b7
spill     = (src & 0x01) << 7       ; b0 falls into the next byte's b7
```

Multi-pixel shifts (1..7) are just multi-bit rotates. **The JSP ZX bit-shift core
ports almost verbatim** — this is the natural first target.

### 8.2 Mode 1 — cheap mask + half-shift + carry

Two bit-planes (A = bits 7..4, B = bits 3..0), each holding one value-bit of the
4 pixels. A 1-pixel **right** shift moves each pixel one position right within its
plane; the rightmost pixel (p3) spills to the next byte's p0:

```
cur_byte_out  |= (src & 0xEE) >> 1   ; p0..p2 -> p1..p3, both planes
next_byte_out |= (src & 0x11) << 3   ; p3 spills into next byte's p0
```

Derivation:
- Plane A (bits 7,6,5 = p0,p1,p2) → (6,5,4 = p1,p2,p3): `(src & 0xE0) >> 1`;
  p3 bit (b4) spills: `(src & 0x10) << 3` → next byte b7.
- Plane B (bits 3,2,1 = p0,p1,p2) → (2,1,0 = p1,p2,p3): `(src & 0x0E) >> 1`;
  p3 bit (b0) spills: `(src & 0x01) << 3` → next byte b3.
- Combine: `0xE0|0x0E = 0xEE`, `0x10|0x01 = 0x11`. ∎

~3 ALU ops + OR per byte — **no LUT strictly required for a 1px shift.** Shifts of
2/3 px compose the 1px step, or are precomputed into a 256-entry LUT per offset
for speed.

### 8.3 Mode 0 — cheap mask + shift (odd/even interleave)

Pixel 0 (left) = odd bits {7,5,3,1}; pixel 1 (right) = even bits {6,4,2,0}. A
1-pixel right shift moves pixel 0 → pixel 1 (odd→even, `>>1`) and pixel 1 → next
byte's pixel 0 (even→odd of next byte, `<<1`):

```
cur_byte_out  |= (src & 0xAA) >> 1   ; pixel0 (odd bits) -> pixel1 (even bits)
next_byte_out |= (src & 0x55) << 1   ; pixel1 (even bits) -> next byte's pixel0
```

Mode 0 has only 2 horizontal phases (offset 0 or 1), so a 256-byte LUT per phase
is the natural fast form, but the mask+shift above already does it.

### 8.4 Masks shift identically

For transparency, the sprite carries a **mask** (1 = background shows, 0 = sprite
pixel). The mask is shifted **with the exact same per-mode operation** as the
pixel data, then composited:

```
screen = (screen AND shifted_mask) OR shifted_pixels
```

This is the SP1/JSP "AND-mask / OR-pixels" composite, applied to the shifted,
`W+1`-byte-wide row.

---

## 9. What a pixel-smooth renderer must do, per sprite, per frame

1. **Split coordinate:** `byte_col = pixel_x / ppb`, `shift = pixel_x % ppb`
   (ppb = 2/4/8 for M0/M1/M2); `y` is the scan-line directly (1px vertical).
2. **Realtime-shift** each sprite row by `shift` (§8) → a `W+1`-byte row of pixels
   and a matching shifted mask.
3. **Composite** with the mask against the screen (§8.4).
4. **Restore background** under the sprite's *previous* (unaligned) footprint.

**Important: this is a solved software problem, not a CPC-specific blocker.** The
ZX has *no* sprite hardware and *no* hardware screen buffer either — SP1 and JSP
implement the off-screen shadow/tile buffer and the background restore **entirely
in software, with zero hardware help**. JSP-CPC **will** implement the same
mechanism; there is no open question of *whether* it can be done, only the
mechanism detail. The established SP1/JSP model is a **library-maintained software
shadow buffer**: the library holds a representation of the screen (as tiles), the
engine composites sprites into it, and only changed cells are pushed to video RAM
— so the background is restored implicitly on the next recomposite, no per-sprite
bookkeeping at the call site.

Crucially, **JSP already implements this** on ZX. The CPC port does **not**
redesign it and does **not** choose a new strategy — JSP's existing shadow-buffer
/ dirty-cell machinery is **reused unchanged**. Background restore is inherited,
not re-decided (see §11.1 for the precise port surface).

---

## 10. Memory & speed economics

| Approach                    | Memory                          | Per-frame CPU       | Notes                                                              |
|-----------------------------|---------------------------------|---------------------|--------------------------------------------------------------------|
| **Pre-shifted**             | **O(frames × N)** — prohibitive | low (byte blit)     | N = 2/4/8; multiplies *every* frame of *every* sprite              |
| **Realtime shift** (chosen) | **O(small fixed tables)**       | higher (shift+mask) | SP1/JSP model; cost scales with on-screen sprites, not asset count |
| **Compiled**                | O(code per image)               | lowest              | huge code size; impractical for a general engine                   |

For an engine like RAGE1 with many animation frames across many sprites, the
**memory blow-up of pre-shift is the deciding factor**: realtime shifting trades
a manageable per-frame CPU cost for a fixed, tiny memory cost. This is precisely
the trade SP1 and JSP already make on ZX, and it has shipped countless smooth ZX
games — so it is a proven, accepted economics for RAGE1.

---

## 11. Decision

1. **Pre-shifting is rejected** — too expensive memory-wise for a multi-frame
   engine.
2. **RAGE1 CPC will use realtime shifting + masking — the SP1/JSP model.** Fixed
   shift logic (small LUTs / mask-ops) instead of per-sprite copies; per-frame CPU
   cost accepted.
3. **The sprite engine is JSP.** Rather than grow a bespoke shifting blitter
   inside RAGE1, **add CPC support to JSP** (Jorge's own sprite library, which
   already does realtime-shift masked sprites on ZX and shares SP1's data format —
   see the `project_jsp_sprite_format` memory). RAGE1's CPC sprite path then
   becomes a **thin JSP backend**, mirroring how RAGE1 already consumes SP1/JSP on
   ZX. The cross-platform seam stays at "RAGE1 gfx backend → sprite library",
   never smeared into engine code.

### 11.1 The JSP-CPC port surface — high-level architecture is UNCHANGED

This is the decisive architectural point: **the CPC port of JSP keeps JSP's
entire high-level architecture identical to the ZX version.** JSP is already
structured as a platform-agnostic engine sitting on a thin platform layer; only
that thin layer is swapped. Concretely:

**Reused verbatim from the ZX JSP (the high-level engine):**
- the off-screen **shadow / tile buffer** and **dirty-cell tracking**;
- the **sprite list / allocation / update** model;
- the **compositing flow** (validate → recomposite changed cells → flush);
- **background restore** (a consequence of the shadow buffer — see §9);
- the **public API** RAGE1 calls, and the **sprite data format**;
- the overall frame/update lifecycle.

**Swapped for CPC (the only delta — the thin platform layer):**
- the **realtime shift tables / functions**, per mode (§8: M2 rotate, M1 nibble,
  M0 interleave);
- the **pixel encoding** (planar-in-byte, §4) used when packing cells to bytes;
- the **screen-address arithmetic** (CPC's interleaved scan-line layout / CRTC
  paging) instead of the ZX screen map;
- the **mask format / composite** at the byte level (§8.4).

So the JSP-CPC effort is bounded and well-understood: **change the shifting and
the byte/screen plumbing; inherit everything above it.** This is exactly why
routing CPC sprites through JSP (rather than a bespoke RAGE1 blitter) is the right
call — the smooth-movement architecture already exists and is proven; CPC only
needs its low-level pixel layer filled in.

---

## 12. Strategic plan

1. **PARK** RAGE1 CPC sprite work. `engine/src/gfx_cpctel.c` cell-granular
   rendering remains the **interim** CPC backend; do not invest further in making
   it smooth.
2. **Parallel project: add CPC support to JSP.** Realtime-shift, not pre-shift.
   Recommended order:
   1. **Mode 2** first — 1bpp linear, the existing ZX bit-shift core ports almost
      verbatim (§8.1). Lowest-risk way to stand up the CPC pipeline end-to-end.
   2. **Mode 1** — planar nibble shift (§8.2). The primary RAGE1 CPC target today
      (the engine currently runs MONO/Mode-1).
   3. **Mode 0** — odd/even interleave shift (§8.3), for 16-colour games.
   - Keep JSP's high-level architecture **unchanged**; only fill in the per-mode
     platform layer (shift, encoding, screen addressing, mask — §11.1). Background
     restore comes free with the reused shadow buffer.
3. **Return to RAGE1** CPC port and wire **JSP-in-CPC-mode as the CPC sprite
   engine** — a thin `gfx` backend dispatching to JSP, replacing the interim
   `gfx_cpctel` sprite path.
4. **Amend the plan:** update gfx.md **G8-5** so "cell-granular / functional only"
   stops reading as the finish line, and add an explicit *"pixel-smooth CPC sprite
   movement via JSP-CPC"* requirement + design task to `cpc-renderer.md` / `gfx.md`.

---

## 13. Open design decisions (to resolve when the work resumes)

### RAGE1-side

- **CPC sprite asset format — emit it.** JSP-CPC **defines** the CPC sprite + mask
  byte format (per mode); RAGE1's **datagen must emit that format** for CPC builds,
  exactly as it already emits SP1/JSP sprite data on ZX. The format is designed in
  JSP; RAGE1 follows it. Unit-test the §8 shift masks against the agreed format.

### JSP-side (owned and resolved in the JSP-CPC project — NOT RAGE1's to decide)

Listed only for context; these are internal to JSP and do not belong to RAGE1:

- **Shift implementation form** — inline mask-ops vs LUT-per-phase vs LUT
  everywhere.
- **Per-mode shift paths / mode support** — which of M0/M1/M2 are first-class, and
  any "2px-Mode-0 good enough" fast path.
- **Compositing model** — **DECIDED:** direct-to-screen, **no** double buffer.
  Some tearing is accepted; there is **no flicker** because the masked-composite
  model writes each cell once (`screen = (screen & mask) | pixels`), with no
  erase→redraw gap. **No ISR coupling** on cpc-flat: the blitter (main loop, video
  RAM) and the ISR (timer + Arkos AY player, PSG) share no hardware and no mutable
  state; the ISR may preempt a blit but is fully register-clean (`cpc_fast_isr`
  saves IX/IY/AF/BC/DE/HL + the shadow set), so the blit is oblivious to it. The
  only residual coupling is future cpc-banked bank-switching, handled by the
  `interrupt_nesting_level` interlock (banking.md §3.5.1).
- **Background-restore mechanism** — inherited from JSP's existing shadow-buffer
  architecture (§9, §11.1).

---

## 14. References / sources

Local source (verified directly):
- `engine/src/gfx_cpctel.c` — current cell-granular CPC renderer.
- `external/cpctelera/` — `cpct_getScreenPtr.asm` (x in bytes), `cpct_drawSprite*`,
  no sub-byte shift routine.
- `~/src/spectrum/z88dk/libsrc/target/cpc/cpcrslib/sprites/` — CPCRSLib byte-aligned
  sprites; `…/graphics/` — plot/putsprite.
- `doc/multiplatform-plan/gfx.md` (G8-5 functional bar), `cpc-renderer.md`.

Wider CPC ecosystem:
- [CPCWiki — Programming: Fast Sprites](https://www.cpcwiki.eu/index.php/Programming:Fast_Sprites)
- [cpctech (cpcwiki.de) — Sprites](https://cpctech.cpcwiki.de/docs/sprites.html)
- [CPCWiki — Video modes](https://www.cpcwiki.eu/index.php/Video_modes)
- [CPCtelera — Smooth 1-pixel Mode 0 movement (demo)](https://www.youtube.com/watch?v=bEkf95Q2puk)
- [CPCtelera docs — drawSpriteMasked / asset conversion](http://lronaldo.github.io/cpctelera/files/sprites/cpct_drawSpriteMasked-s.html)
- [meesterturner/cpcsprite](https://github.com/meesterturner/cpcsprite)
- [AMSprite — CPCWiki](https://www.cpcwiki.eu/index.php/AMSprite)
- [Oli's CPC game prototype (movement notes)](https://www.evolutional.co.uk/post/amstradcpc-game-prototype/)

Related project memory: `project_cpc_sprite_engine_via_jsp`,
`project_jsp_sprite_format`.

---

## Appendix A — 1-pixel right-shift quick reference

| Mode | In-byte contribution | Carry into next byte | Notes |
|------|----------------------|----------------------|-------|
| 2 | `(src >> 1)` | `(src & 0x01) << 7` | linear 1bpp; = ZX rotate |
| 1 | `(src & 0xEE) >> 1` | `(src & 0x11) << 3` | two nibble-planes |
| 0 | `(src & 0xAA) >> 1` | `(src & 0x55) << 1` | odd/even pixel interleave |

Process a row left→right, OR-ing each source byte's in-byte contribution into the
current output byte and its carry into the next; output row is `W+1` bytes. Shift
the mask with the identical operation and composite
`screen = (screen & mask) | pixels`. **Verify masks against the real asset byte
format before use.**

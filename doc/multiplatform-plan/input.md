# Input HAL: `input_*` design + per-platform backends

This document is the Input chapter of the RAGE1 cross-platform plan
(see `doc/multiplatform-plan/README.md` for the parent plan; sibling
docs are `gfx.md`, `audio.md`, `assets.md`, `toolchain.md`,
`cpc-renderer.md`, `banking.md`, `testing.md`). It covers the
audit of the existing input code, the ZX-specific assumptions baked
into it, and the phased work needed to turn it into **the** multi-
platform input HAL — with the current ZX backend (z88dk's `input`
library) and a new Amstrad CPC backend (cpctelera's `keyboard/` module)
sitting behind a single API. The shape mirrors `gfx_*` exactly:
generic `input.h` + per-backend `input_zx.h` / `input_cpc.h`. No second
abstraction layer.

Conventions used in this file:

- Code references use `file_path:line` form.
- Phases are tagged `IN1`, `IN2`, …; tasks within them `IN1-1`, `IN1-2`, …
- "ZX game" = any of the existing `games/*` test games. Their behaviour
  must match the pre-change screenshot regression baseline at every
  phase exit.

Out of scope for this document:

- Graphics HAL (`gfx.md`).
- Audio HAL — including the `audio_*` event surface that
  `CONTROLLER_SELECTED` will eventually route through (`audio.md`).
- Banking and code paging (`banking.md`); we only note ISR/timing
  concerns that banking must coordinate with.
- Build matrix and platform Makefiles (`toolchain.md`); we only note
  the per-platform link-against decisions.
- cpctelera vendoring itself (`cpc-renderer.md`); we only describe
  how to wire its `keyboard/` module.
- Asset overlay copy mechanism (`assets.md`); we only describe how
  per-platform input config files (if any) ride that mechanism.

---

## 1. Current state audit

### 1.1 Input code in `engine/` (file map)

The input code surface in RAGE1 today is **tiny** — that is a
significant finding by itself, and the main reason this HAL effort is
much smaller than `gfx.md`'s. The complete inventory:

**Engine files dedicated to input:**

- `engine/src/controller.c` — 47 lines total. Defines
  `init_controllers()`, `controller_read_state()`,
  `controller_pause_key_pressed()`, `controller_reset_all()`. Pulls in
  `<input.h>` (z88dk's input library) plus `rage1/controller.h`.
- `engine/include/rage1/controller.h` — 47 lines total. Declares
  `struct controller_info_s { uint8_t type; struct udk_s keys;
  uint8_t state; }`, controller-type enum (`CTRL_TYPE_UNDEFINED`,
  `_KEYBOARD`, `_KEMPSTON`, `_SINCLAIR1`), and default-keyboard-key
  macros (`KBD_UP = IN_KEY_SCANCODE_q` etc.).

**Engine files that consume the input result:**

- `engine/src/main.c:49` — calls `init_controllers()` once at boot;
  `:83-84` calls `in_wait_key()` / `in_wait_nokey()` under
  `BUILD_FEATURE_LOADING_SCREEN_WAIT_ANY_KEY`.
- `engine/src/game_loop.c:39-43,112-114,230` — calls
  `controller_pause_key_pressed()`, `in_wait_nokey()`, and per-frame
  `check_controller()` → `controller_read_state()`.
- `engine/src/debug.c:62-65` — `debug_waitkey()` wraps
  `in_wait_key()` + `in_wait_nokey()`.
- `engine/src/hero.c:170,183,190` — reads
  `game_state.controller.state & IN_STICK_FIRE` for weapon logic.
- `engine/banked_code/common/hero.c:13,116,154,…,239` — reads
  `game_state.controller.state & MOVE_ALL` and tests against
  `MOVE_UP`/`MOVE_DOWN`/`MOVE_LEFT`/`MOVE_RIGHT` for hero motion.
  `<input.h>` is included **only** for the `IN_STICK_*` masks.
- `engine/include/rage1/hero.h:43-47` — defines
  `MOVE_UP/_DOWN/_LEFT/_RIGHT` as aliases for `IN_STICK_UP`/`_DOWN`/
  `_LEFT`/`_RIGHT`; `MOVE_ALL = (MOVE_UP | MOVE_DOWN | MOVE_LEFT |
  MOVE_RIGHT)`. This is the single most important coupling point
  between input semantics and the rest of the engine.

**No engine-side controller-selection menu**. The menu that lets the
player pick "Keyboard / Kempston / Sinclair / Redefine" is **per-game
custom code**, not part of the engine — see
`games/default/game_src/game_functions.c:42-149` and
`games/minimal/game_src/menu.c:6-8`. The engine just exposes
`game_state.controller.type` and `game_state.controller.keys`; the
game's `GAME_FUNCTION TYPE=MENU` is responsible for setting them
before the main game loop runs.

**Per-game input helpers:**

- `games/default/game_src/kbd.c:6-46` — `capture_key_scancode()`:
  inline-assembly per-row keyboard scan that returns a z88dk-style
  scancode `(row_port_byte << 8) | (1<<bit)` so it can be stored into
  `game_state.controller.keys.{up,down,left,right,fire}` and read by
  `in_stick_keyboard()`. Hard-codes the 8 ZX row ports
  `{0xf7,0xfd,0xfb,0xfe,0xef,0xdf,0xbf,0x7f}` and `IN ($FE)`.
- `games/default/game_src/kbd.h` — one-line prototype.
- `games/default_jsp/game_src/kbd.{c,h}` — near-identical copy of the
  `default` helper. **These are the only two games** that carry their
  own `kbd.c`/`kbd.h`. Verified via `find games -name "kbd.*"` and
  `grep -l 'capture_key_scancode' games/*/game_src/*`. The other
  games with a non-trivial controller-selection menu (`blobs`,
  `crumbs`, `damage_mode`, `get_weapon`, `monochrome`, `vortex2`) do
  **not** ship a `kbd.c` and do **not** call
  `capture_key_scancode()`; their `game_functions.c` menus stop at
  "1: KEYBOARD / 2: KEMPSTON / 3: SINCLAIR" with no Option-4
  ("Redefine") capture path. The `kbd.c` duplication seam is
  therefore narrow (two files), see Phase IN4. (The wider
  *menu-text-and-dispatch* duplication across the 8 games with a
  non-trivial menu is a different concern, tracked separately in
  Risk R7.)

**No engine `menu.c`/`menu.h`** — confirmed via
`find engine -name "menu.*"`. Menu is always per-game.

**Total active direct z88dk `in_*` call sites in engine:** **10** —
4 in `controller.c` (lines 34, 35, 36, 42), 2 in `main.c` (83-84), 2
in `game_loop.c` (40, 42), 2 in `debug.c` (63-64). The three sites in
`engine/src/hero.c` (170, 183, 190) are **reads of
`game_state.controller.state`**, not direct `in_*` calls, and so are
not part of this count. Plus the read-only consumption of the
controller-state byte in banked hero code (see §1.5 for the full
enumeration). The HAL surface is small.

### 1.2 ZX keyboard scanning (per-row I/O ports)

The ZX Spectrum has an 8-row × 5-column keyboard matrix mapped to the
ULA `IN ($FE)` port. The high byte of the port address selects the
row: each row is selected by holding a different one of A8–A15 low,
giving 8 row ports `0xFEFE`, `0xFDFE`, `0xFBFE`, `0xF7FE`, `0xEFFE`,
`0xDFFE`, `0xBFFE`, `0x7FFE`. The low 5 bits of the input byte are 0
for "key pressed", 1 for "not pressed".

RAGE1's *engine* does not implement this scan directly — it goes
through z88dk's `<input.h>` library
(`/home/jorgegv/src/spectrum/z88dk-jorgegv/include/_DEVELOPMENT/clang/input/input_zx.h`),
which provides:

- `in_inkey()` — instantaneous ASCII of any single key currently down.
- `in_key_pressed( uint16_t scancode )` — test one specific (row, bit)
  pair (the 16-bit "scancode" packs `(row_port_byte << 8) |
  inverted_bitmask`).
- `in_key_scancode( int c )` — convert ASCII → scancode.
- `in_wait_key()` / `in_wait_nokey()` / `in_test_key()` — block/poll.
- `in_pause( uint16_t dur_ms )` — busy-wait, early-out on keypress.
- `IN_KEY_SCANCODE_a` … `IN_KEY_SCANCODE_z` (and digits, ENTER,
  SPACE, CAPS, SYM, ANYKEY, DISABLE) — pre-baked scancodes.

The per-game `kbd.c` helper does its **own** raw scan to capture an
arbitrary key in `(row_port << 8) | bit` form, because z88dk's
`in_inkey()` returns ASCII (lossy: e.g. shifted keys) and not the
16-bit scancode shape that `in_stick_keyboard()` consumes. The raw
scan in `games/default/game_src/kbd.c:6-46` is the lowest-level ZX
keyboard hardware contact in the entire codebase.

### 1.3 ZX joysticks: Kempston, Sinclair, Cursor

z88dk's `input_zx.h` exposes five joystick "read" functions, all of
which return a single byte in the format
`(IN_STICK_FIRE | IN_STICK_RIGHT | IN_STICK_LEFT | IN_STICK_DOWN |
IN_STICK_UP)` active-high (the bit layout
`0x80, 0x08, 0x04, 0x02, 0x01` defined at
`input.h:38-46`):

- `in_stick_keyboard( udk_t *u )` — reads 5 user-defined ZX scancodes
  from the supplied `udk_t` (the same struct embedded into
  `controller_info_s`).
- `in_stick_kempston()` — reads Kempston joystick at I/O port `$1F`
  (or `$5F`/`$7F` mirrors); bit 0..4 = U/D/L/R/Fire active-**high**.
- `in_stick_sinclair1()` — emulates joystick by reading keys
  `6/7/8/9/0` (one of the two "Interface 2" mappings).
- `in_stick_sinclair2()` — emulates joystick by reading keys
  `1/2/3/4/5`.
- `in_stick_cursor()` — emulates joystick by reading keys
  `5/6/7/8` plus `0` for fire (the "Protek" / "AGF" cursor mapping).
- `in_stick_fuller()` — Fuller box, port `$7F`.

RAGE1 wires three of these into `controller_read_state()` at
`engine/src/controller.c:32-39`:

```c
case CTRL_TYPE_KEYBOARD:  return in_stick_keyboard( &game_state.controller.keys );
case CTRL_TYPE_KEMPSTON:  return in_stick_kempston();
case CTRL_TYPE_SINCLAIR1: return in_stick_sinclair1();
```

`CTRL_TYPE_SINCLAIR2`, `CTRL_TYPE_CURSOR`, `CTRL_TYPE_FULLER` are
**not** currently wired. The engine knows only the three. Adding them
on ZX is one trivial `case` per joystick; this is **not** part of the
multiplatform plan but is noted as a small Phase IN6 follow-up.

The key shape from the engine's perspective: **all read functions
return one byte with the same `IN_STICK_*` bit layout, polling-only
(no edge events), one read per game frame**. This shape is
fundamentally portable; the multiplatform task is mostly about
renaming and unforking the joystick-type vocabulary.

### 1.4 Controller selection menu + `.gdata` SOUND

**No engine-side menu.** The controller-selection screen is authored
per-game in user C code, supplied to the engine via the
`GAME_FUNCTION TYPE=MENU` directive in `Game.gdata` (see
`doc/DATAGEN.md:557`). Two representative implementations:

- **Full menu with Redefine** (`games/default/game_src/game_functions.c:42-149`
  and `games/default_jsp/`):
  - Draws "1: KEYBOARD / 2: KEMPSTON / 3: SINCLAIR / 4: REDEFINE".
  - Loops on `in_inkey()`, dispatches `'1'..'4'`.
  - Option `1`-`3`: sets `game_state.controller.type =
    CTRL_TYPE_KEYBOARD|KEMPSTON|SINCLAIR1`.
  - Option `4` ("Redefine"): calls `capture_key_scancode()` five
    times (Up, Down, Left, Right, Fire), storing into
    `game_state.controller.keys.{up,down,left,right,fire}`. Plays
    `SOUND_CONTROLLER_SELECTED` (a beepfx ID) after each capture, with
    a 500 ms `in_pause()`.
- **3-option menu without Redefine** (`games/blobs/`, `games/crumbs/`,
  `games/damage_mode/`, `games/get_weapon/`, `games/monochrome/`,
  `games/vortex2/` — all near-identical):
  - Draws "1: KEYBOARD / 2: KEMPSTON / 3: SINCLAIR" — no Option 4.
  - Loops on `in_inkey()`, dispatches `'1'..'3'`.
  - Sets `game_state.controller.type` as above. No `kbd.c`/`kbd.h`
    in these games; no `capture_key_scancode()` call.
- **Trivial menu** (`games/minimal/game_src/menu.c:6-8`): just sets
  `game_state.controller.type = CTRL_TYPE_KEYBOARD` and returns. Used
  for compactness in test games where input UX is uninteresting.

**The `CONTROLLER_SELECTED` SOUND ID** is one of the seven game-event
sound symbols declared in `BEGIN_GAME_CONFIG` (see
`doc/DATAGEN.md:622`). It is **declared centrally** but **played by
user code**, not by the engine — `engine/` has no reference to
`SOUND_CONTROLLER_SELECTED`. The symbol is emitted by
`tools/datagen.pl:3313` as a `#define SOUND_CONTROLLER_SELECTED
<value>` in the generated header, where `<value>` is the right-hand-
side of `SOUND CONTROLLER_SELECTED=BEEPFX_ITEM_3` (or whatever
constant the game chose) in `Game.gdata`.

This is significant for multiplatform: the SOUND ID *event* is
gameplay-shared, but the *symbol* on the right-hand-side is platform-
specific (`BEEPFX_*` is beeper-only; CPC will need Arkos AY IDs). See
the `audio.md` cross-reference in §3.5 below.

### 1.5 Caller inventory: where the engine reads input

Comprehensive grep across `engine/src/`, `engine/include/`,
`engine/banked_code/`, `engine/lowmem/` (`grep -rn 'in_inkey\|in_pause\
|in_wait_nokey\|in_wait_key\|in_test_key\|in_key_pressed\|in_stick_\|
in_key_scancode\|controller_\|IN_STICK_\|IN_KEY_SCANCODE_\|udk_s\|
CTRL_TYPE_' engine/`):

**Direct calls into z88dk's `input.h`** (these are what need a HAL
indirection):

- `engine/src/controller.c:34` — `in_stick_keyboard( &game_state.controller.keys )`
- `engine/src/controller.c:35` — `in_stick_kempston()`
- `engine/src/controller.c:36` — `in_stick_sinclair1()`
- `engine/src/controller.c:42` — `in_key_pressed( IN_KEY_SCANCODE_y )`
- `engine/src/main.c:83-84` — `in_wait_key()` / `in_wait_nokey()`
- `engine/src/game_loop.c:40,42` — `in_wait_nokey()`
- `engine/src/debug.c:63-64` — `in_wait_key()` / `in_wait_nokey()`

**Reads of `game_state.controller.state`** (state-byte consumers, all
via `IN_STICK_*` / `MOVE_*` masks):

- `engine/src/hero.c:170,183,190` — fire-button edge detection.
- `engine/banked_code/common/hero.c:116,154,173,195,215,239` — full
  4-way movement decoding.
- `engine/src/game_loop.c:113` — assigns
  `game_state.controller.state = controller_read_state()`.

**Reads of `game_state.controller.type`** (rare):

- `engine/src/controller.c:33` — the `switch` in `controller_read_state`.
- Various `games/*/game_src/game_functions.c` and `menu.c` — set
  `game_state.controller.type` from user-code menu logic.

**Reads of `game_state.controller.keys`** (also rare):

- `engine/src/controller.c:24-28` — `init_controllers()` writes
  defaults into `keys.{up,down,left,right,fire}`.
- `engine/src/controller.c:34` — passes `&...controller.keys` to
  `in_stick_keyboard`.
- Various `games/*/game_src/game_functions.c` — write captured
  scancodes into `keys.{up,…,fire}` during "Redefine".

**Notable absences**:

- **No flow rule** in any test game tests keyboard state directly —
  confirmed by `grep -rn 'USER_KEY\|in_key\|in_stick' engine
  tools/datagen.pl doc/DATAGEN.md`. Flow rules read game flags, items,
  hotzones, lives — not raw input. This is excellent news: the
  HAL change does not need to touch the flow-rule vocabulary.
- **No banked code that calls `in_*` directly**. Banked
  `engine/banked_code/common/hero.c` includes `<input.h>` only for
  the `IN_STICK_*` constants (`MOVE_*` aliases). Once those constants
  come from `rage1/input.h`, the `<input.h>` include can be dropped.
  See Phase IN3.
- **No engine code reads keyboard rows directly**. All ZX-hardware-
  level coupling is concentrated in z88dk's `input` library, which is
  exactly the right shape for replacing it per-backend.

**Total active engine input touch-points: 10 direct z88dk `in_*`
calls + 1 banked include + ~10 reads of
`controller.state/type/keys`**. The 10 direct calls break down as: 4
in `controller.c` (`in_stick_keyboard`, `in_stick_kempston`,
`in_stick_sinclair1`, `in_key_pressed`), 2 in `main.c`
(`in_wait_key`, `in_wait_nokey`), 2 in `game_loop.c` (two
`in_wait_nokey`), 2 in `debug.c` (`in_wait_key`, `in_wait_nokey`).
Much smaller surface than `gfx_*` (~45 calls in 12 files). The HAL
refactor is correspondingly cheaper.

---

## 2. ZX-specific assumptions

The following assumptions are baked into the input contract today.
Each must be addressed by the HAL design in §3.

1. **z88dk's `<input.h>` is the de facto input HAL today.** Every
   engine input call is a thin wrapper on z88dk. z88dk's `input`
   subsystem has a *cross-platform* layer (the documented
   `in_GetKey`/`in_KeyPressed`/`in_JoyKeyboard` family, see
   `/home/jorgegv/src/spectrum/z88dk-original-2.3/include/input.h`)
   plus platform-specific extensions for each target (Spectrum,
   SAM, SMS, …). On paper z88dk could also serve CPC, but its `+cpc`
   joystick offering is minimal compared with cpctelera's keyboard
   module — and we have already chosen cpctelera as the CPC graphics
   backend. We **do not** rely on z88dk's portability claim for input.

2. **Per-row I/O port pattern** is hard-coded in user game code
   (`games/default/game_src/kbd.c:4`), as the array
   `{0xf7, 0xfd, 0xfb, 0xfe, 0xef, 0xdf, 0xbf, 0x7f}` of high-byte
   row selectors for `IN ($FE)`. This is ZX-specific. CPC reads its
   keyboard via the 8255 PPI, **not** via direct row I/O ports — its
   matrix has 10 lines selected through port B / port C of the PPI
   driving the AY-3-8912's I/O port.

3. **Kempston joystick at port `$1F`**. ZX-specific hardware. The
   constant lives inside z88dk's `in_stick_kempston()`; engine code
   does not see it directly. CPC has built-in DB-9 joystick ports
   exposed via keyboard-matrix rows 9 (Joy0) and 6 (Joy1) — entirely
   different hardware decoding.

4. **Sinclair joystick is a key-emulation pseudo-stick** (keys
   `6/7/8/9/0` for Sinclair 1; `1/2/3/4/5` for Sinclair 2). Has no
   CPC equivalent. Direct port to CPC would mean "the player is
   pressing 5 specific Locomotive-keyboard keys" — but that's already
   covered by the keyboard-with-user-defined-keys path on CPC. The
   `CTRL_TYPE_SINCLAIR1` constant is therefore ZX-only by definition.

5. **Polling-only model**: input is read **once per game frame**
   inside `check_controller()` (`engine/src/game_loop.c:113`). No
   edge events, no key-repeat from the input layer, no interrupt-
   driven keyboard handler in RAGE1. `game_state.controller.state` is
   the only persistent per-frame state. Fire-button edge detection in
   `engine/src/hero.c:183-191` is implemented as "compare current
   `IN_STICK_FIRE` bit against `game_state.bullet.firing`". This
   model is **portable** to CPC, as long as the CPC backend updates
   its keyboard buffer before each `check_controller()` call. Note
   that cpctelera's `cpct_scanKeyboard` is **costly** (212 µs / 848
   T-states) and must be called *exactly once per frame*, not every
   `gfx_*` macro invocation. See §3.1's API for the explicit
   "begin-of-frame scan" entrypoint.

6. **State-byte bit packing**: `IN_STICK_UP=0x01`, `IN_STICK_DOWN=0x02`,
   `IN_STICK_LEFT=0x04`, `IN_STICK_RIGHT=0x08`, `IN_STICK_FIRE=0x80`,
   `IN_STICK_FIRE_2=0x40`, `IN_STICK_FIRE_3=0x20` (z88dk `input.h:38-46`).
   Aliased in RAGE1 as `MOVE_UP`/`MOVE_DOWN`/`MOVE_LEFT`/`MOVE_RIGHT`
   (`engine/include/rage1/hero.h:43-46`) plus `MOVE_NONE=0` and
   `MOVE_ALL=0x0F`. This packing is a *convention*, not a hardware
   requirement; it just happens to match the Kempston port byte
   layout. **We keep this layout** for the HAL — it is convenient and
   compact — but we re-publish the constants under the
   `INPUT_STATE_*` / `input_state_t` namespace so engine code stops
   needing `<input.h>` directly.

7. **`udk_t` (z88dk's struct) embedded into engine state.**
   `engine/include/rage1/controller.h:23` declares
   `struct udk_s keys` as a field of `controller_info_s`. The struct
   has 5 `uint16_t` scancodes (`fire, right, left, down, up`) shaped
   for `in_stick_keyboard()` consumption. This is a leaky abstraction:
   the *engine state* knows that the controller stores "z88dk-shaped
   scancodes". On CPC the equivalent is a `cpct_keyID` (also 16 bits,
   but with different layout: low byte = matrix line 0-9, high byte =
   bit mask). The HAL needs an **opaque per-backend scancode type**
   (`input_scancode_t`) and a per-backend `input_udk_t` struct.

8. **`IN_KEY_SCANCODE_y` (pause key) is hard-coded** at
   `engine/src/controller.c:42`. ZX-specific. On CPC there is a
   matching constant (`Key_Y`) but the engine code that knows the
   identity of the pause key shouldn't have to name a platform-
   specific scancode at compile time. **Lift to a HAL-supplied
   `INPUT_SCANCODE_PAUSE`** (a backend-defined macro that resolves to
   the platform-correct scancode) — see §3.1.

9. **`IN_KEY_SCANCODE_q`, `_a`, `_o`, `_p`, `_SPACE`** are referenced
   in `engine/include/rage1/controller.h:29-33` as the default
   redefinable-keyboard mapping (Up/Down/Left/Right/Fire). They are
   reasonable defaults on a ZX layout (Q/A = up/down, O/P = left/
   right, Space = fire — the classic ZX game layout). On CPC the
   equivalent intuitive defaults are different (cursor keys + Space,
   or O/P + Q/A + Space — there is some convention overlap). The
   per-game custom defaults belong in `.gdata`, not in the engine
   header; see §3.4.

10. **Beeper-only sound IDs.** `SOUND CONTROLLER_SELECTED=BEEPFX_*` in
    every game's `Game.gdata`. On CPC the SFX bank is Arkos / AY-
    native. The event mapping (which gameplay events trigger sounds)
    is shared; the SFX *symbol* values are per-platform. Belongs to
    `audio.md`; flagged here because the `CONTROLLER_SELECTED` event
    is fired from the input subsystem's downstream code.

11. **No `IN_KEY_SCANCODE_*` mention of CAPS SHIFT / SYM SHIFT
    combinations in engine code**, but the `kbd.c` raw scan can
    return a CAPS / SYM scancode if the player presses them. The
    "Redefine" UI accepts whatever the player presses. On CPC the
    equivalent modifier keys (CTRL, SHIFT) exist; cpctelera's
    `cpct_keyID` covers them. No engine-side change needed.

---

## 3. `input_*` HAL design

The shape mirrors `gfx_*` exactly:

- **`engine/include/rage1/input.h`** — the public HAL. Engine code
  `#include`s only this header for input.
- **`engine/include/rage1/input_zx.h`** — ZX backend header. Maps the
  HAL surface to z88dk's `<input.h>` library calls.
- **`engine/include/rage1/input_cpc.h`** — CPC backend header. Maps
  the HAL surface to cpctelera's `cpctelera/src/keyboard/` calls.
- Backends select via `BUILD_FEATURE_INPUT_BACKEND_ZX` /
  `BUILD_FEATURE_INPUT_BACKEND_CPC` (the analogue of
  `BUILD_FEATURE_GFX_BACKEND_*` from `gfx.md`). The macro is emitted by
  `tools/datagen.pl` from `PLATFORM` (zx48/zx128 → ZX backend,
  cpc464/cpc6128 → CPC backend; see §3.2 for the matrix).
- Anywhere the HAL needs a multi-step real function (analogue of
  `gfx_init` etc.), the body lives in `engine/src/input.c` and is
  guarded by `#ifdef BUILD_FEATURE_INPUT_BACKEND_*`. Most of the HAL
  resolves at preprocessing time via macros — same pattern as
  `gfx_sp1.h` / `gfx_jsp.h`.

### 3.1 API surface (function by function)

Below, every operation the engine needs, with proposed signature and
classification (a/b/c from §2.2 of `gfx.md`):

| Operation | Proposed signature | Class | Notes |
|---|---|---|---|
| **Init / lifecycle** | | | |
| `input_init()` | `void input_init( void )` | **(b) generalisable** | ZX: no-op (z88dk needs no init). CPC: zero `cpct_keyboardStatusBuffer[]`, set up firmware-disable if running with `cpct_disableFirmware()` (depends on cpc-renderer's mode). |
| `input_shutdown()` | `void input_shutdown( void )` | **(b)** | ZX: no-op. CPC: restore firmware/interrupt state if needed. Probably unused (RAGE1 owns the machine until reset). |
| **Per-frame scan (the explicit polling-point)** | | | |
| `input_scan()` | `void input_scan( void )` | **(b)** *new* | ZX: no-op (z88dk's `in_stick_*` reads ports synchronously every call). CPC: calls `cpct_scanKeyboard()` (or `_f`/`_i`/`_if` per choice — see §4) and refreshes `cpct_keyboardStatusBuffer[]`. Engine calls `input_scan()` **once per frame**, before any `input_state_read()` / `input_key_pressed()` / `input_inkey()`. This is **the key shape difference** that the HAL imposes: CPC needs a separate "scan now" call; ZX gets a no-op. |
| **Joystick / movement state read** | | | |
| `input_state_read( type, udk )` | `input_state_t input_state_read( uint8_t type, input_udk_t *udk )` | **(b)** | Reads the *current* state byte in `INPUT_STATE_*` bit packing. `type` is one of `CTRL_TYPE_*` (see §3.3); `udk` is the user-defined-keys struct (used only for `CTRL_TYPE_KEYBOARD`; backends ignore it otherwise). |
| **Single-key query** | | | |
| `input_key_pressed( scancode )` | `uint8_t input_key_pressed( input_scancode_t scancode )` | **(c) ZX-specific signature** | `input_scancode_t` is `uint16_t` on both backends but the encoding differs. ZX → `in_key_pressed(scancode)`. CPC → `cpct_isKeyPressed( (cpct_keyID)scancode )`. |
| **Single-key ASCII** | | | |
| `input_inkey()` | `uint16_t input_inkey( void )` | **(b)** | Returns ASCII of any single key down, 0 if none/ambiguous. ZX → `in_inkey()`. CPC → walk the buffer + a small ASCII translation table (cpctelera does not expose `inkey`-equivalent directly; the backend implements it in ~30 lines). |
| **Wait / pause** | | | |
| `input_wait_key()` | `void input_wait_key( void )` | **(a)** | Block until any key down. Both backends already have this. |
| `input_wait_nokey()` | `void input_wait_nokey( void )` | **(a)** | Block until no keys down. Both already have it. |
| `input_test_key()` | `uint8_t input_test_key( void )` | **(a)** | "Is *any* key currently pressed?" ZX → `in_test_key()`. CPC → `cpct_isAnyKeyPressed_f()`. |
| `input_pause( ms )` | `uint16_t input_pause( uint16_t ms )` | **(b)** | Busy-wait `ms` milliseconds, early-out on keypress, return remaining. ZX → `in_pause(ms)`. CPC → custom loop calling `cpct_scanKeyboard_f()` + `cpct_isAnyKeyPressed_f()`, calibrated for CPC clock speed (4 MHz vs ZX's 3.5469 MHz). |
| **Scancode lookup / capture** | | | |
| `input_lookup_key( ascii )` | `input_scancode_t input_lookup_key( uint8_t ascii )` | **(b)** | Convert ASCII → backend scancode for `udk_t` population (so user-game menus do not name `IN_KEY_SCANCODE_q` directly). ZX → `in_key_scancode(c)`. CPC → small ASCII→`cpct_keyID` lookup table. |
| `input_capture_scancode()` | `input_scancode_t input_capture_scancode( void )` | **(b)** *new* | Wait for one key press, return its backend-shaped scancode. Replaces the per-game `capture_key_scancode()` helper duplicated across 7 games (see Phase IN6). ZX: equivalent of the inline-asm scan in `games/default/game_src/kbd.c`. CPC: scan + walk the 10-byte buffer for the first 0-bit. |
| **Pause-key convenience** | | | |
| `input_pause_key_pressed()` | `uint8_t input_pause_key_pressed( void )` | **(b)** | Was the pause key (`INPUT_SCANCODE_PAUSE`) pressed this frame? Backend-defined which key that is — default `Y` on ZX (existing behaviour), default `H` or `P` on CPC (decision in Open Question Q3). |

**New types**:

```c
// engine/include/rage1/input.h   (public, opaque-to-callers)
typedef uint8_t  input_state_t;       // packed INPUT_STATE_* bits, 1 byte
typedef uint16_t input_scancode_t;    // backend-defined encoding
typedef struct input_udk_s input_udk_t; // backend-defined layout
```

**New constants** (defined in `input.h`, identical-valued on both
backends — these are the *byte-packing* convention, see §2 item 6):

```c
#define INPUT_STATE_UP      0x01
#define INPUT_STATE_DOWN    0x02
#define INPUT_STATE_LEFT    0x04
#define INPUT_STATE_RIGHT   0x08
#define INPUT_STATE_FIRE    0x80
#define INPUT_STATE_FIRE_2  0x40
#define INPUT_STATE_FIRE_3  0x20
#define INPUT_STATE_NONE    0x00
#define INPUT_STATE_DIRS    ( INPUT_STATE_UP | INPUT_STATE_DOWN | \
                              INPUT_STATE_LEFT | INPUT_STATE_RIGHT )
```

`MOVE_*` (`engine/include/rage1/hero.h:43-47`) becomes aliases of
the `INPUT_STATE_*` values (one-line change, keeps banked
`hero.c` semantically identical).

### 3.2 Backend split: ZX, CPC (and macro family)

**`input_zx.h`** (sketch):

```c
#include <input.h>                              // z88dk
typedef struct udk_s         input_udk_t;        // z88dk's struct

#define INPUT_SCANCODE_PAUSE       IN_KEY_SCANCODE_y
#define INPUT_SCANCODE_DEFAULT_UP    IN_KEY_SCANCODE_q
#define INPUT_SCANCODE_DEFAULT_DOWN  IN_KEY_SCANCODE_a
#define INPUT_SCANCODE_DEFAULT_LEFT  IN_KEY_SCANCODE_o
#define INPUT_SCANCODE_DEFAULT_RIGHT IN_KEY_SCANCODE_p
#define INPUT_SCANCODE_DEFAULT_FIRE  IN_KEY_SCANCODE_SPACE

// macros that resolve at preprocessing time
#define input_scan()                  ((void)0)
#define input_wait_key()              in_wait_key()
#define input_wait_nokey()            in_wait_nokey()
#define input_test_key()              in_test_key()
#define input_pause( ms )             in_pause( (ms) )
#define input_inkey()                 in_inkey()
#define input_key_pressed( sc )       in_key_pressed( (sc) )
#define input_lookup_key( c )         in_key_scancode( (c) )
// input_state_read, input_capture_scancode: real functions in input.c
```

**`input_cpc.h`** (sketch):

```c
#include <keyboard/keyboard.h>                 // cpctelera (provides
                                               // the `cpct_keyID`
                                               // enum we re-use here)

// CPC scancode encoding (provided by cpctelera's `cpct_keyID` enum):
// low byte = matrix line (0..9), high byte = bit mask within that
// line. We deliberately do NOT redeclare `cpct_keyID` locally to
// avoid shadowing the upstream definition from keyboard/keyboard.h.
//
// Field order matches z88dk's `struct udk_s` (fire, right, left, down,
// up) so user code that previously assigned to `keys.up`/`keys.fire`
// continues to work source-compatibly across both backends.
typedef struct input_udk_s_cpc {
    cpct_keyID fire, right, left, down, up;
} input_udk_t;

#define INPUT_SCANCODE_PAUSE         Key_Y    // see Q3 for default choice
#define INPUT_SCANCODE_DEFAULT_UP    Joy0_Up
#define INPUT_SCANCODE_DEFAULT_DOWN  Joy0_Down
#define INPUT_SCANCODE_DEFAULT_LEFT  Joy0_Left
#define INPUT_SCANCODE_DEFAULT_RIGHT Joy0_Right
#define INPUT_SCANCODE_DEFAULT_FIRE  Joy0_Fire1

// every operation maps to a cpctelera call, or to a helper in input.c
#define input_scan()                  cpct_scanKeyboard_if()
#define input_test_key()              cpct_isAnyKeyPressed_f()
#define input_key_pressed( sc )       cpct_isKeyPressed( (sc) )
// input_wait_key, input_wait_nokey, input_pause, input_inkey,
// input_lookup_key, input_state_read, input_capture_scancode:
// real bodies in input.c (no native cpctelera equivalent for some)
```

**`input.c`** (multi-step real bodies — small file):

- `input_init()` — both backends (ZX: clear `controller_info`; CPC:
  clear `cpct_keyboardStatusBuffer`).
- `input_state_read( type, udk )` — `switch(type) { … }`, dispatches
  per `CTRL_TYPE_*` to the backend's joystick/keyboard read.
- `input_capture_scancode()` — ZX: replaces inline-asm helper from
  `games/default/game_src/kbd.c`. CPC: walks
  `cpct_keyboardStatusBuffer[]`.
- `input_pause()` — both backends (the CPC one cannot trivially be a
  macro because of the early-out-on-key logic).
- `input_wait_key()`, `input_wait_nokey()`, `input_inkey()`,
  `input_lookup_key()` — backend-portable bodies that call the
  primitives above.

**Selection knob** (analogue of
`BUILD_FEATURE_GFX_BACKEND_*` from `gfx.md` §2.8):

- `tools/datagen.pl` emits `BUILD_FEATURE_INPUT_BACKEND_ZX` when
  `PLATFORM ∈ {zx48, zx128}`.
- Emits `BUILD_FEATURE_INPUT_BACKEND_CPC` when
  `PLATFORM ∈ {cpc464, cpc6128}`.
- `engine/include/rage1/input.h` has:
  ```c
  #ifdef BUILD_FEATURE_INPUT_BACKEND_ZX
      #include "rage1/input_zx.h"
  #endif
  #ifdef BUILD_FEATURE_INPUT_BACKEND_CPC
      #include "rage1/input_cpc.h"
  #endif
  ```
- The input backend is **forced by `PLATFORM`**: there is no user
  choice — ZX platforms always get the ZX input backend, CPC
  platforms always get the CPC input backend. This is **different
  from** the graphics backend, which is user-selectable between SP1
  and JSP on ZX via a `.gdata` knob (see `gfx.md` §2.8 for the
  `BUILD_FEATURE_GFX_BACKEND_*` selection logic). Input has no such
  intra-platform fork — the keyboard / joystick hardware is the
  platform.

### 3.3 Controller selection cross-platform

The current ZX controller-type vocabulary
(`engine/include/rage1/controller.h:36-39`) is:

```c
#define CTRL_TYPE_UNDEFINED   0
#define CTRL_TYPE_KEYBOARD    1
#define CTRL_TYPE_KEMPSTON    2
#define CTRL_TYPE_SINCLAIR1   3
```

`KEMPSTON` and `SINCLAIR1` are ZX-only by definition (Kempston is a
specific I/O port; Sinclair is a key-emulation mapping for ZX
joysticks). On CPC the equivalent vocabulary is:

```c
#define CTRL_TYPE_UNDEFINED   0
#define CTRL_TYPE_KEYBOARD    1   // user-defined keys via udk_t
#define CTRL_TYPE_JOY0        4   // CPC built-in joystick port 0 (DB-9)
#define CTRL_TYPE_JOY1        5   // CPC built-in joystick port 1
```

Two design choices:

- **A. One global enum, sparsely populated per platform.** Both
  platforms see the full `CTRL_TYPE_*` enum (values 0-5); a
  platform-specific subset is actually meaningful at runtime. ZX
  `controller_read_state()` returns `INPUT_STATE_NONE` (state byte
  zero) if the user picks a CPC-only type; CPC ditto for ZX-only
  types. This is **simple** but allows nonsense (the user-game menu
  must filter to the right subset per platform anyway).

- **B. Backend-specific enums with overlap.** `CTRL_TYPE_UNDEFINED`
  and `CTRL_TYPE_KEYBOARD` are in `input.h` (cross-platform).
  `CTRL_TYPE_KEMPSTON` / `_SINCLAIR1` live in `input_zx.h`.
  `CTRL_TYPE_JOY0` / `_JOY1` live in `input_cpc.h`. The user-game
  menu code refers to them by name; if it names a constant the
  current platform doesn't define, it gets a clean compile error
  (good!). Per-game menu code is *already* platform-specific in the
  per-platform overlay tree (see `assets.md` §2.5).

**Recommendation: Option B.** The compile-time platform safety is
worth the cost. Per-platform `<platform>/game_src/menu.c` shadowing
(asset-overlay mechanism, `assets.md` §2.2) is already the right
place to keep CPC's "1: KEYBOARD / 2: JOY0 / 3: JOY1 / 4: REDEFINE"
vs ZX's "1: KEYBOARD / 2: KEMPSTON / 3: SINCLAIR / 4: REDEFINE".

The cross-platform constants in `input.h`:

```c
// Shared across all platforms
#define CTRL_TYPE_UNDEFINED   0
#define CTRL_TYPE_KEYBOARD    1

// Reserved range 2-15: platform-specific, defined in input_zx.h / input_cpc.h.
// Values are not portable across platforms — user menus must know which
// constants are meaningful for the current PLATFORM.
```

`controller_info_s` stays platform-portable: `type` is `uint8_t` and
the runtime just dispatches in `controller_read_state()`. The
*meaning* of `type=2` differs per platform; that meaning is
authored per-platform via `game_src/<platform>/menu.c` overlay.

### 3.4 Per-game key mapping under platform overlays

Today `engine/include/rage1/controller.h:29-33` hard-codes default
redefinable keys to `q/a/o/p/SPACE` (ZX). For CPC the obvious defaults
are different — at minimum the user-defined-keys struct needs to be
initialised to CPC-shaped `cpct_keyID` values, not ZX
`IN_KEY_SCANCODE_*` values.

Three options for how the per-game key map travels through the build:

- **A. Engine-supplied defaults only.** `input_init()` sets the
  `udk` field to platform defaults (`INPUT_SCANCODE_DEFAULT_*`). User
  games override by writing to `game_state.controller.keys` from
  their menu code. Existing convention — no change.

- **B. `.gdata` declares default keys.** Add a `CONTROLLER` directive
  in `BEGIN_GAME_CONFIG`:
  ```
  CONTROLLER  KBD_UP=q KBD_DOWN=a KBD_LEFT=o KBD_RIGHT=p KBD_FIRE=SPACE
  ```
  Datagen emits `#define CFG_KBD_UP …` constants used by
  `init_controllers()`. ZX defaults differ from CPC defaults; either
  the `.gdata` author writes platform-portable ASCII (`q`, `SPACE`)
  and datagen converts to backend-specific scancode at build time
  (preferred), or the per-platform overlay `Game.gdata` overrides the
  whole block.

- **C. ASCII-only API.** `engine/include/rage1/controller.h` declares
  defaults in ASCII, not scancode form. `init_controllers()` calls
  `input_lookup_key('q')` etc. to convert at runtime. No `.gdata`
  change needed.

**Recommendation: C (ASCII-only) for the engine defaults**, plus B
(`.gdata CONTROLLER` directive) as an *optional* per-game override.
ASCII is the only platform-portable spelling of a key. The runtime
cost of one `input_lookup_key` call per default-key at `init_controllers`
time is negligible (5 lookups × ~50 cycles each = ~1 ms, once per
game boot).

Concretely, `engine/include/rage1/controller.h` changes from:

```c
#define KBD_UP    IN_KEY_SCANCODE_q
#define KBD_DOWN  IN_KEY_SCANCODE_a
#define KBD_LEFT  IN_KEY_SCANCODE_o
#define KBD_RIGHT IN_KEY_SCANCODE_p
#define KBD_FIRE  IN_KEY_SCANCODE_SPACE
```

to:

```c
#define KBD_DEFAULT_UP    'Q'
#define KBD_DEFAULT_DOWN  'A'
#define KBD_DEFAULT_LEFT  'O'
#define KBD_DEFAULT_RIGHT 'P'
#define KBD_DEFAULT_FIRE  ' '
```

…and `init_controllers()` becomes:

```c
void init_controllers( void ) {
    game_state.controller.keys.up    = input_lookup_key( KBD_DEFAULT_UP );
    game_state.controller.keys.down  = input_lookup_key( KBD_DEFAULT_DOWN );
    game_state.controller.keys.left  = input_lookup_key( KBD_DEFAULT_LEFT );
    game_state.controller.keys.right = input_lookup_key( KBD_DEFAULT_RIGHT );
    game_state.controller.keys.fire  = input_lookup_key( KBD_DEFAULT_FIRE );
    game_state.controller.type       = CTRL_TYPE_UNDEFINED;
}
```

This is **platform-portable**: ZX gets ZX scancodes, CPC gets CPC
`cpct_keyID`s, both via the HAL.

For per-game default-key overrides via `.gdata`, declare them
optional and platform-portable:

```
BEGIN_GAME_CONFIG
    ...
    KBD_DEFAULT_UP=Q
    KBD_DEFAULT_DOWN=A
    ...
END_GAME_CONFIG
```

The `KEY=VALUE` form matches the existing `SOUND <NAME>=<VAL>`
directive convention (see `doc/DATAGEN.md:550-556`); we deliberately
do **not** introduce a separate whitespace-separated dialect. Datagen
emits `#define CFG_KBD_DEFAULT_UP 'Q'`; engine checks
`#ifdef CFG_KBD_DEFAULT_UP` and falls back to the engine default.
Same overlay mechanics as everything else; documented in
`assets.md` §2.5.

### 3.5 The `CONTROLLER_SELECTED` SOUND / event behaviour

The `CONTROLLER_SELECTED` SOUND ID is **declared** in
`Game.gdata` (`SOUND CONTROLLER_SELECTED=<symbol>`) and **played** by
the per-game menu code via either `beeper_play_fx()` (48K), `bit_beepfx()`
(blob-loaded beeper), or eventually `tracker_play_fx()` (AY/Arkos
path).

On CPC the question is "does the event still make sense?". Answer:
**yes, unconditionally**. CPC also has multiple input options
(keyboard, Joy0, Joy1, keyboard-with-redefined-keys), so the menu
still has a non-trivial selection step that benefits from audible
feedback. The CPC equivalent SFX symbol comes from the Arkos
soundfx bank (owned by `audio.md`).

The mechanics:

- `Game.gdata` continues to declare the event:
  `SOUND CONTROLLER_SELECTED=<symbol>`.
- On ZX (`PLATFORM zx48|zx128`): `<symbol>` is a `BEEPFX_*` constant.
- On CPC (`PLATFORM cpc464|cpc6128`): `<symbol>` is an Arkos
  SFX index.
- Either via Tier-3 `<platform>/game_data/game_config/Game.gdata`
  full-shadow (`assets.md` §2.4) or via a per-platform `SOUND_CPC`/
  `SOUND_ZX` directive (`audio.md`'s decision; flagged as Open Q in
  `assets.md` §6 item 8).
- User-code menu calls `beeper_play_fx( SOUND_CONTROLLER_SELECTED )`
  on ZX or `tracker_play_fx( SOUND_CONTROLLER_SELECTED )` on CPC.
  *The function name may differ per platform*; `audio.md` decides
  whether to expose a single `audio_play_fx()` HAL entrypoint or
  keep them separate.

**From the input HAL's perspective** the only contract is: the menu
code (per-game, in the platform overlay) calls
`game_state.controller.type = CTRL_TYPE_<chosen>` and then triggers
the SFX via the *audio* HAL. `input_*` is not involved in playing the
sound. This document only documents the event so it doesn't fall
between the cracks.

---

## 4. CPC input backend choice

The task spec asks explicitly: use cpctelera's keyboard scan, or
write a custom scan?

### 4.1 cpctelera keyboard scan

cpctelera ships
`cpctelera/src/keyboard/` with the following public surface
(verified from the upstream `keyboard.h` and the
`cpct_scanKeyboard.s` / `cpct_isKeyPressed.s` asm sources):

- **Storage**: `cpct_keyboardStatusBuffer[10]` — 10 bytes (80 bits),
  one bit per key, **0 = pressed, 1 = not pressed** (AY-3-8912
  convention).
- **Scan functions** (all populate the buffer; T-state / µs costs at
  4 MHz, taken from each `.s` header in
  `cpctelera/src/keyboard/`):
  - `cpct_scanKeyboard()` — full scan; manages its own DI/EI
    internally. **848 T-states (≈ 212 µs)**.
  - `cpct_scanKeyboard_f()` — fast (unrolled) variant; also manages
    its own DI/EI. **680 T-states (≈ 170 µs)**.
  - `cpct_scanKeyboard_i()` — interrupt-safe variant: **assumes
    interrupts are already disabled** and does not DI/EI itself
    (caller's responsibility). **840 T-states (≈ 210 µs)**.
  - `cpct_scanKeyboard_if()` — combined fast + interrupt-safe; also
    does not DI/EI itself. **672 T-states (≈ 168 µs)**.
- **Query functions** (read the buffer; do **not** rescan):
  - `cpct_isKeyPressed( cpct_keyID key )` — 14 µs / 56 T-states.
    `key` is a 16-bit ID: low byte = matrix line 0-9, high byte =
    bit mask.
  - `cpct_isAnyKeyPressed()` / `_f()` — short-circuit any-key test.
- **Joystick coverage**: CPC built-in joysticks Joy0 and Joy1 are
  **part of the same matrix** (Joy0 = line 9, Joy1 = line 6).
  `Joy0_Up = 0x0109`, `Joy0_Fire1 = 0x1009`, etc. — they are
  ordinary `cpct_keyID` values handled by the same
  `cpct_scanKeyboard` + `cpct_isKeyPressed` pair. **No separate
  joystick read function exists or is needed.**

Practical implications for RAGE1:

- ✅ The full ZX state byte (up/down/left/right/fire) can be built by
  five `cpct_isKeyPressed` calls (one per direction/button), each
  using the appropriate Joy0_*/Joy1_*/`Key_*` ID. Total cost: 5 × 56
  = 280 T-states (~70 µs) per `input_state_read` call. Negligible.
- ✅ The scan cost (848 T-states) is paid once per frame in
  `input_scan()`, called from `check_controller()` at the start of
  each frame iteration. At 50 Hz that is ~42 400 T-states/sec out of
  the 4 000 000 the CPU has — ~1 % CPU.
- ✅ Licence: LGPL-3.0 (verified in `cpc-renderer.md` §1.1). Since we
  are vendoring cpctelera as a submodule under `external/cpctelera`
  anyway, the keyboard module costs zero additional surface — it's
  already in the vendored tree.
- ✅ ASM hot-path coded by Augusto Ruiz and others, well-tested in
  many shipped CPC games.

### 4.2 Custom scan alternative (brief)

Writing a custom RAGE1-owned CPC keyboard scanner is possible. The
hardware-level steps are:

1. Disable interrupts.
2. Set PPI port C (`$F6xx`) to select keyboard line N (lines 0..9).
3. Read PPI port A (`$F4xx`) to get the 8-bit line state.
4. Store inverted into `our_buffer[N]`.
5. Repeat for N = 0..9.
6. Re-enable interrupts.

The whole thing is ~30 lines of assembly. Pros: zero external
dependency for input; no upstream surprises. Cons:

- ❌ Duplicates well-tested cpctelera code we are already vendoring.
- ❌ Adds an asm file the RAGE1 maintainer must keep correct across
  z88dk SDCC version bumps.
- ❌ No upstream community of CPC programmers to spot bugs in our
  scan.
- ❌ We would need to re-derive Joy0/Joy1 matrix coordinates,
  shift-state semantics, etc.
- ⚠️ Marginal cycle savings (cpctelera's scan is already near the
  theoretical minimum at 848 T-states).

### 4.3 Recommendation + justification

**Use cpctelera's `cpct_scanKeyboard_if` + `cpct_isKeyPressed`.**

Justifications, in order of weight:

1. **Already vendored.** Once `cpc-renderer.md` Phase R1 lands
   cpctelera as `external/cpctelera`, its keyboard module costs us
   exactly one extra `Makefile.common` rule (`-Iexternal/cpctelera/
   cpctelera/src/keyboard/`) and a handful of asm/C source files.
2. **Joy0/Joy1 fall out for free.** The fact that CPC joysticks are
   matrix rows 9 and 6 makes "keyboard scan + joystick read" a
   *single* operation. cpctelera already exposes the right scancode
   constants (`Joy0_Up`, `Joy0_Fire1`, …). A custom scanner would
   have to re-derive those.
3. **Symmetry with the rest of the CPC backend.** `gfx_cpc.c` and
   `gfx_cpc.h` will already include from `external/cpctelera/.../
   sprites/`, `video/`, `firmware/`. Adding `keyboard/` keeps the
   "one library, one integration boundary" rule.
4. **Cycle cost is acceptable.** 1 % CPU per frame for `cpct_scanKeyboard`
   plus negligible cost per `input_state_read` call. Even if RAGE1
   eventually goes 60 Hz on CPC, the budget remains tiny.
5. **LGPL-3.0 is already accepted** for cpctelera as a whole.

**Recommended scan variant: `cpct_scanKeyboard_if`** — fast +
interrupt-safe variant: assumes interrupts are already disabled at
call time and does **not** manage them itself (same for `_i`; the
caller owns DI/EI). RAGE1's main game loop runs with interrupts
enabled (for tracker/timer), so the engine wrapper must disable
interrupts for the 168 µs / 672 T-state window of the scan
(168 µs = body of `cpct_scanKeyboard_if` measured at 4 MHz; source:
`cpctelera/src/keyboard/cpct_scanKeyboard_if.s` cycle-count header).
This is a one-line `__asm__ di / ei __endasm` around the call site,
encapsulated inside `input_cpc.h`'s `input_scan()` macro:

```c
#define input_scan() do { __asm di __endasm; \
                          cpct_scanKeyboard_if(); \
                          __asm ei __endasm; } while(0)
```

(Alternative: use `cpct_scanKeyboard_f()` which manages its own DI/EI
internally — 170 µs / 680 T-states — slightly slower than `_if` plus
caller-side DI/EI, but simpler at the call site. Open Q4 below.)

**Banking caveat**: `cpct_scanKeyboard` does direct PPI I/O which
doesn't interact with CPC bank-switching. There is no
banking.md-level concern from input. The scan time (~168 µs for `_if`,
~170 µs for `_f`, ~212 µs for the plain variant) is well under one
scanline cycle, so it cannot cause raster bar / split effects.
Flagged in §5 (Risks) regardless.

---

## 5. Phased work plan

Each phase ends with `make all-test-builds` green (ZX) and
`tests/00regression/` screenshot tests green (ZX). CPC test games
join the matrix only at IN5 / IN6 and onwards. Phases are commit
groups; individual tasks within a phase may briefly break the tree;
phase exits must restore green.

### Phase IN1 — Audit & test scaffolding

Goal: pin behaviour, no production code changes.

- **IN1-1** Pin the screenshot baseline for input-driven test paths.
  - What: ensure `tests/00regression/` covers the input touch-points:
    at minimum the controller-selection menu flow in `games/default`
    (key '1' → keyboard), the game pause logic (press Y while in
    game), and the hero-fire edge detection. If any of these are
    not already covered, add screenshot/regression hooks (see
    `testing.md`). Run baseline against `master`.
  - Test: regression green.
  - Outcome: known-good pre-multiplatform baseline.
- **IN1-2** Inventory the per-game `kbd.c` / `kbd.h` duplicates.
  - What: list every game with a `game_src/kbd.{c,h}` file. Verified
    today: **only `games/default` and `games/default_jsp`** carry
    these files; both are near-identical. No other test game has a
    `kbd.c`. Confirm they remain near-identical and flag any
    divergence.
  - Test: `find games -name "kbd.*"` + `diff
    games/default/game_src/kbd.c games/default_jsp/game_src/kbd.c`.
  - Outcome: known consolidation surface (two files) for Phase IN4.
- **IN1-3** Add a static-grep CI guard: no engine file under
  `engine/banked_code/` includes `<input.h>` directly except the
  three current sites (`hero.c`). The guard catches new uses of the
  z88dk input header creeping in during refactor.
  - Test: ad-hoc CI shell rule.
  - Outcome: refactor safety net.
- **Phase-exit criteria**:
  - Baseline pinned.
  - Duplication inventory complete.
  - CI guard active.

### Phase IN2 — `input.h` skeleton + `INPUT_STATE_*` constants

Goal: introduce the HAL header surface and the cross-platform state-
bit constants, **without removing the z88dk dependency** yet. This is
the analogue of `gfx.md` Phase G1-2 (additive alias).

- **IN2-1** Add `engine/include/rage1/input.h` with:
  - `INPUT_STATE_UP/_DOWN/_LEFT/_RIGHT/_FIRE/_NONE/_DIRS` constants.
  - Conditional include of `rage1/input_zx.h` (the only backend
    that exists at this point).
  - Prototypes for the new HAL functions (still un-implemented).
- **IN2-2** Add `engine/include/rage1/input_zx.h` as a **thin
  wrapper** over `<input.h>`: macros that map `input_*` to
  `in_*`, plus the `INPUT_SCANCODE_*` / `KBD_DEFAULT_*`
  per-backend constants. Both names compile.
- **IN2-3** Switch `engine/include/rage1/hero.h:43-46` from
  `IN_STICK_UP` to `INPUT_STATE_UP`. Aliases ensure the binary is
  identical.
  - Test: `make all-test-builds` byte-identical to IN1 exit.
- **IN2-4** Switch `engine/src/hero.c:170,183,190` from
  `IN_STICK_FIRE` to `INPUT_STATE_FIRE`.
  - Test: regression green.
- **Phase-exit criteria**:
  - `engine/include/rage1/input.h` exists and provides
    `INPUT_STATE_*`.
  - Banked `hero.c` and main `hero.c` use the new constants.
  - ZX binaries byte-identical.

### Phase IN3 — Engine ↔ HAL migration

Goal: route every engine `in_*` call through the HAL surface. Banked
`hero.c`'s `<input.h>` include can disappear.

- **IN3-1** Replace `<input.h>` includes in engine source with
  `"rage1/input.h"`:
  - `engine/src/controller.c:11` → `"rage1/input.h"`.
  - `engine/src/main.c:11` → `"rage1/input.h"`.
  - `engine/include/rage1/controller.h:14` → `"rage1/input.h"`.
  - `engine/banked_code/common/hero.c:13` → `"rage1/input.h"`.
  - Other indirect callers (any file that includes
    `rage1/controller.h` transitively gets `rage1/input.h`).
- **IN3-2** Migrate every direct z88dk input call:
  - `controller.c:34-36` → `input_state_read( type, &…keys )`.
    This involves moving the `switch(type)` from `controller.c`
    *into* `input.c`'s `input_state_read()` body. `controller.c`'s
    `controller_read_state()` becomes a one-liner wrapper or is
    removed entirely (decision: keep as wrapper for now to preserve
    callsite stability; flag for removal in IN6).
  - `controller.c:42` → `input_key_pressed( INPUT_SCANCODE_PAUSE )`.
  - `main.c:83-84` → `input_wait_key()` / `input_wait_nokey()`.
  - `game_loop.c:40,42` → `input_wait_nokey()`.
  - `debug.c:63-64` → `input_wait_key()` / `input_wait_nokey()`.
- **IN3-3** Replace `IN_KEY_SCANCODE_*` references in
  `engine/include/rage1/controller.h:29-33` with the
  ASCII-defaults pattern from §3.4 (`KBD_DEFAULT_UP = 'Q'` etc.).
  Update `init_controllers()` to use `input_lookup_key()`.
  - Test: regression green. (One run-time `input_lookup_key` call per
    direction at boot; verify no ZX visual or behavioural diff.)
- **IN3-4** Add the `input_scan()` macro (no-op on ZX) and add an
  `input_scan()` call at the start of `check_controller()`
  (`engine/src/game_loop.c:112`). On ZX it expands to nothing; the
  call site is in place for CPC.
  - Test: regression green.
- **IN3-5** Add a CI grep-guard step that scans the four engine
  source roots — `engine/src/`, `engine/banked_code/`,
  `engine/lowmem/`, `engine/include/` — for any of the legacy
  z88dk-input symbols (`<input.h>` include, `in_inkey`, `in_pause`,
  `in_wait_*`, `in_test_key`, `in_key_pressed`, `in_stick_*`,
  `in_key_scancode`, `IN_STICK_*`, `IN_KEY_SCANCODE_*`, `udk_s`).
  The guard **explicitly excludes** the two HAL implementation
  files where these symbols are still expected to appear:
  `engine/include/rage1/input_zx.h` and `engine/src/input.c`. Scoping
  the search to the four engine roots (and excluding the two HAL
  files) is important — without that, the guard's own regex string,
  any per-game `game_src/` file, or even this `input.md` line would
  match and produce false positives. The guard is a shell step in
  CI (not specified inline here); zero matches outside the excluded
  files is the pass condition.
  - Outcome: engine is fully HAL-clean.
- **Phase-exit criteria**:
  - No direct z88dk `<input.h>` includes or calls remain anywhere
    in `engine/` (verified by IN3-5 grep guard, added to CI).
  - `make all-test-builds` green; ZX screenshot regression green.

### Phase IN4 — Per-game `kbd.c` consolidation

Goal: remove the two per-game `kbd.c`/`kbd.h` files (in `games/default`
and `games/default_jsp`). Replace them with the HAL's
`input_capture_scancode()`.

- **IN4-1** Implement `input_capture_scancode()` in `input.c`
  (ZX branch). It is the body of the inline-asm helper at
  `games/default/game_src/kbd.c:6-46`, lifted into HAL territory.
- **IN4-2** Update the canonical reference game (`games/default`) to
  call `input_capture_scancode()` from its menu code, replacing the
  `capture_key_scancode()` call. Delete `games/default/game_src/kbd.{c,h}`.
  - Test: `make build-default`, manual + regression test of
    "Redefine" menu path.
- **IN4-3** Sweep the only other game that ships its own `kbd.{c,h}`
  — `games/default_jsp` — to call `input_capture_scancode()` instead.
  Delete `games/default_jsp/game_src/kbd.{c,h}`. After IN4-2 deletes
  the `default` copy, this removes all `kbd.c` files from the tree.
  (The other games — `blobs`, `crumbs`, `damage_mode`, `get_weapon`,
  `monochrome`, `vortex2` — do not have a `kbd.c` and have no
  Redefine path, so nothing to migrate there.)
  - Test: `make all-test-builds`.
- **IN4-4** Update `tools/datagen.pl` documentation in
  `doc/DATAGEN.md` to point at the HAL's `input_capture_scancode()`
  for custom redefine flows. Mention the change in the game-template
  generation (`make new-game`).
- **Phase-exit criteria**:
  - Zero `game_src/kbd.c` files remain in any test game.
  - All games still build and pass regression.

### Phase IN5 — CPC backend skeleton (stub)

Goal: provide a non-real CPC input backend so engine source compiles
clean when `PLATFORM` selects a CPC target. Analogue of `gfx.md`
Phase G7.

- **IN5-1** Add `engine/include/rage1/input_cpc.h` with the full
  contract (typedefs, constants, macros). Macros may expand to
  empty `do{}while(0)` or to a `cpct_*` symbol that resolves to a
  no-op extern (declared but not yet linked).
- **IN5-2** Add `engine/src/input.c` real bodies under
  `#ifdef BUILD_FEATURE_INPUT_BACKEND_CPC` for
  `input_state_read`, `input_capture_scancode`, `input_pause`,
  `input_wait_key`, `input_wait_nokey`, `input_inkey`,
  `input_lookup_key` — all initially stubs (return zero, no
  busy-wait).
- **IN5-3** Add `cpc` to the platform matrix in `tools/datagen.pl`:
  - Emit `BUILD_FEATURE_INPUT_BACKEND_CPC` when `PLATFORM ∈
    {cpc464, cpc6128}`.
  - Emit `BUILD_FEATURE_INPUT_BACKEND_ZX` otherwise.
- **IN5-4** Compile-test against the stub via `games/00cpc-compile-
  test/` (the synthetic test target introduced in `gfx.md` G7-4) —
  ensure every `engine/src/*.c` file compiles clean against the
  stub input backend.
  - Test: `zcc` C-level type-check passes; linkage may fail (no real
    cpctelera linked yet).
- **Phase-exit criteria**:
  - All ZX test games still build green.
  - `games/00cpc-compile-test/` compiles its `engine/src/*.c`
    against the CPC stub input backend with no errors.

### Phase IN6 — Real CPC backend wiring

Goal: actual keyboard / joystick reads on CPC, gated by
`cpc-renderer.md` Phase R1 having landed (cpctelera vendored under
`external/cpctelera`).

- **IN6-1** Implement `input_cpc.h` macros pointing to real
  cpctelera symbols (`cpct_scanKeyboard_if`, `cpct_isKeyPressed`,
  `cpct_isAnyKeyPressed_f`).
- **IN6-2** Implement `input.c`'s CPC branches:
  - `input_state_read( CTRL_TYPE_KEYBOARD, udk )` — 5
    `cpct_isKeyPressed` calls, OR the bits.
  - `input_state_read( CTRL_TYPE_JOY0, _ )` — 5 calls with
    `Joy0_Up`/`Joy0_Down`/etc.
  - `input_state_read( CTRL_TYPE_JOY1, _ )` — same with `Joy1_*`.
  - `input_capture_scancode()` — `cpct_scanKeyboard()` + walk
    `cpct_keyboardStatusBuffer[]` until a `0` bit is found, return
    `(matrix_line | (bit_mask << 8))`.
  - `input_inkey()` — table lookup from `cpct_keyID` to ASCII for
    common keys; 0 otherwise.
  - `input_pause( ms )` — busy-wait with `cpct_scanKeyboard_f` +
    `cpct_isAnyKeyPressed_f` polling; calibrated for 4 MHz.
  - `input_wait_key()` / `input_wait_nokey()` — loop on
    `cpct_isAnyKeyPressed_f`.
  - `input_lookup_key( ascii )` — ASCII → `cpct_keyID` table.
- **IN6-3** Define the CPC controller-type constants in
  `input_cpc.h`:
  ```c
  #define CTRL_TYPE_JOY0  4
  #define CTRL_TYPE_JOY1  5
  ```
  (`CTRL_TYPE_KEYBOARD` and `_UNDEFINED` are in `input.h` per §3.3.)
- **IN6-4** Implement the per-game CPC menu overlay for
  `games/minimal` (`games/minimal/cpc6128/game_src/menu.c`).
  Trivial: set `game_state.controller.type = CTRL_TYPE_KEYBOARD`,
  exit. Shadows the shared ZX-only one.
- **IN6-5** Implement the per-game CPC menu overlay for
  `games/default` (`games/default/cpc6128/game_src/game_functions.c`).
  Mirrors the ZX "1: KEYBOARD / 2: JOY0 / 3: JOY1 / 4: REDEFINE"
  flow. Plays the CPC `SOUND_CONTROLLER_SELECTED` SFX after each
  selection via the audio HAL (per `audio.md`).
- **IN6-6** Add CPC screenshot regression for `games/minimal` and
  `games/default` controller-selection paths (per `testing.md`).
- **IN6-7** Decide and implement Open Q3 (CPC pause key). Recommend
  `Key_H` ("H" — the "halt" mnemonic, away from cursor keys to avoid
  accidental triggers). Set `INPUT_SCANCODE_PAUSE = Key_H` in
  `input_cpc.h`.
- **Phase-exit criteria**:
  - `games/minimal` and `games/default` build and run on CPC
    emulator (Caprice32 or RVM) with working keyboard and joystick
    input.
  - Pause-key works on both ZX (`Y`) and CPC (`H`).
  - ZX regression still green.
  - CPC regression green for the two ported games.

### Phase IN7 — Optional `.gdata CONTROLLER` directive + cleanup

Goal: enable per-game default-key override via `.gdata` (§3.4
option B); polish the public surface.

- **IN7-1** Add `CONTROLLER` directive parsing in `tools/datagen.pl`
  (in the `GAME_CONFIG` state branch). Accept ASCII keys, e.g.:
  ```
  CONTROLLER  KBD_UP=Q KBD_DOWN=A KBD_LEFT=O KBD_RIGHT=P KBD_FIRE=SPACE
  ```
  Emit `#define CFG_KBD_DEFAULT_UP 'Q'` etc. in
  `build/generated/features.h` (or `game_data.h`).
- **IN7-2** Update `init_controllers()` in
  `engine/src/controller.c` to prefer `CFG_KBD_DEFAULT_*` over
  `KBD_DEFAULT_*` when present.
- **IN7-3** Pause key configurability: add an optional
  `PAUSE_KEY=<ascii>` to the `CONTROLLER` directive. Engine reads
  `CFG_PAUSE_KEY` or falls back to platform default.
- **IN7-4** Document the `CONTROLLER` directive in `doc/DATAGEN.md`
  next to the existing `SOUND` block (`doc/DATAGEN.md:616-625`).
- **IN7-5** Remove `controller_read_state()` and
  `controller_pause_key_pressed()` from `controller.c` — they
  become one-line wrappers that no longer pull weight.
  Engine call sites call `input_state_read` / `input_key_pressed`
  directly. (Decision deferred to this phase to keep IN3 minimal.)
- **Phase-exit criteria**:
  - `.gdata CONTROLLER` directive works on at least one ZX game and
    one CPC game.
  - ZX + CPC regression green.

### Phase IN8 — Hardening, MSX/C64 anticipation, docs

Goal: close the loop, capture forward-looking decisions.

- **IN8-1** Sketch what an MSX backend would look like
  (`input_msx.h`): MSX reads its keyboard via the AY-3-8910 I/O port
  in a 11-row matrix; joysticks via PSG port + bit-packed register.
  Confirm the HAL shape generalises. **No implementation** — sketch
  only in this doc and `doc/multiplatform-plan/README.md`.
- **IN8-2** Sketch C64 (cbm/Commodore) input shape — the `CIA` chip
  / matrix scan. Same shape conclusion; flag the 6502 toolchain axis
  as the actual blocker.
- **IN8-3** Add a `tests/00regression/input_hal_smoke` test target
  that exercises all the HAL primitives (scan, state read, lookup,
  capture, wait, pause) on each supported PLATFORM.
- **IN8-4** Update top-level `doc/multiplatform-plan/README.md` to
  reflect input HAL status.
- **Phase-exit criteria**:
  - MSX/C64 sketch documented.
  - Smoke regression added.
  - Docs current.

---

## 6. Risks

- **R1 — Banking-time-sensitive ISR interaction with `cpct_scanKeyboard`.**
  Interrupts are disabled during the scan: ~168 µs for the
  recommended `_if` variant (caller manages DI/EI), ~170 µs for
  `_f` (manages its own DI/EI), ~212 µs for the plain `cpct_scanKeyboard`.
  If the Arkos/tracker ISR is running with very tight scanline timing
  (raster bar effects, for example), that DI window could shift a
  raster split. RAGE1 does not currently do raster effects, but this
  is a known footgun for future audio.md / banking.md interactions.
  *Mitigation*: `input_scan()` is called once per frame at a
  well-defined point in the main game loop (start of
  `check_controller()`), before any audio-critical work. Document
  the timing constraint in `banking.md`'s ISR section.

- **R2 — z88dk SDCC version skew between cpctelera and RAGE1.**
  cpctelera ships its own SDCC 3.6.8 internally; RAGE1 uses
  z88dk-bundled SDCC 4.x. The `__z88dk_fastcall` / `__z88dk_callee`
  annotations in cpctelera keyboard.h are nominally compatible with
  z88dk's SDCC, but cycle counts and register usage may differ at
  the asm-call-site level.
  *Mitigation*: validate every cpctelera keyboard function with a
  small standalone test program early in IN6. Pin to a known-good
  cpctelera commit; document the pin in `cpc-renderer.md`.

- **R3 — `udk_t` struct shape divergence breaks save/restore.**
  If any game persists `game_state.controller.keys` to a save slot
  or to non-volatile storage, the shape change from z88dk's `udk_s`
  to a backend-specific `input_udk_t` is a backwards-compat break.
  *Mitigation*: today, no test game saves controller state. Note in
  release notes for any external game maintainers. Mitigation
  applies even on ZX (struct field count is the same, field types
  are the same — only the typedef name changes — so the change is
  almost certainly binary-compatible on ZX).

- **R4 — `IN_KEY_SCANCODE_*` removal breaks external games.**
  External games may use `IN_KEY_SCANCODE_y` etc. directly in user
  code. Removing the include of `<input.h>` from engine headers
  doesn't prevent user code from including it, but the
  `KBD_*` macros that were re-exported (`KBD_UP`, `KBD_DOWN`, etc.)
  change semantic from "ZX scancode" to "ASCII default".
  *Mitigation*: keep `KBD_*` as **runtime-resolved scancodes**
  populated by `input_lookup_key(KBD_DEFAULT_*)` — they remain
  available as variables `game_state.controller.keys.up` etc. The
  `KBD_*` compile-time macros are removed cleanly with a clear
  error message pointing at `input_lookup_key`. Document in
  `ROADMAP.md` and release notes. Add a deprecation grace period
  during IN3.

- **R5 — CPC keyboard ghost-keys / matrix collisions.**
  Pressing certain key combinations on real CPC hardware causes
  matrix ghosting (a key on row R appears pressed when it isn't,
  because another column on row R is held). cpctelera's scan
  reports the matrix as-is, so the engine sees ghosts. ZX has the
  same hardware limitation but its keyboard layout reduces clash
  for common game keys.
  *Mitigation*: pick CPC default keys (and CPC redefine guidance)
  from a known-good "no-ghost" subset, e.g. cursor cluster +
  Space. Document the constraint in `doc/MULTIPLATFORM-INPUT.md`
  (Phase IN8 deliverable).

- **R6 — Banking-time keyboard ISR mid-bank-switch.**
  CPC6128 bank-switching via the 8255 PPI shares the I/O space with
  keyboard scanning (different ports, but the same chip). If the
  scan happens during a bank switch, the result is undefined.
  *Mitigation*: `input_scan()` is called at a deterministic, well-
  isolated point in the frame — never inside a banked-code section.
  Document in `banking.md`; add a CI grep to ensure `input_scan()`
  is not called from `engine/banked_code/`.

- **R7 — Per-game CPC menu code drift.**
  Eight test games carry a non-trivial controller-selection menu in
  `game_src/game_functions.c` (`default`, `default_jsp`, `blobs`,
  `crumbs`, `damage_mode`, `get_weapon`, `monochrome`, `vortex2`;
  verified via `grep -l 'CTRL_TYPE_KEMPSTON' games/*/game_src/*.c`).
  Once we sibling-tree-shadow each menu under `<platform>/game_src/`
  for CPC, every such game grows a *second* menu implementation, and
  as the ZX menu evolves, the CPC overlay drifts. Counted naively,
  after Phase IN6 the duplicate menu surface is 8 games × 2 platforms
  = **16** separate `game_functions.c` files. Note this is a
  *menu-text-and-dispatch* duplication; it is **distinct from** the
  `kbd.c`/`kbd.h` asm-helper duplication, which is much smaller
  (only `default` and `default_jsp` ship a `kbd.c` — 2 files, fixed
  by Phase IN4).
  *Mitigation*: extract a shared `engine/src/input_menu.c` template
  that the per-game menus invoke (only differing in the strings
  printed and the controller types offered). Out of scope for IN6 —
  flagged for a future "engine menu HAL" follow-up. Track as Open
  Question Q5.

- **R8 — Joy0/Joy1 vs Kempston/Sinclair vocabulary clash.**
  `CTRL_TYPE_KEMPSTON = 2` on ZX vs `CTRL_TYPE_JOY0 = 4` on CPC.
  If user code does `if (type == CTRL_TYPE_KEMPSTON) { … }` and
  is then compiled for CPC, the `CTRL_TYPE_KEMPSTON` token is
  undefined → compile error. Per §3.3 we accept this *because*
  the compile error is the goal: user code should not silently
  mean two different things on two platforms.
  *Mitigation*: per-platform overlay of `game_functions.c` (already
  the assets.md mechanism). Document the convention; add a sample
  ifdef-conditional menu in the game template (`make new-game`).

- **R9 — Pause key collision with redefined keys.**
  On ZX the pause is `Y`; if the player redefines fire to `Y` they
  lose pause (and inadvertently pause every time they fire). On
  CPC if pause defaults to `H` and the player redefines a movement
  key to `H`, same issue.
  *Mitigation*: `input_capture_scancode()` could refuse to return
  the pause scancode. Simpler: leave it as a known wart, document
  in `doc/DATAGEN.md`. Pre-existing on ZX; no regression.

---

## 7. Open Questions

- **Q1 — `CTRL_TYPE_*` enum partition: shared vs backend-private?**
  Option B in §3.3 was recommended (backend-private `CTRL_TYPE_KEMPSTON`,
  `CTRL_TYPE_SINCLAIR1`, `CTRL_TYPE_JOY0`, `CTRL_TYPE_JOY1`).
  Confirm or pick Option A (all values cross-platform-defined,
  unsupported types return `INPUT_STATE_NONE` at runtime). Decide
  before IN5.

- **Q2 — Should `input_inkey()` exist as a HAL function at all?**
  Today `in_inkey()` is used only by per-game menu code, not by the
  engine. It is awkward on CPC because cpctelera doesn't expose an
  equivalent — we have to maintain an ASCII translation table. The
  engine itself never calls `in_inkey()`. **Sub-option Q2A**: drop
  `input_inkey` from the HAL entirely; per-game menu code uses
  `input_capture_scancode` + game-local translation. **Sub-option
  Q2B**: keep `input_inkey()` because half a dozen per-game menus
  already use it and the migration cost is real. Recommend Q2B
  with a small (20-30 entry) ASCII table on CPC. Confirm before IN6.

- **Q3 — CPC pause-key default.**
  Recommended `Key_H` (mnemonic: halt). Alternatives: `Key_P`
  (mnemonic: pause; but conflicts with the default right-movement
  key in ZX layout `O/P`, which a CPC port might keep), or `Key_ESC`
  (intuitive, but used by many CPC games as exit-to-menu). Confirm
  before IN6-7. Make it configurable per-game via
  `.gdata CONTROLLER PAUSE_KEY=h` (IN7-3).

- **Q4 — `cpct_scanKeyboard_if` vs `cpct_scanKeyboard_f`?**
  `_if` is faster but expects interrupts already disabled and does
  **not** manage them internally — our wrapper has to do DI/EI
  explicitly. `_f` handles its own DI/EI inside. The cpctelera-
  function-body delta is small: `_if` is 672 T-states (168 µs), `_f`
  is 680 T-states (170 µs) — i.e. about 8 T-states / 2 µs per scan
  (verified from each variant's `.s` cycle header). Once the `_if`
  caller's own `di`/`ei` (4 T-states each) are accounted for, the two
  shapes are effectively interchangeable on cost; the real choice is
  about where DI/EI semantics live. Recommend `_if` with explicit
  DI/EI in the macro (§4.3) — cleaner separation of concerns.
  Confirm before IN6-1.

- **Q5 — Should there be an engine-level menu HAL?**
  Risk R7 flags the per-game-menu drift problem. A future
  `engine/src/menu.c` could provide a templated controller-selection
  menu (driver/strings supplied by the game). Out of scope for the
  multiplatform plan; flagged here so it can be opened as a separate
  task. The HAL shape would be: `void engine_menu_select_controller(
  const char *title, const char **option_names, const uint8_t
  *option_types, uint8_t num_options )`.

- **Q6 — Mouse / lightgun / extended-input support.**
  z88dk's `input.h` has a full mouse API (Kempston mouse, AMX mouse,
  AY mouse, simulated mouse via joystick). cpctelera does *not*
  ship mouse support natively (AMX mouse drivers exist as third-
  party CPC code). RAGE1 today uses none of it. Recommendation:
  out of scope for Phase 1. Document the HAL as joystick + keyboard
  only; explicitly defer mouse to a future phase.

- **Q7 — CPC second fire / extended joystick buttons.**
  cpctelera exposes `Joy0_Fire1`, `Joy0_Fire2`, `Joy0_Fire3`.
  `INPUT_STATE_FIRE_2`, `INPUT_STATE_FIRE_3` already exist in the
  bit packing. Should the engine read them and route to a second
  weapon / action? Recommendation: out of scope; only `_FIRE` is
  used today. Reserve the bits.

- **Q8 — `IN_KEY_SCANCODE_DISABLE` / `_ANYKEY` semantics on CPC.**
  z88dk's input_zx.h defines two magic scancode values: `0xffff`
  ("disabled key") and `0x1f00` ("any key"). The engine doesn't
  use them, but per-game user code might. Recommendation: not
  reproduced on CPC; if user code references them under CPC build,
  compile error → user explicitly handles it. Document.

- **Q9 — Persistent key redefinition.**
  Currently the player redefines keys per-game-session; nothing
  persists. If RAGE1 ever gains save-game support, controller
  config would naturally save. The HAL types (`input_udk_t`) differ
  per platform → save files are per-platform anyway. Note for
  future planning. No decision needed now.

- **Q10 — `MOVE_*` macro retention.**
  `MOVE_UP/_DOWN/_LEFT/_RIGHT/_ALL/_NONE` aliases in `hero.h`. They
  are used pervasively in banked `hero.c`. Recommendation: keep the
  alias even after introducing `INPUT_STATE_*`. `MOVE_*` reads more
  naturally in hero-movement code. The aliases just `#define
  MOVE_UP INPUT_STATE_UP` — zero cost.

---

*End of input.md.*

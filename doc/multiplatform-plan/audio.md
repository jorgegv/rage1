# Audio HAL: `audio_*` design + per-platform backends

This document is the Audio chapter of the RAGE1 cross-platform plan
(parent: `doc/multiplatform-plan/README.md`). It audits today's
audio code — beeper, Vortex Tracker, Arkos Tracker, ISR ticking, the
`SOUND` / `TRACKER*` `.gdata` directives — and proposes an
`audio_*` HAL that mirrors the `gfx_*` shape introduced in `gfx.md`.
The HAL has three concrete backends in Phase 1: **ZX beeper** (48K
only, via z88dk's BIT/BEEPFX), **ZX AY** (128K, via the existing
Arkos2 / Vortex2 paths), and **CPC AY** (464/664/6128, via the
multi-target Arkos2 AKG player).

Conventions used in this file:

- Code references use `file:line` (clickable in most editors).
- Phase tags `AU1, AU2, …`; tasks `AU1-1, AU1-2, …`.
- "ZX game" = any of the existing `games/*` test games. Their
  audible behaviour must match the pre-multiplatform baseline at
  every phase exit.

This is a living document; phase scoping and task numbering may
change during execution.

*Note: all line numbers in this document reference HEAD as of the
audit; re-grep if executing later — line numbers may drift.*

---

## 1. Current state audit

### 1.1 Audio code in `engine/` (file map)

The audio subsystem today is small and well-isolated. Files
involved:

| File | Purpose | Notes |
|---|---|---|
| `engine/src/sound.c` | Empty placeholder | Single comment `// everything moved to banked_code`. Will be repurposed as the HAL dispatch unit (§3). |
| `engine/include/rage1/beeper.h` | Beeper API surface | Pulls in `<sound/bit.h>` from z88dk for the `BEEPFX_*` constants. Declares `init_beeper`, `beeper_request_fx`, `beeper_play_pending_fx`, `beeper_play_fx`. |
| `engine/banked_code/common/beeper.c` | Beeper implementation | 40 lines. `bit_beepfx()` is the only platform call. `init_beeper` only present in 128K builds (48K BSS init zeros the bit state automatically). |
| `engine/include/rage1/tracker.h` | Tracker API surface (platform-agnostic) | Declares both **public** `tracker_*` operations (called from engine + game code) and **per-tracker hook contract** `tracker_specific_*`. Already shaped like a small HAL. |
| `engine/banked_code/128/tracker.c` | Tracker dispatcher | 116 lines. Pure dispatch over `tracker_specific_*` hooks plus mute / current-song bookkeeping. 100% portable shape; only `init_tracker` is build-gated to `BUILD_FEATURE_TRACKER`. |
| `engine/banked_code/128/tracker_arkos2.c` | Arkos2 backend | Implements `tracker_specific_*` over `ply_akg_*` ASM symbols. Includes the Arkos2 player ASM via `arkos2_wrapper(void) __naked`. |
| `engine/banked_code/128/tracker_vortex2.c` | Vortex2 backend | Implements `tracker_specific_*` over `ay_vt2_*`. Sound FX not supported (`#error` if `BUILD_FEATURE_TRACKER_SOUNDFX` is on). |
| `engine/banked_code/128/arkos2-player_asm.inc` | Arkos2 AKG player code, asm | AT2 `PlayerAkg.asm` hand-ported from RASM to z88dk z80asm syntax; ZX-Spectrum hardware variant. See R1. |
| `engine/banked_code/128/arkos2-stubs_asm.inc` | Z88DK C-call stubs for Arkos2 | Bridge between RAGE1's C and the player's asm labels. |
| `engine/banked_code/128/vortex2-player_asm.inc` | Vortex2 PT3 player code, asm | ZX AY PT3 player hand-ported from RASM to z88dk z80asm syntax (originating from z88dk's `psg/vt2` library), included this way because the lib is not in NEWLIB. |
| `engine/include/rage1/arkos2.h` | Arkos2 C prototypes | `ply_akg_init`, `ply_akg_play`, `ply_akg_stop`, `ply_akg_initsoundeffects`, `ply_akg_playsoundeffect`. The same prototypes a CPC Arkos2 build would expose. |
| `engine/include/rage1/vortex2.h` | Vortex2 C prototypes | `ay_vt2_init/play/start/stop/mute`. Mirrors z88dk's `include/psg/vt2.h`. |
| `engine/src/interrupts.c:52-56` | ISR tick hook | Calls `tracker_do_periodic_tasks()` from the IM2 ISR when `BUILD_FEATURE_TRACKER` is defined. Beeper is **not** ticked from the ISR — `bit_beepfx` is synchronous and blocking. |
| `engine/src/flow.c:313-317,450-476,755-771` | Flow-rule actions | `do_rule_action_play_sound` (beeper), `do_rule_action_tracker_*` (4 tracker actions). |
| `engine/src/game_loop.c:73-84,185-191,280-283` | Per-frame chokepoints | Plays pending beeper FX, pending tracker FX; starts / stops music at game-loop entry / exit. |
| `engine/src/main.c:59,70,73` | Init sequence | `init_beeper()`, `init_tracker()`, `init_tracker_sound_effects()` — gated by `BUILD_FEATURE_*`. |
| `etc/rage1-config.yml:59-114` | Banked-function table | Declares the 12 banked audio functions and their callee/fastcall signatures. Drives `tools/banktool.pl` / `tools/generate_banked_function_defs.pl`. |
| `lib/RAGE/Arkos2.pm` | Build-side Arkos2 helpers | `arkos2_convert_song_to_asm()`, `arkos2_convert_effects_to_asm()`, `arkos2_count_sound_effects()`. Shells out to AT2's `tools/SongToAkg` and `tools/SongToSoundEffects`. AT2 path comes from `etc/rage1-config.yml:14-15`. |

**No audio code lives in `engine/lowmem/`.** Every audio function is
either banked (128K) or compiled into the main binary against the
ZX48 build with no banking concerns. This matters for the HAL split
(§3.2): the HAL surface only needs `#include`-visibility in the
TUs that *call* audio (main, game_loop, flow, interrupts), not in
banked code, plus the backend bodies themselves.

### 1.2 `.gdata` directives — `SOUND`, `TRACKER`, `TRACKER_SONG`, `TRACKER_FXTABLE`

Today's audio-shaped DSL surface in `.gdata`:

#### `SOUND <event>=<symbol>`

Parsed at `tools/datagen.pl:851-862`. Pure key/value pair: the LHS
is an event name (`ENEMY_KILLED`, `BULLET_SHOT`, `HERO_DIED`,
`ITEM_GRABBED`, `CONTROLLER_SELECTED`, `GAME_WON`, `GAME_OVER`,
`HERO_HIT`), the RHS is a symbol the engine plays back. In every
checked-in game the RHS is a `BEEPFX_*` constant from z88dk's
`sound/bit.h`. Datagen emits one C-level macro per pair:
`tools/datagen.pl:3311-3314` generates
`#define SOUND_<EVENT> <SYMBOL>` (e.g.
`#define SOUND_ENEMY_KILLED BEEPFX_HIT_3`) into `game_data.h`.

That macro is used in two places:

- **Flow-rule actions**: `DO PLAY_SOUND SOUND_<EVENT>` in a `.gdata`
  flow file (e.g. `games/default/game_data/flow/Events.gdata:4`).
  Datagen turns it into an action record with
  `.data.play_sound.sound_id = SOUND_<EVENT>`
  (`tools/datagen.pl:2475`), executed at
  `engine/src/flow.c:314-316` as `beeper_request_fx(...)`.
- **Direct C calls** from `game_src/*.c`: e.g.
  `games/default/game_src/game_functions.c:109` —
  `beeper_play_fx( SOUND_CONTROLLER_SELECTED )`.

So today the `SOUND` directive is **implicitly ZX-coupled**: the
RHS resolves to a `BEEPFX_*` constant which is a `bfx_*` symbol —
data structures specific to z88dk's BIT/BEEPFX library — and both
engine sites that consume it call `bit_beepfx()` underneath.

#### `TRACKER TYPE=<type> [IN_GAME_SONG=<name>] [FX_CHANNEL=<n>] [FX_VOLUME=<n>]`

Parsed at `tools/datagen.pl:989-1027`. `TYPE` is one of
`arkos2` or `vortex2` (the only valid trackers — see
`tools/datagen.pl:112`, `@valid_trackers`). Side effects:

- Emits `BUILD_FEATURE_TRACKER` and `BUILD_FEATURE_TRACKER_<TYPE>`
  (e.g. `BUILD_FEATURE_TRACKER_ARKOS2`).
- If `FX_CHANNEL` is specified (legal values 0/1/2 — Arkos2 AY
  channels), emits `BUILD_FEATURE_TRACKER_SOUNDFX` and
  `#define TRACKER_SOUNDFX_CHANNEL <n>`.
- If `FX_VOLUME` is specified (0-16), emits
  `#define TRACKER_SOUNDFX_VOLUME <n>`. Note Arkos2's player takes
  **inverted** volume (0 = max), so the consumer
  (`engine/banked_code/128/tracker_arkos2.c:69`) does
  `16 - TRACKER_SOUNDFX_VOLUME` at call time.
- If `TYPE=vortex2` and any FX-related option is present, parsing
  `die`s — Vortex2 has no SFX support.

#### `TRACKER_SONG NAME=<name> FILE=<path>`

Parsed at `tools/datagen.pl:1029-1047`. Builds a list of songs.
Generation logic at `tools/datagen.pl:3848-3884` converts each
song file to a banked `.asm` and emits a `tracker_song_<NAME>[]`
byte array. Also emits `#define TRACKER_SONG_<NAME> <index>`.

- For **Arkos2** songs (`type=arkos2`): if file ends in `.aks`,
  invokes `SongToAkg -sppostlbl :` from AT2 (path in
  `etc/rage1-config.yml:14-15`) to convert to z88dk-flavoured asm
  (`lib/RAGE/Arkos2.pm:22-61`). `.asm` is passed through.
- For **Vortex2** songs: copies the binary `.pt3` into the banked
  build dir and writes a one-line ASM shim that includes it as a
  raw `BINARY` blob.

#### `TRACKER_FXTABLE FILE=<path>`

Parsed at `tools/datagen.pl:1049-1062`. Single per-game effects
table. Generated at `tools/datagen.pl:3901-3919`. Same `.aks`→asm
path as songs, via `SongToSoundEffects`. Also computes the
effect count by counting `dw SoundEffects_SoundNN` lines in the
generated asm (`lib/RAGE/Arkos2.pm:109-123`) and emits
`#define TRACKER_SOUNDFX_NUM_EFFECTS <n>`.

#### Side-by-side game audit

| Game | Beeper SOUND | Tracker TYPE | Songs (.aks/.pt3) | SFX table | Notes |
|---|---|---|---|---|---|
| `games/default` | 7 BEEPFX_* | arkos2 | music1/2.asm | soundfx.asm | All `.asm` (pre-converted), no AKS. |
| `games/default_jsp` | 7 BEEPFX_* | arkos2 | music1/2.asm | soundfx.asm | Same. |
| `games/monochrome` | 7 BEEPFX_* | arkos2 | music1/2.asm | soundfx.asm | Same. |
| `games/get_weapon` | 7 BEEPFX_* | arkos2 | music1/2.asm | soundfx.asm | Same. |
| `games/vortex2` | 7 BEEPFX_* | vortex2 | music1/2.pt3 | none | The only Vortex2 game; commented-out SFX line. |
| `games/blobs` | 7 BEEPFX_* | — | — | — | No tracker. |
| `games/minimal` | 7 BEEPFX_* | — | — | — | No tracker. |
| `games/crumbs`, `damage_mode`, `mapgen`, `sub_bufs_48`, `sub_bufs_128`, `minimal_jsp` | 7-8 BEEPFX_* | — | — | — | No tracker. |

Observation: **every game uses beeper FX**, half the games use
Arkos2 music, **one** game uses Vortex2. The Arkos2 path is the
dominant tracker code path and is what the CPC port hooks into.

### 1.3 ZX beeper (BEEPFX) path

Call graph for a single beeper FX:

```
.gdata flow rule DO PLAY_SOUND SOUND_<EVENT>
   |
   v
generated action: do_rule_action_play_sound() @flow.c:313-317
   |
   v
beeper_request_fx( SOUND_<EVENT> )  @beeper.c:29-32 (banked)
   |
   |   stores ptr in game_state.beeper_fx
   |   sets F_LOOP_PLAY_BEEPER_FX
   v
(deferred — end of frame)
game_loop.c:73-76  -- if flag set:
   beeper_play_pending_fx()  @beeper.c:34-36 (banked)
       -> bit_beepfx( game_state.beeper_fx )
```

Direct path (game-side custom code, bypasses the deferred flag):

```
beeper_play_fx( SOUND_<EVENT> )  @beeper.c:38-40 (banked)
   -> bit_beepfx( sfx )
```

Both paths terminate in `bit_beepfx()` — z88dk's BIT player. The
function is **synchronous and blocking**: it busy-loops driving
the ZX 48K beeper port (`#FE`) for the duration of the effect.
Several SFX last tens of milliseconds, which is why the engine
defers playback to the end of the game loop (after rendering is
done, before the next frame budget).

ZX-shaped assumptions:

1. **Port `#FE` write to bit 4 of port output** is the only
   sound-producing instruction on ZX 48K beeper. Hard-coded in
   the z88dk BIT player; *not* in RAGE1's source. The HAL just
   passes a `void *` SFX pointer and the player does the rest.
2. **`BEEPFX_*` sound IDs** (e.g. `BEEPFX_HIT_3 = bfx_17`) are
   addresses of pre-compiled SFX byte streams shipped in
   z88dk's `sound_bit` library. Each `bfx_<n>` is a label in
   asm. On a non-ZX target these labels do not exist.
3. **Blocking call model**. `bit_beepfx` consumes ~10-50 ms
   uninterrupted CPU. Acceptable on ZX because there's no
   parallel music to disturb (48K = beeper-only); cannot
   coexist with AY music on 128K, which is why the engine
   *prefers* AY+Arkos for 128K and the beeper survives there
   only as a deferred FX path. CPC ports must not assume this
   model — CPC's AY is continuous and beeper-like timing is not
   the audio model.
4. **`game_state.beeper_fx` is a raw `void *`** of unknown
   provenance. Today this is fine because the only providers
   are `BEEPFX_*` symbols. After HAL'ification this becomes an
   opaque "FX cookie" whose meaning is backend-defined.

The `init_beeper()` 128K-only quirk
(`engine/banked_code/common/beeper.c:20-27`) zeros
`_sound_bit_state` — a residual state variable in the BIT player
library. On 48K, BSS zero-init handles this; on 128K, banked
code does not run BSS init for itself, so the engine zeros it
explicitly. **CPC has no equivalent state variable**; the CPC
backend's `audio_init()` will do nothing here.

### 1.4 ZX AY / Tracker path

Two AY tracker backends today:

- **Arkos2** (preferred, with SFX). C wrapper in
  `tracker_arkos2.c` over the `ply_akg_*` symbols defined in
  `arkos2-player_asm.inc`. The player is the **AT2 generic AKG
  player**, configured for the Spectrum hardware variant via the
  Spectrum hardware define inside the included asm.
- **Vortex2** (PT3 only, no SFX). C wrapper in
  `tracker_vortex2.c` over the `ay_vt2_*` symbols defined in
  `vortex2-player_asm.inc`. The player is identical to z88dk's
  `psg/vt2` library; it's included as asm because that library
  is not built into NEWLIB (`tracker_vortex2.c:49-57`).

The dispatcher in `tracker.c:42-115` is **already backend-
agnostic** in shape. It carries:

- a mute flag (`uint8_t muted`),
- a current-song index (`uint8_t current_song = 255`),
- a small state-machine: select-song mutes, then calls
  `tracker_specific_select_song()`, then restores the mute
  state.

Every operation that does platform work is delegated to a
`tracker_specific_*` hook. **This is already a HAL in all but
name.** The audio HAL design (§3) renames these hooks into the
canonical `audio_*` namespace and rationalises the music vs SFX
split.

Tables driven by the build:

```c
extern void *all_songs[];          // generated by datagen
extern void *all_sound_effects[];  // generated by datagen
extern uint8_t muted;
extern uint8_t current_song;
```

`all_songs[]` and `all_sound_effects[]` are generated in the
banked code by `tools/datagen.pl:3890-3919`. The tracker hooks
look up entries by index, so the indirection is
backend-portable.

ZX-shaped assumptions in this path:

1. **AY chip I/O ports `$FFFD` / `$BFFD`**. ZX AY register
   select / data write ports. **CPC uses entirely different
   ports** (the PSG is accessed through the 8255 PPI at
   `$F4xx` / `$F6xx`). The port addresses are inside the
   tracker player asm, *not* in RAGE1 code.
2. **AT2 AKG player is multi-target**. The same generic AKG
   asm source contains code for `PLY_AKG_HARDWARE_CPC`,
   `PLY_AKG_HARDWARE_MSX`, `PLY_AKG_HARDWARE_SPECTRUM`,
   `PLY_AKG_HARDWARE_PENTAGON`. RAGE1's `arkos2-player_asm.inc`
   is a snapshot of the player **assembled for Spectrum**;
   building the same source for CPC is a matter of flipping the
   hardware define. **This is the key fact enabling shared
   tracker assets across ZX and CPC** (§3.4).
3. **128K-only**. `BUILD_FEATURE_TRACKER` is gated on
   `BUILD_FEATURE_ZX_TARGET_128`
   (`tools/datagen.pl:2700-2702`). The tracker code physically
   lives in `engine/banked_code/128/`. On CPC this constraint
   disappears: CPC464 has 64K but its AY player runs without
   banking. The `engine/banked_code/128/tracker*.c` location is
   a banking arrangement, *not* an audio constraint — see
   `banking.md`.
4. **`DEFAULT_SUBSONG = 0`** (`arkos2.h:38`) is an Arkos2
   convention; portable.
5. **Player call ABI**. `ply_akg_init`, `ply_akg_play`,
   `ply_akg_stop`, `ply_akg_initsoundeffects`,
   `ply_akg_playsoundeffect` — these C-callable thin wrappers
   are produced by `arkos2-stubs_asm.inc`. The CPC build needs
   the same stubs, on top of the same generic player asm.

### 1.5 ISR ticking and timing assumptions

Tracker music is ticked from the IM2 service routine. From
`engine/src/interrupts.c:52-56`:

```c
void do_periodic_isr_tasks( void ) {
#ifdef BUILD_FEATURE_TRACKER
   tracker_do_periodic_tasks();
#endif
}
```

…called from `service_interrupt` (the IM2 ISR) at line 67.
Frequency: **50 Hz on ZX**, deriving from the ZX Spectrum's
50-Hz video refresh ISR (`current_time.frame == 50`,
`interrupts.c:36`).

`tracker_do_periodic_tasks` (`tracker.c:80-84`) returns
immediately if muted; otherwise calls the backend's tick. For
Arkos2 this is `ply_akg_play()`; for Vortex2 it's `ay_vt2_play()`.

Assumptions baked into this:

1. **The hardware delivers 50 ISRs/sec.** ZX runs at 50 Hz (PAL)
   or 60 Hz (NTSC); RAGE1 assumes PAL throughout. **CPC also
   runs at 50 Hz (PAL)** — but its raster ISR mechanism is
   different (the CPC's gate array drives 300 Hz, the firmware
   provides a 50 Hz hook). The CPC tracker player's tempo is
   tuned to 50 Hz the same way the ZX one is — so the tempo
   contract is preserved cross-platform.
2. **Beeper FX is *not* ticked from ISR.** `bit_beepfx` is a
   blocking play, not a continuous tick. So the ISR hook has
   no beeper code path. CPC's AY-only model means there is
   nothing equivalent to beeper-FX on CPC; the ISR hook is
   the only audio path on CPC.
3. **ISR must call into bank 0 / fixed memory for the
   tracker tick**. Today `tracker_do_periodic_tasks` lives in
   banked code (`engine/banked_code/128/tracker.c`) but
   `etc/rage1-config.yml:101-102` includes it in the
   banked-functions table — so the C-side caller actually
   resolves to a banked-call dispatcher (see `banking.md`).
   The ISR can't safely page banks itself; the dispatcher
   handles preserve/restore. **On CPC-flat (no banking) this
   becomes a direct call; on CPC-banked (6128 RAM expansion)
   the dispatcher pattern needs equivalent treatment** —
   owned by `banking.md`, not here.
4. **`periodic_tasks_enabled` gate**
   (`interrupts.c:58-60,70-71`). Until
   `interrupt_enable_periodic_isr_tasks()` is called near the
   end of `init_program()` (`main.c:77`), the ISR does **not**
   tick the tracker, which prevents un-initialised state from
   being played. Portable.

### 1.6 Caller inventory: where the engine triggers sound

Every audio call path eventually goes through one of the four
public APIs: `beeper_request_fx`, `beeper_play_fx`,
`tracker_*`, or `tracker_request_fx`. The inventory:

**Init sites** (called once at startup):
- `engine/src/main.c:59` — `init_beeper()` (gated 128K only)
- `engine/src/main.c:70` — `init_tracker()`
- `engine/src/main.c:73` — `init_tracker_sound_effects()`

**ISR sites** (50 Hz):
- `engine/src/interrupts.c:54` — `tracker_do_periodic_tasks()`

**Game-loop chokepoints** (per-frame deferred):
- `engine/src/game_loop.c:74` — `beeper_play_pending_fx()`
- `engine/src/game_loop.c:81` — `tracker_play_pending_fx()`

**Music control at game-state boundaries**:
- `engine/src/game_loop.c:188-190` — start of game: select song,
  rewind, start
- `engine/src/game_loop.c:282` — end of game: stop

**Flow-rule action sites** (`.gdata`-authored game logic):
- `engine/src/flow.c:315` — `beeper_request_fx()` (action
  `PLAY_SOUND`)
- `engine/src/flow.c:452-453` — `tracker_stop` +
  `tracker_select_song` (action `TRACKER_SELECT_SONG`)
- `engine/src/flow.c:459` — `tracker_stop` (action
  `TRACKER_MUSIC_STOP`)
- `engine/src/flow.c:465` — `tracker_start` (action
  `TRACKER_MUSIC_START`)
- `engine/src/flow.c:473` — `tracker_request_fx` (action
  `TRACKER_PLAY_FX`)

**Game-side custom code** (`game_src/*.c`):
- `games/default/game_src/game_functions.c:80-82` —
  `tracker_select_song`, `tracker_rewind`, `tracker_start`
  (also in `default_jsp`, `monochrome`, `get_weapon`, `vortex2`)
- `games/default/game_src/game_functions.c:109,115,121,127,133,143`
  — `beeper_play_fx( SOUND_CONTROLLER_SELECTED )` and similar
  (controller-selection menu chrome)
- `games/default/game_src/game_functions.c:228,241` —
  `beeper_play_fx( SOUND_GAME_WON )`, `SOUND_GAME_OVER`
- `games/default/game_src/game_functions.c:147-149` —
  `tracker_stop` + `tracker_select_song` + `tracker_rewind`
  pattern at game-state transitions

**Total**: ~20-25 active call sites across engine + 4-5 games.
Strongly chokepointed: every call eventually hits one of 14
public symbols (`init_beeper`, `init_tracker`,
`init_tracker_sound_effects`, `beeper_request_fx`,
`beeper_play_fx`, `beeper_play_pending_fx`,
`tracker_select_song`, `tracker_start`, `tracker_stop`,
`tracker_rewind`, `tracker_do_periodic_tasks`,
`tracker_play_pending_fx`, `tracker_request_fx`,
`tracker_play_fx`). The HAL just needs to capture this set.

---

## 2. ZX-specific assumptions

Distilled from §1.3-§1.5, the platform-coupled assumptions that
must be addressed by the HAL design:

1. **I/O port addresses are inside player asm, not RAGE1**.
   ZX 48K beeper port `#FE`; ZX AY ports `$FFFD`/`$BFFD`; CPC AY
   via PPI at `$F4xx`/`$F6xx`. RAGE1's source never mentions
   these — the BIT/BEEPFX library and the AT2/Vortex player asm
   handle it. **HAL implication**: backend bodies own the I/O;
   the HAL surface is portable.

2. **Beeper exists on ZX only**. ZX 48K has *only* the beeper;
   ZX 128K has beeper + AY (the engine deliberately picks AY +
   Arkos for 128K and uses beeper as a deferred-FX path).
   **CPC has only AY** — no beeper-equivalent. The audio HAL's
   `audio_sfx_*` operations must be backend-implementable on a
   pure-AY platform (where SFX comes from the tracker's SFX
   channel).

3. **BEEPFX format is z88dk-specific**. `BEEPFX_*` constants
   (`bfx_*` symbols in `sound/bit.h`) are addresses of
   pre-compiled byte streams in z88dk's `sound_bit` library
   (related to the SoundFX library by Shiru / Vortex — a beeper
   SFX format authored in a DOS tool). The format is **not
   portable** to CPC. CPC SFX has to come from a different
   source — most cleanly Arkos2's SFX table.

4. **Arkos2 player is multi-hardware-target by design**. The
   same AT2-authored `.aks` source compiles to the same
   `.asm` via `SongToAkg`, and the same generic AKG player
   asm runs on ZX, CPC, MSX, Pentagon — the only thing that
   differs is which hardware `IFDEF` is enabled inside the
   player. This is decisive: **Arkos2 is the audio-format
   bridge** between ZX and CPC (§3.4, §4).

5. **Vortex2 / PT3 is ZX-only by convention.** PT3 was authored
   for ZX-AY by Sergey Bulba; players exist on a few other
   platforms, but the format is firmly Spectrum-cultural. CPC
   AY music is overwhelmingly authored in Arkos2 (and to a
   lesser extent SoundTrakker / StarKos). **CPC backend does
   not implement Vortex2**; on CPC, `TRACKER TYPE=vortex2` is a
   hard error at datagen time.

6. **ISR is 50 Hz on PAL ZX; matches CPC**. No timing rework
   needed for the tick.

7. **AY register `$FFFD` selection state**. On ZX, AY register
   selection is destructive to other peripherals on `$FFFD`
   (none today, but conceptually shared). On CPC, the PPI is a
   different sharing story. Not a HAL concern; backend asm
   handles it.

8. **`init_beeper` zeroes `_sound_bit_state` on 128K only**
   (§1.3). 128K-internal quirk; CPC has nothing analogous.

9. **Tracker code is in `engine/banked_code/128/`**. Banking
   arrangement, not an audio constraint — owned by
   `banking.md`. On CPC-flat (no extra RAM) the same code
   sits inside the 64K binary; on CPC-banked (6128 RAM
   expansion) it can be paged as banking.md decides.

10. **`game_state.beeper_fx` is a raw `void *`** (§1.3). After
    HAL'ification this becomes an opaque cookie produced and
    consumed by the same backend.

11. **`SOUND <event>=BEEPFX_*`** in shared `.gdata`. The RHS is
    the only directly-ZX-named token in audio `.gdata` — every
    game uses 7-8 of them. Addressed in §3.3.

---

## 3. `audio_*` HAL design

The HAL is designed in deliberate parallel with `gfx_*`
(`gfx.md` §2):

- **Keep `audio_*` as the only audio HAL.** No second
  abstraction layer above it.
- **Prefer additive over breaking.** Existing
  `beeper_*` / `tracker_*` symbols stay during the migration
  (Phase AU2 introduces the new names as aliases; Phase AU4
  removes the old).
- **Per-platform `BUILD_FEATURE_AUDIO_MUSIC_BACKEND_*` and
  `BUILD_FEATURE_AUDIO_SFX_BACKEND_*` macro families** (two
  independent axes — see §3.2), mirroring
  `BUILD_FEATURE_GFX_BACKEND_*`.
- **Backend selection driven by `PLATFORM` (`.gdata`)** — see
  `toolchain.md`. Each `PLATFORM` has a default (music, SFX)
  backend selection, overridable in rare cases by an explicit
  `AUDIO_BACKEND` `.gdata` directive (Open Question Q1).

### 3.1 API surface (function-by-function)

The HAL has two logical halves: **music** (continuous,
ISR-ticked) and **SFX** (one-shot, may be ISR-ticked on a
spare channel or blocking on the beeper). Plus a small init/
control surface.

Required operations:

| Operation | Signature | Notes |
|---|---|---|
| **Init / control** | | |
| `audio_init` | `void audio_init( void )` | Replaces `init_beeper` + `init_tracker` + `init_tracker_sound_effects`. Backend chooses what to do. Idempotent. |
| `audio_shutdown` | `void audio_shutdown( void )` | Stop music, silence AY, restore device. Not strictly required today (engine never deinitialises) but useful for clean Q-handling on CPC. Optional in Phase 1. |
| **Music** | | |
| `audio_music_select_song` | `void audio_music_select_song( uint8_t song_id )` | Replaces `tracker_select_song`. Renumbering preserved (same `TRACKER_SONG_*` macros — see §3.3). |
| `audio_music_start` | `void audio_music_start( void )` | Replaces `tracker_start`. |
| `audio_music_stop` | `void audio_music_stop( void )` | Replaces `tracker_stop`. |
| `audio_music_rewind` | `void audio_music_rewind( void )` | Replaces `tracker_rewind`. |
| `audio_music_set_volume` | `void audio_music_set_volume( uint8_t vol )` | **New** (Open Question Q3). Not currently exposed; tracker volume is hard-coded. Optional in Phase 1; recommended for Phase AU5. |
| `audio_music_tick` | `void audio_music_tick( void )` | Replaces `tracker_do_periodic_tasks`. Called from ISR at 50 Hz. Must be a no-op on backends that have no continuous music (e.g. ZX48 beeper-only — see Q2). |
| **SFX (beeper)** | | |
| `audio_sfx_beeper_play` | `void audio_sfx_beeper_play( audio_sfx_beeper_t sfx )` | Replacement for `beeper_play_fx`. `audio_sfx_beeper_t` = pointer to a BEEPFX byte stream. Provided by the `BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_BEEPER` backend. |
| `audio_sfx_beeper_request` | `void audio_sfx_beeper_request( audio_sfx_beeper_t sfx )` | Replacement for `beeper_request_fx`. Sets a per-loop pending flag; the engine plays at the deferred chokepoint. |
| **SFX (tracker)** | | |
| `audio_sfx_tracker_play` | `void audio_sfx_tracker_play( audio_sfx_tracker_t sfx )` | Replacement for `tracker_play_fx`. `audio_sfx_tracker_t` = small integer index into `all_sound_effects[]`. Provided by the `BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_AY` or `BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY` backend. |
| `audio_sfx_tracker_request` | `void audio_sfx_tracker_request( audio_sfx_tracker_t sfx )` | Replacement for `tracker_request_fx`. Sets a per-loop pending flag; the engine plays at the deferred chokepoint. |
| **SFX (shared)** | | |
| `audio_sfx_play_pending` | `void audio_sfx_play_pending( void )` | Called from game-loop chokepoint. Drains whichever SFX backends are active (beeper, tracker, or both). Each backend implements as appropriate. |
| **Backend-private hooks** | | |
| (none) | | The `tracker_specific_*` hook layer in today's `tracker.h` is **absorbed into the backend**. Each backend implements `audio_*` directly. The dispatcher / mute layer that currently lives in `tracker.c` becomes part of the AY backends (`audio_zx_ay.c`, `audio_cpc_ay.c`). Beeper backend (`audio_zx_beeper.c`) implements only the beeper-SFX subset; music ops are no-ops. |

Notes on this surface:

- **SFX is split into two parallel axes — beeper and tracker —
  rather than unified into one `audio_sfx_*` call.** Each axis
  has its own typedef (`audio_sfx_beeper_t` = `void *`,
  `audio_sfx_tracker_t` = `uint8_t`) and its own backend feature
  gate (`BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_BEEPER`,
  `BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_AY`,
  `BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY`). On ZX128 both
  axes are active simultaneously — see §3.1.1 below. The
  per-event `SOUND_<EVENT>` macro expands to whichever
  `audio_sfx_{beeper,tracker}_request(…)` call is appropriate
  at the call site (§3.3).
- **The cookie types** carry per-backend meaning (beeper:
  pointer to BIT FX bytes; tracker: small integer index into
  `all_sound_effects[]`). Authoring side, `.gdata`'s `SOUND`
  directive emits a `SOUND_*` macro whose *both* call-target
  and argument type are picked per active SFX backend (§3.3).
- **`audio_sfx_play_pending`** is a single op even though SFX
  may be split across two backends — the function drains
  *whichever* per-loop flags are armed. Keeps the game-loop
  chokepoint code uniform.
- **`audio_music_tick` as no-op on beeper backend** keeps the
  ISR call site (`interrupts.c:54`) uniform: no `#ifdef` in
  the ISR. Cheap on ZX48 because BSS-zero'd dispatcher is a
  single `ret`.
- **All function names use snake_case** matching `gfx_*`.

#### 3.1.1 ZX128 dual-SFX call signature

ZX128 is the platform where both SFX backends coexist by
design: AY music is running, AY SFX may steal a music
channel (via `TRACKER ... FX_CHANNEL=…`), and the beeper is
still wired and free. Today's `games/default` plays beeper
SFX *while* Arkos2 AY music runs in parallel. The HAL must
support this without ambiguity.

The design:

1. Both `BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_BEEPER` and
   `BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_AY` are active
   together on ZX128 by default. Each backend contributes
   its own typedef and its own request/play functions —
   the two are **coexisting**, not mutually exclusive (this
   is why SFX backend selection lives on a *separate* axis
   from music backend selection — see §3.2).
2. The per-event `SOUND_<EVENT>` macro is emitted by
   datagen so that it captures both the cookie *value*
   and the target call. Authoring decides on a per-event
   basis whether the event is a beeper or tracker FX, by
   the RHS of the `SOUND <event>=<rhs>` directive (or by
   the per-platform `SOUND_MAP` overlay, §3.3). Datagen
   emits, for each event, one of:

   ```c
   // event mapped to a beeper effect:
   #define SOUND_ENEMY_KILLED \
       audio_sfx_beeper_request( (audio_sfx_beeper_t) BEEPFX_HIT_3 )
   // event mapped to a tracker SFX-table index:
   #define SOUND_ENEMY_KILLED \
       audio_sfx_tracker_request( (audio_sfx_tracker_t) 2 )
   ```

   (Engine call sites continue to be written as bare
   `SOUND_ENEMY_KILLED;` statements — the macro carries
   both the call and the argument.)
3. `audio_sfx_play_pending` checks both backends' pending
   flags. On ZX128 it runs the AY-SFX drain first (cheap,
   non-blocking) then the beeper-SFX drain (blocking, see
   R7).
4. **Q4 resolved inline**: the doc's design assumes
   *both* SFX backends are active on ZX128 by default. A
   game that wants beeper-only-on-ZX128 (e.g. to keep all
   three AY channels for the music) disables
   `BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_AY` — concretely,
   by omitting `TRACKER ... FX_CHANNEL=…` from
   `Game.gdata`, which is the same gating signal as
   today's `BUILD_FEATURE_TRACKER_SOUNDFX`.

This dual-typedef + per-event macro pattern is what R4's
mitigation refers to.

### 3.2 Backend split: `zx_beeper`, `zx_ay`, `cpc_ay`, and the macro family

File layout, mirroring `gfx_sp1.h` / `gfx_jsp.h` / `gfx_cpc.h`:

```
engine/include/rage1/audio.h            -- HAL umbrella, selects backend
engine/include/rage1/audio_zx_beeper.h  -- ZX48 / ZX128-beeper-FX backend
engine/include/rage1/audio_zx_ay.h      -- ZX128 AY backend (Arkos2 or Vortex2)
engine/include/rage1/audio_cpc_ay.h     -- CPC AY backend (Arkos2)

engine/src/audio.c                          -- Repurposed sound.c: HAL bookkeeping
                                               only (loop-flag dispatch, no I/O).
engine/banked_code/common/audio_zx_beeper.c -- Beeper backend body (today: beeper.c)
engine/banked_code/128/audio_zx_ay.c        -- AY backend dispatcher (today: tracker.c)
engine/banked_code/128/audio_zx_ay_arkos2.c -- AT2-on-Spectrum bindings (today:
                                               tracker_arkos2.c) — same player .inc,
                                               just renamed.
engine/banked_code/128/audio_zx_ay_vortex2.c -- Vortex2 bindings (today:
                                                tracker_vortex2.c)
engine/banked_code/{flat,128}/audio_cpc_ay.c -- AT2-on-CPC bindings (new in AU4)
engine/banked_code/{flat,128}/audio_cpc_ay_arkos2_player_asm.inc
                                             -- AT2 generic AKG player, assembled
                                                with PLY_AKG_HARDWARE_CPC.
```

(The exact location of CPC audio code — flat 64K vs banked —
is owned by `banking.md`. The names above are a working
proposal that `banking.md` will refine.)

`audio.h` umbrella header (sketch):

```c
#ifndef _AUDIO_H
#define _AUDIO_H

#include <stdint.h>
#include "features.h"

// Music backend (continuous, ISR-ticked): zero or one per build.
#ifdef BUILD_FEATURE_AUDIO_MUSIC_BACKEND_ZX_AY
    #include "rage1/audio_zx_ay.h"
#endif

#ifdef BUILD_FEATURE_AUDIO_MUSIC_BACKEND_CPC_AY
    #include "rage1/audio_cpc_ay.h"
#endif

// SFX backends: independent axis from music. ZX128 typically has
// BOTH the beeper SFX backend AND the AY SFX backend active.
#ifdef BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_BEEPER
    #include "rage1/audio_zx_beeper.h"     // provides audio_sfx_beeper_t
#endif

#ifdef BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_AY
    // typedef provided by audio_zx_ay.h (already included above
    // when music backend is ZX_AY); otherwise the SFX-only AY
    // case (rare) includes it here too.
    #ifndef BUILD_FEATURE_AUDIO_MUSIC_BACKEND_ZX_AY
        #include "rage1/audio_zx_ay.h"     // provides audio_sfx_tracker_t
    #endif
#endif

#ifdef BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY
    // Likewise: typedef typically provided by the CPC music header.
    #ifndef BUILD_FEATURE_AUDIO_MUSIC_BACKEND_CPC_AY
        #include "rage1/audio_cpc_ay.h"
    #endif
#endif

// Required types provided by the relevant backend header(s):
//    typedef void *  audio_sfx_beeper_t;    // beeper backend
//    typedef uint8_t audio_sfx_tracker_t;   // AY backends

// HAL contract — Music (provided by the active music backend):
void  audio_init( void );
void  audio_music_select_song( uint8_t song_id );
void  audio_music_start( void );
void  audio_music_stop( void );
void  audio_music_rewind( void );
void  audio_music_tick( void );

// HAL contract — SFX (provided per active SFX backend):
#ifdef BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_BEEPER
void  audio_sfx_beeper_play( audio_sfx_beeper_t sfx );
void  audio_sfx_beeper_request( audio_sfx_beeper_t sfx );
#endif
#if defined(BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_AY) || \
    defined(BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY)
void  audio_sfx_tracker_play( audio_sfx_tracker_t sfx );
void  audio_sfx_tracker_request( audio_sfx_tracker_t sfx );
#endif
void  audio_sfx_play_pending( void );    // single chokepoint; drains all active

#endif // _AUDIO_H
```

`audio_zx_beeper.h` (sketch):

```c
#include <sound/bit.h>
typedef void *audio_sfx_beeper_t;  // pointer to BEEPFX byte stream

// Provides audio_sfx_beeper_{play,request} only.
// Music ops live on a different backend (or are not provided
// at all on ZX48).
```

`audio_zx_ay.h` (sketch):

```c
#include "rage1/arkos2.h"         // or vortex2.h, depending on TRACKER type
typedef uint8_t audio_sfx_tracker_t;  // SFX index (0..TRACKER_SOUNDFX_NUM_EFFECTS-1)
                                      // For Vortex2 backend: typedef present but
                                      // audio_sfx_tracker_play is a no-op (Vortex2
                                      // has no SFX channel).

// Provides music ops + audio_sfx_tracker_{play,request}.
```

`audio_cpc_ay.h` (sketch):

```c
#include "rage1/arkos2.h"         // Arkos2 forced on CPC; no Vortex2 there.
typedef uint8_t audio_sfx_tracker_t;

// Provides music ops + audio_sfx_tracker_{play,request}.
```

#### `BUILD_FEATURE_AUDIO_*_BACKEND_*` macro family

Two independent axes — direct parallel with
`BUILD_FEATURE_GFX_BACKEND_*` in `gfx.md`, but split into a
**music backend** axis and an **SFX backend** axis. This split
is what lets ZX128 carry AY music + beeper SFX simultaneously
without violating any "mutually exclusive" claim (R4
mitigation refers to this).

**Music backend** (zero or one per build):

| Macro | Active when |
|---|---|
| `BUILD_FEATURE_AUDIO_MUSIC_BACKEND_ZX_AY` | `PLATFORM zx128` with `TRACKER TYPE=arkos2` or `TYPE=vortex2`. |
| `BUILD_FEATURE_AUDIO_MUSIC_BACKEND_CPC_AY` | `PLATFORM cpc464`/`cpc6128` with `TRACKER TYPE=arkos2`. |
| (no music backend defined) | `PLATFORM zx48`, or any platform with no `TRACKER` directive — `audio_music_tick` becomes a build-time no-op. |

**SFX backends** (zero, one, or both per build; the two ZX
SFX backends can coexist):

| Macro | Active when |
|---|---|
| `BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_BEEPER` | `PLATFORM zx48`, OR `PLATFORM zx128` (default — beeper SFX always available alongside any music backend). |
| `BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_AY` | `PLATFORM zx128` with `TRACKER TYPE=arkos2` AND `FX_CHANNEL=…` (i.e. today's `BUILD_FEATURE_TRACKER_SOUNDFX` gate). Coexists with `BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_BEEPER`. |
| `BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY` | `PLATFORM cpc464`/`cpc6128` with `TRACKER TYPE=arkos2` AND `FX_CHANNEL=…`. CPC has no beeper SFX backend. |

Sub-flavour macros stay (Phase AU3 renames cleanly). These are
**capability** macros, orthogonal to the per-axis backend
macros above — they're the renames of today's
`BUILD_FEATURE_TRACKER*` family, not a replacement for the
`AUDIO_*_BACKEND_*` selection:

| Old | New |
|---|---|
| `BUILD_FEATURE_TRACKER` | `BUILD_FEATURE_AUDIO_MUSIC` |
| `BUILD_FEATURE_TRACKER_ARKOS2` | `BUILD_FEATURE_AUDIO_MUSIC_ARKOS2` |
| `BUILD_FEATURE_TRACKER_VORTEX2` | `BUILD_FEATURE_AUDIO_MUSIC_VORTEX2` |
| `BUILD_FEATURE_TRACKER_SOUNDFX` | `BUILD_FEATURE_AUDIO_SFX_TRACKER` (capability flag — implies `BUILD_FEATURE_AUDIO_SFX_BACKEND_{ZX,CPC}_AY` is active) |

(Renames are mechanical and done in Phase AU3. The old names
are emitted in parallel during the deprecation window —
identical pattern to G1-2 in `gfx.md`.)

**Default backend selection** by platform (music axis and SFX
axis listed separately):

| `PLATFORM` | Music backend | SFX backend(s) | Tracker types allowed |
|---|---|---|---|
| `zx48` | (none — silent no-op) | `zx_beeper` | none |
| `zx128` (no `TRACKER`) | (none — silent no-op) | `zx_beeper` | none |
| `zx128` (`TRACKER TYPE=arkos2`) | `zx_ay` | `zx_beeper` + `zx_ay` (both active by default) | `arkos2`, `vortex2` |
| `zx128` (`TRACKER TYPE=vortex2`) | `zx_ay` (vortex2 variant) | `zx_beeper` only (Vortex2 has no SFX) | `arkos2`, `vortex2` |
| `cpc464` | `cpc_ay` | `cpc_ay` | `arkos2` only |
| `cpc6128` | `cpc_ay` | `cpc_ay` | `arkos2` only |

(Resolution depends on Q4. Default: both-active for ZX128. To
force beeper-only-on-ZX128, the user disables
`BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_AY` — concretely by
omitting `TRACKER ... FX_CHANNEL=…` from `Game.gdata`, the
same gating signal as today's `BUILD_FEATURE_TRACKER_SOUNDFX`.)

CPC has only one AY backend; the `TRACKER TYPE` switch
effectively becomes a build-time validator that errors out on
`vortex2` for CPC platforms.

### 3.3 `SOUND` directive cross-platform generalisation

This is the only audio-`.gdata` surface that names ZX-specific
symbols today. Three options were considered.

**Option A — File-level Tier-3 shadow of `Game.gdata` per
platform.**  Author writes:

```
# game_data/game_config/Game.gdata (shared core)
BEGIN_GAME_CONFIG
    NAME mygame
    PLATFORM zx128
    SOUND ENEMY_KILLED=BEEPFX_HIT_3
    ...
END_GAME_CONFIG
```

…and on CPC, the entire `Game.gdata` is shadowed by
`cpc6128/game_data/game_config/Game.gdata` with
`SOUND ENEMY_KILLED=ARKOS_FX_HIT_3` (or whatever the
backend-native ID is). This is the **assets.md Tier 3** model
(`assets.md` §2.4). Pro: zero new mechanism. Con:
`Game.gdata` is usually 30-80 lines and authors end up
duplicating everything else.

**Option B — Per-platform `SOUND` directive scoping.**  Author
writes:

```
SOUND_ZX  ENEMY_KILLED=BEEPFX_HIT_3
SOUND_CPC ENEMY_KILLED=AKM_FX_HIT_3
```

Datagen picks the line matching `PLATFORM`. Pro: keeps the
`Game.gdata` in one file. Con: new syntax; couples `.gdata`
to the platform set.

**Option C — Backend-agnostic IDs in `Game.gdata`, mapping
table elsewhere.**  Author writes:

```
SOUND ENEMY_KILLED=SFX_HIT
SOUND BULLET_SHOT=SFX_SHOT
...
```

…and a per-platform overlay file like
`zx128/game_data/audio/sound_map.gdata` says
`SFX_HIT=BEEPFX_HIT_3` for ZX, and
`cpc6128/game_data/audio/sound_map.gdata` says `SFX_HIT=2`
(Arkos SFX-table index) for CPC.

**Recommendation: Option C.**

Rationale:

- It introduces **one** small new directive
  (`SOUND_MAP <name>=<symbol>`) and reuses the existing overlay
  mechanism (`assets.md`'s sibling-tree shadow) to transport
  the per-platform mapping. The `Game.gdata` itself is fully
  shared.
- The `SOUND_*` event-name surface (e.g. `SOUND_ENEMY_KILLED`)
  stays the *same* token both in `.gdata` flow rules and in
  custom C code — no engine-side changes apart from the macro
  expansion target.
- Tier-3 (Option A) shadow remains a perfectly valid fallback
  for games that *want* to diverge harder. Authors are not
  forced into Option C; it's the recommended path for the
  common case.
- Option B's per-platform-suffix directive is more compact
  but proliferates suffixes
  (`SOUND_ZX48`/`SOUND_ZX128`/`SOUND_CPC464`/…); Option C
  keeps the per-platform variation in *one* place (the
  overlay file).

**Concrete shape** (Phase AU6):

```
# game_data/game_config/Game.gdata (shared)
BEGIN_GAME_CONFIG
    SOUND ENEMY_KILLED=SFX_HIT
    SOUND BULLET_SHOT=SFX_SHOT
    SOUND HERO_DIED=SFX_NOPE
    ...
END_GAME_CONFIG
```

```
# zx48/game_data/game_config/sound_map.gdata (overlay)
SOUND_MAP SFX_HIT=BEEPFX_HIT_3
SOUND_MAP SFX_SHOT=BEEPFX_SHOT_2
SOUND_MAP SFX_NOPE=BEEPFX_NOPE
```

```
# cpc6128/game_data/game_config/sound_map.gdata (overlay)
SOUND_MAP SFX_HIT=2
SOUND_MAP SFX_SHOT=1
SOUND_MAP SFX_NOPE=5
```

…where the CPC RHS values are indices into the CPC Arkos2
SFX table. Datagen emits:

```c
// generated (after applying overlay)
#define SOUND_ENEMY_KILLED \
    audio_sfx_beeper_request( (audio_sfx_beeper_t) BEEPFX_HIT_3 )   // ZX48 / ZX128-beeper
// or
#define SOUND_ENEMY_KILLED \
    audio_sfx_tracker_request( (audio_sfx_tracker_t) 2 )            // ZX128-AY / CPC6128
```

The engine call sites (`flow.c:315`, game custom code) do not
change — they still write `SOUND_ENEMY_KILLED;` as a bare
statement. Only the **macro expansion** is per-platform: both
the target call (`audio_sfx_beeper_request` vs
`audio_sfx_tracker_request`) and the cookie cast are picked
by datagen based on the resolved RHS (§3.1.1).

**Back-compat path** (Phase AU6 transition): if the shared
`Game.gdata` already has `SOUND <event>=BEEPFX_*` (i.e. the
RHS is a known `BEEPFX_*` constant), datagen continues to
emit the ZX mapping verbatim. The new `SOUND_MAP`-via-overlay
mechanism kicks in only when the shared RHS is an unknown
symbol (i.e., a generic `SFX_*` token), at which point datagen
*requires* a per-platform `sound_map.gdata` to resolve it,
and errors clearly if missing. This lets existing games stay
ZX-only without any migration.

### 3.4 Music / SFX file format strategy (Arkos2 sharing, per-platform binaries)

The key finding (§2 item 4): **the AT2 generic AKG player
asm** ships with hardware variants for ZX, CPC, MSX,
Pentagon — all gated by `PLY_AKG_HARDWARE_*` defines (verified
against AT2's
`players/playerAkg/sources/PlayerAkg.asm` and the per-target
testers in `players/playerAkg/sources/tester/`). And the AT2
**song output format** (`SongToAkg`) is *the same byte stream*
regardless of target hardware — it encodes notes, not periods
(period-based pitch effects sound subtly different across
platforms, but that's an artistic concern, not a build one —
see R3 for the audible-regression risk this leaves on the
table across PSG variants).

Consequence: **the same `.aks` source file produces a single
shared `tracker_song_*.asm` byte array that plays correctly
on both ZX-AY and CPC-AY**, when paired with the right
hardware-variant of the AKG player asm.

This is decisive. The strategy:

- **Shared song & SFX *sources* in shared `.gdata`**:
  `TRACKER_SONG NAME=game_song FILE=game_data/music/music1.asm`
  references the same file path for every platform.
- **Per-platform player asm**: backend-specific `.inc`
  selecting `PLY_AKG_HARDWARE_SPECTRUM` for ZX-AY or
  `PLY_AKG_HARDWARE_CPC` for CPC-AY. The player itself is the
  same source; only the hardware define differs. RAGE1
  vendors **one** copy of the player asm and includes it
  with the right define per backend.
- **`TRACKER TYPE=vortex2` stays ZX-only**: parser at
  `datagen.pl:1004-1006` already validates the type; we add
  a platform-aware check (CPC rejects `vortex2`).

#### Per-format compatibility matrix

| Source format | ZX48 | ZX128 + Arkos2 | ZX128 + Vortex2 | CPC + Arkos2 |
|---|---|---|---|---|
| `.aks` (Arkos2 AT2 song) | n/a | yes | n/a | yes |
| `.asm` (pre-converted AT2 AKG asm) | n/a | yes | n/a | yes |
| `.pt3` (Vortex Tracker PT3) | n/a | n/a | yes | no — error at datagen |
| `.aks` (Arkos2 SFX table) | n/a | yes | n/a | yes |
| BEEPFX `bfx_*` byte stream | yes (in `<sound/bit.h>` lib) | yes (deferred FX path) | yes (deferred FX path) | no (no beeper on CPC) |

#### Conversion pipeline (cross-platform)

The Perl-side conversion code in `lib/RAGE/Arkos2.pm`
**does not need to change** for CPC. It only converts the
source format (`.aks` → `.asm` via `SongToAkg`); the produced
asm is identical for ZX-AY and CPC-AY. The platform-specific
piece is **which player asm gets assembled alongside it**,
and that lives in the engine source tree (the `.inc` includes),
not in the build tooling.

What does need to change in the build:

- **Player asm selection** moves into the backend-source
  selection (`audio_zx_ay_arkos2.c` picks
  `audio_zx_ay_arkos2_player_asm.inc`;
  `audio_cpc_ay.c` picks
  `audio_cpc_ay_arkos2_player_asm.inc`). Both `.inc` files
  contain the **same player source** with different
  `PLY_AKG_HARDWARE_*` defines set before the include.
- **`Makefile` glob** for tracker player asm switches based
  on `AUDIO_BACKEND`. Symmetric with how `gfx.md` Phase G7
  handles the CPC stub.

### 3.5 Music asset overlay handling (via `assets.md` sibling tree)

Per `assets.md` §2.5, the file-level recursive overlay copy at
`make config` already transports any per-platform file. For
audio assets:

| File kind | Default location | Per-platform overlay (when needed) |
|---|---|---|
| Arkos2 `.aks` source | `game_data/music/music1.aks` | `cpc6128/game_data/music/music1.aks` only if the CPC version genuinely differs musically |
| Arkos2 pre-converted `.asm` | `game_data/music/music1.asm` | Same overlay path; rare in practice |
| Arkos2 SFX `.aks` | `game_data/music/soundfx.aks` | Per-platform overlay if SFX banks diverge |
| Arkos2 SFX `.asm` | `game_data/music/soundfx.asm` | Same |
| Vortex2 `.pt3` | `game_data/music/music1.pt3` | n/a (ZX only) |
| `sound_map.gdata` (§3.3) | n/a | **always** lives in the overlay tree, never in shared core |

**Tier 1 happy path (recommended for most games)**: the
author writes one `.aks` source, drops it in
`game_data/music/`, and *both* ZX-AY and CPC-AY builds use
the same file. The shared `Game.gdata`:

```
TRACKER         TYPE=arkos2 IN_GAME_SONG=game_song FX_CHANNEL=1 FX_VOLUME=16
TRACKER_SONG    NAME=game_song FILE=game_data/music/music1.aks
TRACKER_SONG    NAME=menu_song FILE=game_data/music/music2.aks
TRACKER_FXTABLE FILE=game_data/music/soundfx.aks
```

…builds correctly on every Arkos2-supporting platform, with
the per-platform difference being entirely the player asm
selected at link time.

**Tier 3 fallback**: if the music does diverge per platform
(e.g. CPC has 16-channel SFX headroom that ZX lacks), the
author overlays the whole `Game.gdata` or specific
`game_data/music/*.aks` files. Same machinery as `assets.md`.

**Tier-2-equivalent** (PNG overlay analogue) is not strictly
useful for audio because there is no "decoding" stage that
applies per-platform; an `.aks` is an `.aks` and the conversion
is one-shot. The per-platform decision is binary: either the
file is shared (Tier 1) or it's shadowed entirely (Tier 3).

#### Loading-screen audio?

Some retro games play a few-note jingle during loading. RAGE1
does not today. Out of scope for Phase 1; flagged in §7
Q7.

---

## 4. CPC audio backend choice

The CPC audio decision boils down to: **which AY player do we
wire into the CPC backend?**

### 4.1 cpctelera Arkos player option

cpctelera (`external/cpctelera/` once vendored — see
`cpc-renderer.md` R1) ships an Arkos player at
`cpctelera/src/audio/`:

- `arkostracker.s` — the player (one stable variant +
  interrupts variant)
- `arkostracker_interrupts.s` — interrupt-driven variant
- `audio.h` — C bindings: `cpct_akp_musicInit`,
  `cpct_akp_musicPlay`, `cpct_akp_stop`,
  `cpct_akp_SFXInit`, `cpct_akp_SFXPlay`,
  `cpct_akp_SFXStopAll`, `cpct_akp_SFXStop`,
  `cpct_akp_SFXGetInstrument`,
  `cpct_akp_setFadeVolume`.
- `arkosplayer.txt` — docs

cpctelera also ships `cpct_aks2c` — an asset-converter that
turns an `.aks` file into a C array. The expected song format
is **AT1 / Arkos Tracker 1**'s AKP format, *not* AT2's AKG.
Reference: 64nops's integration guide
(<https://64nops.wordpress.com/2020/12/20/easy-integration-of-arkos-tracker-2-player-with-cpctelera/>)
explains how to use AT2 with cpctelera and notes the player
needs to be swapped out if you want AKG/AKM rather than the
legacy default. The cpctelera-shipped player is the older
"Arkos Player" (effectively AT1 AKP) and *only* targets the
CPC hardware.

**Pros of using cpctelera's player**:
- Zero extra vendoring decisions: it comes with cpctelera.
- Tightly integrated with cpctelera's interrupt hook
  (`arkostracker_interrupts.s`).
- Single source of truth for cpctelera-style audio.

**Cons**:
- **AT1, not AT2.** Our existing ZX games are all AT2
  `.aks`/`.asm`. Using cpctelera's default player on CPC
  means *re-authoring or re-exporting every song* in the
  AT1-compatible format. The AT2 toolchain can export to
  many formats, but the format that this player consumes is
  not the format `SongToAkg` produces.
- **Player is CPC-only.** It cannot run the same `.aks`
  binary on ZX. So either ZX and CPC diverge on song format
  (we need *two* binaries per song) or we choose a player
  that runs both.
- **License: LGPL-3.0** (per `cpc-renderer.md` §4 line 364)
  — fine for our GPLv3 codebase, but the credit clause for
  Arkos requires a credit line.
- **Smaller community footprint than AT2's AKG.** AT2 is the
  current Arkos generation; AT1 is the legacy generation
  most CPC homebrew has migrated off.

### 4.2 Alternatives (brief)

**Option B — AT2 AKG player (generic, multi-target)**.

Use the **same player source** RAGE1 already vendors for ZX
(`engine/banked_code/128/arkos2-player_asm.inc`), just
assembled with `PLY_AKG_HARDWARE_CPC = 1` instead of
`PLY_AKG_HARDWARE_SPECTRUM = 1`. AT2 ships this player at
`Arkos Tracker 2/players/playerAkg/sources/PlayerAkg.asm`
and tester examples for CPC and ZX exist side-by-side
(`PlayerAkgTester_CPC.asm`,
`PlayerAkgTester_SPECTRUM.asm`).

- Pros:
  - **Single song binary** plays on both ZX-AY and CPC-AY
    (the AKG format encodes notes, not periods).
  - **Zero re-authoring** of existing RAGE1 ZX music — every
    game in `games/` that uses Arkos2 today just works on
    CPC.
  - **One Perl conversion path** (`lib/RAGE/Arkos2.pm`) used
    on both platforms — already maintained.
  - **SFX supported** out of the box
    (`ply_akg_initsoundeffects`, `ply_akg_playsoundeffect`).
  - License: AT2 player asm is freely redistributable with
    the credit clause "Music done with Arkos Tracker by
    Targhan/Arkos" (confirm exact terms during vendoring).
- Cons:
  - We carry the player asm in RAGE1's tree (we already do
    for ZX); on CPC builds we assemble the same source with
    a different `IFDEF`.
  - We do **not** use cpctelera's audio module, even though
    cpctelera is otherwise the CPC graphics backend.
    Slightly asymmetric vs the gfx story.

**Option C — Standalone AY player (e.g. AYUMI, Vortex
ZXAY)**.

Use a player not from either cpctelera or Arkos — for example
Peter Sovietov's AYUMI emulator-driver (the spec, not the
emulator). This is mostly a curiosity; no significant CPC
homebrew uses it. Discarded.

**Option D — Write our own**.

Discarded — `gfx.md` and `cpc-renderer.md` already make the
"vendor, don't write" decision for backends.

### 4.3 Recommendation + justification

**Recommendation: Option B — AT2 AKG generic player, with
`PLY_AKG_HARDWARE_CPC` on CPC builds.**

Justification:

1. **Song-source portability is dispositive.** All existing
   RAGE1 ZX games use AT2 `.aks` / converted `.asm`. Adopting
   Option A (cpctelera's player) would force a one-off
   migration of every song across the test suite, and would
   commit every future RAGE1 game to dual-authoring songs in
   incompatible formats. Option B preserves the existing
   asset pipeline byte-for-byte.

2. **Conversion pipeline reuse.** `lib/RAGE/Arkos2.pm`
   already invokes `SongToAkg` and `SongToSoundEffects` from
   AT2. The same Perl, same external tool, same output asm
   — *that's the bridge*. Adding CPC requires zero changes
   to this code.

3. **Slight asymmetry with gfx is acceptable.** The gfx
   backend uses cpctelera; the audio backend uses
   Arkos-direct. Both are LGPL-3.0; both ship as source we
   compile. The only build-level cost is: when scanning
   cpctelera's source tree (per `cpc-renderer.md` §4.2
   line 466 — `src/audio/akm/` is already excluded), we
   exclude the whole `src/audio/` subtree
   (`-not -path '*/audio/*'`). Trivial Makefile change.

4. **Multi-platform future-friendliness.** Option B
   transparently extends to MSX (`PLY_AKG_HARDWARE_MSX`)
   and Pentagon (`PLY_AKG_HARDWARE_PENTAGON`) when those
   land. The same RAGE1 backend file structure scales by
   one new `.inc` per platform.

5. **Risk profile is lower.** cpctelera's audio path is
   stable but its toolchain wants AT1-format input
   (or `cpct_aks2c` conversion which loses fidelity vs
   `SongToAkg`). Going through AT2's own conversion path
   keeps RAGE1's audio pipeline upstream of cpctelera —
   simpler dependency graph.

The single explicit cost: we **do not use** cpctelera's
`src/audio/`. The Makefile glob in `cpc-renderer.md` §4.2 is
already structured to exclude any audio subtree; the
exclusion grows from "`*/audio/akm/*`" to "`*/audio/*`".

---

## 5. Phased work plan

Each phase ends with `make all-test-builds` green for ZX
(mandatory) and screenshot regression green for any
*unaffected* ZX games (best effort mid-phase; mandatory at
phase exit per the parent plan's anchor). Phases are
*commit groups*; individual tasks need not each leave a
green tree.

Audio-specific success criterion in addition to screenshot
regression: **the existing ZX audible behaviour must remain
unchanged** through Phase AU3 exit. This is harder to
automate than screenshot diffing; see §6 R3. Phase AU1
records a manual "audible baseline" recorded with the
JNEXT emulator capture path for the four representative
games (`default`, `default_jsp`, `vortex2`, `monochrome`).

### Phase AU1 — Audit completion & audible baseline

**Goal**: pin what we have today so the migration's effect
is verifiable.

- **AU1-1** Manually record short audio captures of the four
  representative games (`default` on 128K Arkos2,
  `default_jsp` on 128K Arkos2 with JSP gfx, `vortex2` on
  128K Vortex2, `monochrome` on 128K Arkos2) via JNEXT or
  another emulator capable of audio capture.
  *What to test*: recordings exist and contain identifiable
  music + at least one in-game SFX (BULLET_SHOT,
  ENEMY_KILLED).
  *Expected outcome*: baseline `.wav` (or similar) files
  checked into `doc/multiplatform-plan/audio-baseline/` —
  authored once, used for ear-comparison through Phase AU3.
- **AU1-2** Inventory annotation: leave the §1.6 caller list
  in this document as the single source of truth (rather
  than scatter `// HAL-CALLER` comments through code).
  *What to test*: regenerate the inventory with `grep
  -rn 'beeper_\|tracker_'` against current HEAD and confirm
  zero drift vs §1.6.
  *Expected outcome*: list matches HEAD.
- **AU1-3** Verify the AT2 hardware-define mechanism works
  on a synthetic CPC asm fragment. *Outside* the engine —
  just a `misc/au-spike/` standalone asm-only program that
  assembles `arkos2-player_asm.inc` twice (once with
  `PLY_AKG_HARDWARE_SPECTRUM`, once with `PLY_AKG_HARDWARE_CPC`)
  and confirms both produce sensible output sizes. No engine
  link.
  *What to test*: two `.bin` files produced; nm/sizes
  documented.
  *Expected outcome*: confirmation that the same player
  source builds for both hardware variants in our existing
  toolchain.
- **Phase-exit criteria**:
  - Audible baseline recorded for the 4 representative games.
  - Spike build confirms AT2 dual-target works under our
    toolchain.
  - `make all-test-builds` green; `tests/00regression/`
    green.

### Phase AU2 — Introduce `audio_*` HAL aliases (ZX-only, no semantic change)

**Goal**: introduce the new HAL function names as
**aliases** for the existing functions. Nothing migrates yet
— this is name-space prep. Same low-risk approach as
G1-2 / G2 in `gfx.md`.

- **AU2-1** Add `engine/include/rage1/audio.h` and the three
  backend headers
  (`audio_zx_beeper.h`, `audio_zx_ay.h`, `audio_cpc_ay.h`).
  CPC header is a stub (#error if included on a non-CPC
  build).
  *What to test*: builds green; no behaviour change.
  *Expected outcome*: HAL surface is `#include`able.
- **AU2-2** Make the new `audio_*` names callable as inline
  static-redirect aliases for the existing `beeper_*` /
  `tracker_*` symbols. E.g.
  ```c
  static inline void audio_sfx_beeper_request( audio_sfx_beeper_t s ) {
      beeper_request_fx( s );
  }
  static inline void audio_sfx_tracker_request( audio_sfx_tracker_t s ) {
      tracker_request_fx( s );
  }
  ```
  Done inside the backend headers — no extra TU.
  *What to test*: `make all-test-builds` green; binary
  byte-identical to pre-AU2.
  *Expected outcome*: the engine *could* migrate any
  call-site to `audio_sfx_beeper_request` /
  `audio_sfx_tracker_request` and binary stays identical.
- **AU2-3** Add `BUILD_FEATURE_AUDIO_MUSIC_BACKEND_*` and
  `BUILD_FEATURE_AUDIO_SFX_BACKEND_*` macros to
  `tools/datagen.pl` (emitted alongside the existing macros,
  not replacing). Mapping per §3.2 tables: `PLATFORM zx48` →
  `AUDIO_SFX_BACKEND_ZX_BEEPER` only; `PLATFORM zx128` with
  `TRACKER` → `AUDIO_MUSIC_BACKEND_ZX_AY` +
  `AUDIO_SFX_BACKEND_ZX_BEEPER` (+ `AUDIO_SFX_BACKEND_ZX_AY`
  when `FX_CHANNEL` is set); `PLATFORM zx128` without
  `TRACKER` → `AUDIO_SFX_BACKEND_ZX_BEEPER` only.
  *What to test*: grep `build/generated/features.h` after
  rebuild — confirm new macros present alongside legacy ones.
  *Expected outcome*: features header carries both naming
  conventions.
- **Phase-exit criteria**:
  - `audio.h` umbrella + three backend headers exist.
  - Alias paths are exercised in at least one test-game
    build (any one of the existing games, no `.gdata`
    change).
  - All test games still build identically — `make
    all-test-builds` green.
  - Audible baseline match (ear-test) for the four
    recorded games.

### Phase AU3 — Migrate engine + games to `audio_*` names

**Goal**: flip every `beeper_*` / `tracker_*` call site to
the new HAL names. Mechanical; risk is breadth, not depth.

- **AU3-1** Migrate engine internal call sites
  (§1.6 list): `main.c`, `interrupts.c`, `game_loop.c`,
  `flow.c`. One commit per file.
  *What to test*: per file, `make all-test-builds`; on
  `flow.c` exit, audible re-test against baseline.
  *Expected outcome*: each file's `grep beeper_\|tracker_`
  returns zero.
- **AU3-2** Migrate generated `flow.c` action names.
  `do_rule_action_play_sound` becomes
  `do_rule_action_audio_sfx`;
  `do_rule_action_tracker_*` become
  `do_rule_action_audio_music_*` /
  `do_rule_action_audio_sfx`. Datagen's action-name table
  (`tools/datagen.pl:2475,2492-2495`) plus the rule-action
  function-pointer table (`flow.c:755-771`) update in
  lockstep. Keep old action names as `.gdata` aliases for
  one deprecation cycle (PLAY_SOUND → AUDIO_SFX, etc.).
  *What to test*: every test game still builds; rule
  dispatch tables in `build/generated/` updated.
  *Expected outcome*: zero `tracker_*` action symbols in
  generated code.
- **AU3-3** Migrate game-side custom code (§1.6 game
  call-sites). Edit the 5-6 affected `game_src/*.c` files.
  *What to test*: each game builds and is audibly equivalent
  to its baseline recording.
  *Expected outcome*: zero `beeper_*` / `tracker_*` callers
  in `games/`.
- **AU3-4** Rename `engine/banked_code/common/beeper.c` →
  `audio_zx_beeper.c`. Rename
  `engine/banked_code/128/tracker.c` →
  `audio_zx_ay.c`. Rename
  `engine/banked_code/128/tracker_arkos2.c` →
  `audio_zx_ay_arkos2.c`. Rename
  `engine/banked_code/128/tracker_vortex2.c` →
  `audio_zx_ay_vortex2.c`. Rename headers
  correspondingly. Update Makefile object lists.
  *What to test*: `make all-test-builds` green.
- **AU3-5** Rename `BUILD_FEATURE_TRACKER*` →
  `BUILD_FEATURE_AUDIO_*` (per §3.2 table). Datagen emits
  both names through one deprecation cycle.
  *What to test*: `make all-test-builds` green; feature
  macros visible in both naming conventions.
- **AU3-6** Update `etc/rage1-config.yml:59-114`
  banked-functions table — rename entries to use the
  `audio_*` names. Regenerate banked function defs and the
  banked function ASM table.
  *What to test*: `make all-test-builds` green; banked
  call sites resolve.
- **AU3-7** Remove the alias layer added in AU2-2 (drop the
  `static inline` redirects). All callers now use the new
  names directly.
  *What to test*: `make all-test-builds` green; grep for
  removed symbols returns zero hits.
- **Phase-exit criteria**:
  - No `beeper_*` / `tracker_*` C-symbols in engine, games,
    generated code, or config (one `grep -r` confirms it).
  - All test games build and audibly match the baseline
    recordings.
  - `tests/00regression/` ZX screenshot tests green.

### Phase AU4 — CPC audio backend skeleton (stub)

**Goal**: prove the integration shape for a CPC backend
with no real audio. Pre-vendoring of the CPC Arkos player
binary; just the C-side scaffolding.

- **AU4-1** Add `engine/include/rage1/audio_cpc_ay.h` with
  the full HAL contract (function prototypes, typedefs,
  macros).
  *What to test*: `#include`able from a synthetic CPC
  compile-test game (cf. `gfx.md` G7).
- **AU4-2** Add a CPC audio backend stub C file
  (location TBD by `banking.md` — for now,
  `engine/src/audio_cpc_ay.c` is a safe placeholder). Stub
  bodies: all `audio_*` ops are empty (return immediately).
  Gated `#ifdef BUILD_FEATURE_AUDIO_MUSIC_BACKEND_CPC_AY` /
  `#ifdef BUILD_FEATURE_AUDIO_SFX_BACKEND_CPC_AY`.
  *What to test*: when the stub is selected, all callers
  link; the binary plays no sound but is otherwise
  functional. Compile-only verification at this stage.
- **AU4-3** Wire `tools/datagen.pl` and `Makefile.common`
  to emit/select `AUDIO_MUSIC_BACKEND_CPC_AY` (+
  `AUDIO_SFX_BACKEND_CPC_AY` when `FX_CHANNEL` is set) for
  CPC platforms.
  Validate `TRACKER TYPE=vortex2` is rejected on CPC.
  *What to test*: synthetic `games/00cpc-compile-test/`
  (introduced in `gfx.md` G7-4) compiles with audio stub
  active; zero link errors.
- **AU4-4** Vendor the AT2 AKG player source (single copy)
  at `engine/banked_code/audio/arkos2_player.asm`
  (location TBD by `banking.md`). RAGE1 currently has the
  player at `engine/banked_code/128/arkos2-player_asm.inc`
  — that file remains as the *Spectrum-variant* include
  wrapper, and the actual player asm is moved to the
  shared location with `#ifdef`s for hardware variants.
  *What to test*: ZX builds still green; player asm
  byte-identical to pre-move for ZX targets.
- **Phase-exit criteria**:
  - CPC audio stub compiles against the synthetic CPC
    compile-test game.
  - ZX builds unchanged — audible baseline still matches.
  - AT2 player asm is in one canonical location, used by
    both ZX and (eventually) CPC backends.

### Phase AU5 — Real CPC audio backend

**Goal**: real, audible CPC audio. Depends on
`cpc-renderer.md` Phase R1/R2 (cpctelera vendored, toolchain
marriage) and `gfx.md` Phase G7/G8 (CPC gfx wiring) being
landed so we have something to listen *through*.

- **AU5-1** Add `audio_cpc_ay_arkos2_player_asm.inc` —
  a one-line file `PLY_AKG_HARDWARE_CPC = 1` followed by
  `include "engine/banked_code/audio/arkos2_player.asm"`
  (and the stubs include). The companion
  `audio_zx_ay_arkos2_player_asm.inc` does the same with
  `PLY_AKG_HARDWARE_SPECTRUM = 1`.
  *What to test*: both assemble cleanly with `zcc +zx` and
  `zcc +cpc` respectively.
- **AU5-2** Replace the CPC audio stub with real
  Arkos2 bindings — copy the Spectrum bindings
  (`audio_zx_ay_arkos2.c`) and rename to
  `audio_cpc_ay_arkos2.c`. The C body is **identical** —
  it calls the same `ply_akg_*` symbols, which are
  provided by the platform-specific player asm.
  *What to test*: `games/minimal` (the smallest test game)
  builds on `PLATFORM cpc6128` with `TRACKER TYPE=arkos2`
  and one short song; produces audible music on CPC
  emulator (Caprice32 or RVM).
- **AU5-2.1** On first `audio_init` for CPC, write `0` to
  the AY mixer / amplitude registers (R7=R8=R9=R10=R11=R12
  = `0`) **before** any song selection. This silences the
  PSG on a cold boot so that the brief window between
  `audio_init` and the first `audio_music_select_song`
  cannot leak undefined-state noise. Ties directly to R8.
  *What to test*: power-cycle a CPC emulator, run a build
  that calls `audio_init` but never starts a song —
  confirm silence (no white-noise / tone leakage).
- **AU5-3** Wire CPC `audio_sfx_play_pending` via the
  Arkos2 SFX channel. The Spectrum path uses
  `ply_akg_playsoundeffect( id, TRACKER_SOUNDFX_CHANNEL,
  16 - TRACKER_SOUNDFX_VOLUME )` — the CPC path is the
  same. Verify in `games/default`'s CPC build.
  *What to test*: bullet-shoot SFX audibly plays on CPC.
- **AU5-4** Implement the `audio_music_set_volume` op for
  Arkos2 backends (both ZX and CPC). Maps to AT2's fade
  primitives — `ply_akg_*_fade` — if available, otherwise
  no-op with a comment. (Phase AU5 nice-to-have.)
  *What to test*: synthetic test that lowers volume mid-song.
- **AU5-5** Update `lib/RAGE/Arkos2.pm` if any per-platform
  conversion flag is needed. Current expectation: **none**
  — the `.aks` → `.asm` conversion is target-agnostic.
  Phase work is to confirm this and document.
  *What to test*: ZX and CPC builds of `games/default`
  reference the same `tracker_song_*.asm` byte array
  (verified by `nm`).
- **Phase-exit criteria**:
  - At least one CPC test game (`games/minimal` and
    `games/default`) builds, runs, plays music, plays SFX
    on Caprice32 / RVM.
  - All ZX test games still build and audibly match
    baseline.
  - CPC + ZX both produce identical `tracker_song_*.asm`
    bytes for the same `.aks` source (proves cross-platform
    asset sharing works).

### Phase AU6 — `SOUND` directive cross-platform generalisation

**Goal**: introduce the Option-C mapping (§3.3) so games
share most of `Game.gdata` and only the platform-specific
SFX IDs differ. Strict-additive; existing ZX games keep
working without migration.

- **AU6-1** Add `SOUND_MAP <name>=<symbol>` directive
  parsing to `tools/datagen.pl`. Lives in `GAME_CONFIG`
  state, simple key/value collection same shape as `SOUND`.
  *What to test*: parse a synthetic file with `SOUND_MAP`,
  inspect resulting `$game_config->{'sound_map'}`.
- **AU6-2** Adjust the `SOUND <event>=<rhs>` parser to
  optionally treat `<rhs>` as a *generic name* (the
  Option-C path): if the RHS is **not** a known
  `BEEPFX_*` constant and **not** an integer literal,
  emit a generic `SOUND_<EVENT>` macro that expands to
  the `SOUND_MAP` table lookup. The mapping is finalised
  after both `SOUND` and `SOUND_MAP` directives have been
  parsed.
  *What to test*: pre-existing ZX games with literal
  `BEEPFX_*` still build verbatim; a new `games/test_sound_map/`
  synthetic game uses generic IDs and resolves them via
  overlay.
- **AU6-3** Migrate `games/default` to the Option-C model:
  shared `SOUND ENEMY_KILLED=SFX_HIT`, ZX overlay
  `SOUND_MAP SFX_HIT=BEEPFX_HIT_3`, CPC overlay
  `SOUND_MAP SFX_HIT=2`. Test on both platforms.
  *What to test*: `games/default` on ZX48, ZX128, CPC6128
  all build and audibly match (a different SFX, but a
  defined one, on CPC).
- **AU6-4** Document the directive in `doc/DATAGEN.md`
  alongside `SOUND`. Update Open Question 8 of
  `assets.md` to closed.
  *What to test*: doc-only.
- **Phase-exit criteria**:
  - `SOUND_MAP` directive recognised by datagen.
  - One representative game (`games/default`) demonstrates
    the cross-platform `SOUND_MAP` flow end-to-end.
  - Existing ZX-only games unchanged in behaviour.
  - `make all-test-builds` green.

### Phase AU7 — Hardening, cleanup, deprecation

**Goal**: close out the migration and the documentation.

- **AU7-1** Remove the deprecated `BUILD_FEATURE_TRACKER*`
  macro aliases from `datagen.pl` (now `AUDIO_*` only).
- **AU7-2** Remove the deprecated `PLAY_SOUND` /
  `TRACKER_*` flow-rule action keyword aliases (now
  `AUDIO_SFX` / `AUDIO_MUSIC_*`).
- **AU7-3** Add CPC audio to the CI matrix line introduced
  by `cpc-renderer.md` / `testing.md`.
- **AU7-4** Update `doc/DATAGEN.md` audio section: name
  the HAL, the backend matrix, the `SOUND_MAP` directive.
- **AU7-5** Remove cpctelera's `src/audio/` from the
  cpctelera glob (excluded by `-not -path '*/audio/*'`)
  with a justifying comment pointing to this document's
  §4.3.
- **Phase-exit criteria**:
  - No `TRACKER*` macro / keyword in engine, datagen,
    Makefiles, or game data.
  - CI green on ZX48 + ZX128 + CPC6128 audio lanes.
  - Docs reflect final state.

---

## 6. Risks

- **R1 — AT2 player asm assembly under z88dk's z80asm vs
  RASM.** AT2's `PlayerAkg.asm` is authored in RASM syntax.
  Today RAGE1's `arkos2-player_asm.inc` is the
  RASM-flavoured source patched/rewritten to z88dk z80asm
  syntax (the file is hand-massaged). The CPC variant
  needs the same syntax-port and the same hardware-define
  hooks. If the upstream AT2 player changes, the
  syntax-port has to be redone.
  *Mitigation*: Phase AU1-3's spike already isolates the
  assembly step; if it succeeds, the syntax port is good
  for both Spectrum and CPC variants (since the only
  difference is the `IFDEF` branch). Track the upstream
  AT2 player version in a `VERSION.txt` next to the
  vendored asm.

- **R2 — cpctelera's audio module gets pulled in
  accidentally.** `cpc-renderer.md` §4.2's source glob
  `find $(CPCTELERA_SRC) -name '*.c' -not -path '*/audio/akm/*'`
  excludes only `audio/akm/`, not the whole audio tree.
  Without the AU7-5 fix, builds may link both cpctelera's
  Arkos player and RAGE1's AT2 player and conflict on AY
  state.
  *Mitigation*: AU7-5 explicit exclusion; assert at link
  time that `cpct_akp_*` symbols are not in the final
  binary (CI grep on `nm` output).

- **R3 — Audible regression is hard to test
  automatically.** Screenshot regression catches gfx
  drift, but audio drift is much subtler — same player,
  slightly different tick alignment, and pitch effects
  shift. Detection requires WAV-spectral comparison or
  ear-testing.
  *Mitigation*: ear-test against the AU1-1 baseline
  recordings at each phase exit. Long-term: integrate
  FUSE/JNEXT audio-capture into `tests/00regression/`
  with a tolerant spectral diff. Tracked as Open Question
  Q5.

- **R4 — `audio_sfx_*` typedef per backend, on a platform
  (ZX128) where two SFX backends coexist.** Today
  `beeper_request_fx(void *)` and `tracker_request_fx(uint16_t)`
  take different argument types. The HAL keeps both —
  `audio_sfx_beeper_t = void *` (BIT FX byte stream pointer)
  and `audio_sfx_tracker_t = uint8_t` (SFX-table index) —
  by splitting the SFX backend feature axis from the music
  backend axis (§3.2). ZX128 builds get **both** typedefs and
  **both** request/play function families in scope
  simultaneously.
  *Mitigation*: the design defined in §3.1.1 ("ZX128
  dual-SFX call signature"): two distinct HAL ops
  (`audio_sfx_beeper_request` / `audio_sfx_tracker_request`)
  plus a per-event `SOUND_<EVENT>` macro that expands to
  whichever request call is appropriate at the call site
  (§3.3 picks beeper vs tracker per event). Phase AU3-2
  rolls this out. Alternative considered and rejected:
  unify to one `uintptr_t`-typed `audio_sfx_t` — costs ZX
  code size in the common (small-integer) case and forces
  the dispatcher to discriminate at runtime.

- **R5 — Banked-call dispatcher cost for tracker tick.**
  `tracker_do_periodic_tasks` is currently a banked
  function called from the IM2 ISR. The dispatcher
  preserves SP, switches banks, dispatches, restores SP,
  switches banks back. On CPC-flat (no banking, the
  64K464 case) there should be no dispatcher overhead;
  ensuring the build emits a direct call there is a
  banking concern (`banking.md`), but the audio HAL
  needs to be checked for accidental indirection.
  *Mitigation*: Phase AU5 includes a tick-cost spot
  check on CPC464 (`make mem` size delta of the audio
  path) and on ZX128 (no regression vs baseline).

- **R6 — Vortex2 dies on CPC, surprising existing
  Vortex2 author.** `games/vortex2` is the only Vortex2
  game today; if a Vortex2-using author retargets to
  CPC the build fails at datagen.
  *Mitigation*: clear error message in datagen
  ("TRACKER TYPE=vortex2 is not supported on CPC
  platforms — convert to TYPE=arkos2"). `games/vortex2`
  has a sibling `.aks` next to its `.pt3`
  (`games/vortex2/game_data/music/music1.aks` is present
  per §1.2 audit) — re-authoring as Arkos2 is a small
  user task.

- **R7 — Beeper SFX timing on ZX128 with AY music
  running.** `bit_beepfx` is blocking; while it runs the
  Arkos AY tick is still triggered from ISR but the AY
  tempo will drift slightly because the player's
  scheduling assumes timely ticks. This is a pre-existing
  issue, not introduced by the HAL.
  *Mitigation*: document; consider adding a "stop
  beeper-SFX-during-music" option in Phase AU5 follow-up
  if the drift is audible. Track as Open Question Q6.

- **R8 — CPC AY initial register state.** On a cold boot,
  the CPC's PSG mixer / envelope / amplitude registers are
  in undefined state. The Arkos player initialises them
  on first `ply_akg_init`, but if `audio_init` is called
  before the first song is selected the AY may emit
  noise. ZX has the same issue but the BIT player
  silences the beeper on init. Verify CPC behaves
  equivalently.
  *Mitigation*: **AU5-2.1** explicitly writes `0` to the
  AY mixer / amplitude registers in `audio_init` for CPC
  before any song selection. This forecloses the
  undefined-state-noise window regardless of what the
  Arkos player does internally.

- **R9 — Schedule blowup at AU5.** AU5 depends on
  cpc-renderer + toolchain landing first. If those slip,
  AU5 slips. Phases AU1-AU4 + AU6 are all do-able
  independently of cpctelera.
  *Mitigation*: same pattern as gfx.md R7 — AU4 (stub)
  delivers all the integration shape without the
  library dependency. If AU5 slips, the codebase is in a
  measurably better state regardless.

- **R10 — License-credit clause for Arkos.** The AT2
  player license requires a credit "Music done with
  Arkos Tracker by Targhan/Arkos" in any project using
  it. RAGE1's `README.md` should carry this and our games'
  loaders should display it on the loading screen (or
  at least in their `--help` / about screens). Same
  requirement on ZX today; no new burden, but flag it.
  *Mitigation*: AU7-4 doc pass adds the credit lines.

---

## 7. Open Questions

These need user resolution before or during execution.

- **Q1 — Explicit `AUDIO_BACKEND` directive in `.gdata`?**
  The default backend per `PLATFORM` is unambiguous in
  Phase 1 (§3.2 table). Do we ever want an explicit
  override (e.g. "force the beeper backend on ZX128
  even though AY is available")? Recommended default:
  **no explicit directive in Phase 1** — the platform's
  default backend stands. Add `AUDIO_BACKEND` directive
  only if a real use case appears. Confirm.

- **Q2 — ZX48 music: silent no-op or beeper jingle?**
  Today, `BUILD_FEATURE_TRACKER` is 128K-only; ZX48
  games have no music at all. Should `audio_music_*`
  ops on ZX48 silently no-op, or should we leave open
  the door to a beeper-music backend (a la `1tracker`
  beep music)? Recommended: **silent no-op in Phase 1**;
  defer beeper-music as a future option. Confirm.

- **Q3 — `audio_music_set_volume` op required?**
  Today there is no run-time volume control. AT2's
  player supports fade-to-volume; CPC and ZX both. Worth
  exposing? Recommended: **add it as an optional op in
  AU5-4** if Arkos exposes the symbol; backend may
  no-op otherwise.

- **Q4 — ZX128: parallel beeper + AY SFX?**
  ZX128 has both available. `games/default` today uses
  beeper SFX exclusively (the BEEPFX_* `SOUND` lines)
  while running Arkos AY music. After the HAL, should
  ZX128 prefer beeper SFX (lower-latency, no AY
  channel cost) or AY SFX (better timbre, but steals an
  AY channel from the music)?
  **Resolved (§3.1.1, §3.2)**: both SFX backends are
  active on ZX128 by default — the design assumption is
  "both coexist". Per-event routing (beeper vs AY) is
  decided at datagen time by the `SOUND <event>=<rhs>` RHS
  (and per-platform `SOUND_MAP` overlays, §3.3). A game
  that wants beeper-only-on-ZX128 disables
  `BUILD_FEATURE_AUDIO_SFX_BACKEND_ZX_AY` — concretely by
  omitting `TRACKER ... FX_CHANNEL=…` from `Game.gdata`
  (same gating signal as today's
  `BUILD_FEATURE_TRACKER_SOUNDFX`). Two coexisting
  typedefs (`audio_sfx_beeper_t = void *` and
  `audio_sfx_tracker_t = uint8_t`) are picked per call
  site by the `SOUND_*` macro expansion.

- **Q5 — Automated audio regression.**
  Today regression is screenshot-based; audio is ear-
  tested. Should `tests/00regression/` grow an audio-
  diff path (capture WAV, spectral compare with
  tolerance)? Recommended: **not in Phase 1** — ear test
  against the AU1-1 baselines suffices for the migration.
  Future improvement, tracked here. Confirm.

- **Q6 — Beeper-FX vs AY-music timing interaction.**
  R7: blocking `bit_beepfx` on ZX128 disturbs AY tempo
  slightly. Worth fixing — by deferring beeper FX to AY
  silence, or by running beeper FX in a smaller chunked
  state machine that yields to AY ticks? Recommended:
  **document the trade-off**, do not fix in Phase 1
  unless audible during baseline-recording. Confirm.

- **Q7 — Loading-screen jingle?**
  No game ships one today; ZX BASIC loader simply does
  `LOAD`. CPC loader story is similar. Add a one-shot
  "play a jingle while loading" feature? Recommended:
  **out of scope for Phase 1**.

- **Q8 — Music files in shared vs per-platform location.**
  Authoring convention: put the `.aks` source in shared
  `game_data/music/`, the per-platform converted assets
  under each platform overlay? Or keep shared `.aks` +
  let the build pipeline convert per platform? Per §3.4
  the conversion is target-agnostic so shared `.aks` is
  enough. Confirm the recommendation: **shared `.aks`
  only**, no per-platform overlay needed for the happy
  path.

- **Q9 — Vortex2 retirement?**
  Only one game (`games/vortex2`) uses Vortex2, and it
  already has a sibling `.aks` source. Is this game's
  PT3 path culturally important to preserve, or do we
  retire it in favour of Arkos2 universally? Recommended:
  **keep Vortex2 backend** — it's small (~70 lines of
  binding + the player asm), it's only ZX, and it
  removes the risk of audible drift in the
  `games/vortex2` baseline. Confirm.

- **Q10 — MSX / C64 placeholder.**
  Per the parent task, MSX and C64 are sketch-only. MSX
  is a clean fit (AT2 already has `PLY_AKG_HARDWARE_MSX`
  and the AY model holds). C64's SID is utterly
  different — no AT2 hardware target, no Arkos. C64
  audio is a from-scratch reimplementation against a
  SID player (e.g. `cc1541` family). The HAL doesn't
  block this — `audio_*` is general enough — but C64
  remains a long-horizon item, not blocked by Phase 1
  decisions. Confirm no Phase 1 decision is disqualifying.

---

*End of audio.md.*

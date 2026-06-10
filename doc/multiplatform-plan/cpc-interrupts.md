# CPC interrupts: RAGE1-owned IM1 ISR (flat + banked, unified)

Status: PLAN, design converged (2026-06-11). Supersedes the interim `dataset.c`
DI fix (commit 31e9b61), which is removed as the final verified step.

## 1. Goal

A single RAGE1-owned interrupt schema, identical for **cpc-flat and cpc-banked**:

- RAGE1 installs its **own IM1 handler in always-mapped low memory** (< 0x4000)
  and takes full control — **no firmware ISR**, in either mode.
- The handler derives the engine's **50 Hz tick from the CPC VSYNC**, so
  `do_timer_tick()` / `do_periodic_isr_tasks()` run with the same cadence and
  semantics as the ZX IM2 ISR (whose 50 Hz is likewise VSYNC-locked).
- Handler + `memory_switch_bank` both live in low memory, and the 50 Hz body runs
  **with interrupts enabled**, so a tick may fire while an expansion bank is paged
  into 0x4000–0x7FFF and may itself call banked code (future tracker music) — the
  reentrant banked-call-from-ISR case of `doc/BANKED-FUNCTIONS.md`.

## 2. Why (root cause, proven)

On cpc-banked the current IM1 dispatch routes through the z88dk-clib vector walker
(`asm_interrupt_handler` ~0x5803 + `im1_vectors`/`fast_vectors` ~0x6B21/0x6B36),
which physically sit **inside** the 0x4000–0x7FFF bank-swap window. A tick during a
dataset decompress (bank paged in) vectors into paged-out code → crash (proven on
cap32; the interim DI fix masks it). The fix is to own the IM1 vector directly in
low memory — and, per the unification decision, do the same on cpc-flat instead of
leaning on the firmware/CRT interposer.

## 3. Current state

- **cpc-flat:** stock z88dk `cpc_crt0`; engine registers `cpc_fast_isr` via
  `cpc_add_fast_isr()` into the CRT `fast_vectors`; CRT interposer at 0x0038 walks
  the clib vector table.
- **cpc-banked:** custom `crt0-cpc-banked.asm`; same `cpc_add_fast_isr()` path and
  clib vector walk (the in-window hazard).
- Both share `interrupts.c` `cpc_fast_isr()` (full IX/IY+shadow save every 300 Hz
  interrupt, C divide-by-six) and `init_interrupts()`.

## 4. Target install (unified)

`init_interrupts()` (CPC branch, shared flat+banked) becomes the **single
installer**, independent of which crt0 built the image:

```
di
im 1
poke 0x0038 = JP ; poke 0x0039..A = rage1_cpc_isr     ; RAGE1 owns the IM1 vector
reset cpc_isr_div_counter = 0, isr_busy = 0, interrupt_nesting_level = 0,
      periodic_tasks_enabled = 0
ei
```

- No `cpc_add_fast_isr`, no clib `fast_vectors`/`asm_interrupt_handler`, no firmware
  ISR — identical for both CPC modes.
- `crt0-cpc-banked.asm`: the `__interposer_isr__` vector-walk body + its clib
  EXTERNs become dead — trim them. Keep only what the loader→game handover needs
  before `init_interrupts()` runs (TBD; ideally nothing — `init_interrupts()` is
  the sole installer).
- cpc-flat: no `-crt0` change required if `init_interrupts()` overwrites 0x0038 and
  fully owns IM1; verify the stock CRT does not re-assert the firmware ISR behind us
  (e.g. on any firmware call we no longer make).

**Placement requirement:** `rage1_cpc_isr` (the asm wrapper) MUST link in an
always-mapped low section (< 0x4000) on cpc-banked — e.g. the lowmem asm unit that
already holds `interrupt_nesting_level`/`cpc_isr_div_counter`
(`engine/src/cpc-banked/asmdata_cpc_banked.asm`), not left to `code_compiler` link
order. The C body it calls (`do_timer_tick`/`do_periodic_isr_tasks`) is already low.
On cpc-flat placement is unconstrained but kept uniform.

## 5. The handler — VSYNC-driven 50 Hz, interruptible slow path

### 5.1 Model
The CPC raster interrupt fires ~6×/frame (300 Hz), hardware-synchronised to VSYNC by
the Gate Array. RAGE1 does **not** count to six to make the tick — it detects
**VSYNC** (PPI port B bit 0), which happens exactly once per frame, and that IS the
50 Hz tick (the "divide by six" is implicit in VSYNC recurring once per 6
interrupts). The tick body runs **with interrupts enabled** so that (a) interrupts
are never lost across a long body, (b) the frame counter stays VSYNC-synced even
during an overrun, and (c) the body may call banked code.

### 5.2 The handler (low memory, at 0x0038)
```
rage1_cpc_isr:                ; entered DI (Z80 auto-DI on IM1 accept)
    push af / push bc
    ld a,(cpc_isr_div_counter) / inc a / ld (cpc_isr_div_counter),a
    ld b,$f5 / in a,(c) / rra              ; carry = VSYNC bit (read FIRST, ~6-8 instr in)
    jr nc,.exit                            ; not VSYNC -> just advanced the counter
    ; --- VSYNC: frame boundary ---
    xor a / ld (cpc_isr_div_counter),a     ; resync: counter = 0
    ld a,(isr_busy) / or a
    jr nz,.exit                            ; body already running -> skip (= missed tick)
    ld a,1 / ld (isr_busy),a               ; [DI] test+set is atomic
    [full save: de, hl, ix, iy, + shadow set (exx/ex af,af')]
    ;  ^ shadow set (AF'/BC'/DE'/HL') saved for parity with the ZX IM2 ISR
    ;    (asm_im2_push_registers saves the full shadow set + IX/IY) AND because a
    ;    banked Arkos2 / future AU5 tracker run from the body uses exx internally;
    ;    without it the interrupted main code's shadow set is silently corrupted.
    ;    Cheap here: the slow path runs only 50x/s.  The fast path saves only AF/BC.
    ei                                     ; <-- body runs INTERRUPTIBLE
    call _rage1_50hz_tick                  ; do_timer_tick + (periodic) do_periodic_isr_tasks
    di                                     ; <-- back to DI BEFORE touching the flag
    [restore shadow set, iy, ix, hl, de]
    xor a / ld (isr_busy),a                ; clear flag while DI
.exit:
    pop bc / pop af
    ei                                     ; (confirmed: EI/RET, not DI/RET — see 5.4)
    ret
```

### 5.3 EI/DI invariant (the part that must be exact)
- Test-and-set `isr_busy` while **DI** (before the `ei`).
- Clear `isr_busy` while **DI** (after the body, before the final `ei`).
If the clear ever runs with interrupts on, a nested VSYNC tick could slip the guard
and re-enter the body. `isr_busy` is a 1-bit reentrancy flag, **separate** from
`interrupt_nesting_level` (which only guards `memory_switch_bank`'s own atomicity).

### 5.4 Overrun behavior (interruptible slow path)
Every interrupt advances the counter and re-reads VSYNC, then exits **`ei`/`ret`**
(decision: keep the counter perfectly VSYNC-synced even through a long body; nesting
is bounded to one level because the fast path is a few µs and cannot recurse into the
body while `isr_busy`). If the body ever runs longer than a frame, the next VSYNC
interrupt finds `isr_busy` set and skips the body — RAGE1 simply sees a missed tick
(identical to a missed interrupt on ZX). No corruption, bounded stack.

### 5.5 Banked code from the ISR → lets us delete Fix A
Because the body is interruptible and `memory_switch_bank` is atomic (di/inc/dec/ei)
and reentrant (saves the previous bank), a tick may run mid-`dataset_activate`:
the decompress runs with interrupts **live**, a tick fires, the body optionally plays
banked music (`switch → play → switch back to the dataset bank`), and the decompress
resumes with its bank intact (BANKED-FUNCTIONS.md case b). This is what makes the
interim `dataset.c` DI fix unnecessary — removed as the final verified step.

### 5.6 The counter
`cpc_isr_div_counter` no longer drives the tick (VSYNC does). It is kept as a
frame-position tracker (`0` = just saw VSYNC; 1..5 = sub-frame interrupt index),
VSYNC-synced at all times, reserved for future sub-frame / raster use.

### 5.7 VSYNC-sample reliability (assumption, lightly verified)
VSYNC is sampled ~6–8 instructions into the ISR, so if an interrupt fires while VSYNC
is high we catch it. VSYNC width (~6–8 lines) ≪ the 52-line interrupt spacing, so at
most one interrupt per frame samples it high; for RAGE1's standard mode-1 screen the
GA reliably fires one ~2 lines into VSYNC, so exactly one does. Failure mode if ever
violated = a single missed tick that frame (self-correcting). Guard with a tick-rate
check, not blind trust (§6.4).

## 6. Test plan
1. `build-cpc-banked-test` + a cpc-flat target build & run; `all-test-builds` 23/23;
   **ZX byte-identical** (CPC-only changes).
2. `main.map`: clib `asm_interrupt_handler`/`im1_vectors`/`fast_vectors` off the IRQ
   path (ideally unlinked); `rage1_cpc_isr` < 0x4000.
3. cap32 (banked): green-probe after `init_datasets()` passes WITH then WITHOUT the
   interim DI fix → low ISR alone fixes the crash.
4. **Tick-rate check:** `current_time` advances at ~50 Hz (not 300/42/other) on both
   flat and banked — confirms VSYNC detection fires exactly once per frame.
5. Soak: repeated `dataset_activate` with interrupts live; no drift/crash. (Repeat
   with banked music once AU5 lands — the real reentrancy exercise.)
6. Independent critical reviewer.

## 7. Out of scope / future
- Dropping the firmware exx-set machinery entirely (loader→game handover).
- Sub-frame/raster use of `cpc_isr_div_counter` (planned).
- Separate CPC sprite screen-addressing garble (independent of interrupts).
- `codeset_call` banked-code-from-window (CPC codesets currently empty; the low ISR
  already covers ISR safety).

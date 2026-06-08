# Phase 8 — Engine performance optimization (first AI pass)

> **Status: APPROVED (2026-06-08). Plan only — NO code written yet.** User signed off
> the §3 decisions D1–D5 and resolved the §6 questions Q1–Q5 (recorded below). Phase 8
> is queued AFTER Phase 4 (cpc-banked) and Phases 5–7; PO1 starts when the phase begins.
>
> Cross-refs: hot-path map in this doc §2 is grounded in the engine survey of
> `engine/src/*.c` + `engine/banked_code/common/*.c`. Safety gate builds on
> `testing.md` (the `tests/00regression/` screenshot suite) and the Task 7
> parallel build matrix. Management entry: `management/00tasklist.md` **Phase 8**.

## 1. Goal

The **JSP** sprite engine has already been heavily hand- and AI-optimized for
both ZX and CPC, but **externally to RAGE1** (it is a vendored submodule). The
**RAGE1 engine itself** (`engine/src/*.c`, `engine/banked_code/common/*.c`,
`engine/lowmem/`) was hand-tuned in the past but has **never had an AI
optimization pass**. Phase 8 is that pass: improve **per-frame execution speed**
— and, where free, **code size** — of the platform-neutral engine and the ZX
(SP1) backend, on **both** ZX 48/128 and CPC, **without any behavioral
regression**.

This phase is fundamentally different from Phases 1–7: **optimization changes
the binary by definition.** The ZX byte-identity gate that protected every prior
refactor does **not** apply here and must be explicitly retired for Phase-8 work
(see §3 D1 / §5). The replacement gate is *behavioral* equivalence (the
screenshot regression suite) plus *measured* speedups.

## 2. What already exists (the leverage)

| Layer | State | Evidence |
|---|---|---|
| Per-frame hot paths | Well isolated in a single game loop | `engine/src/game_loop.c:run_main_game_loop()` (184-319) |
| Guard conditions | Expensive ops already gated (`num_frames>1`, `dx/dy!=0`, early `return` on no active bullets) | `engine/banked_code/common/enemy.c:48,60,65`; `bullet.c:34` |
| Some hot functions already use `static` locals | `hero_animate_and_move` (14), `btile_draw_frame` (8) | `banked_code/common/hero.c:112-120`; `src/btile.c:49` |
| local→static lesson harness | Prior experiment proving the trade-off is *per-function*, not universal | `tests/local_var_unoptimization/` |
| Behavioral regression suite | Pixel-perfect, deterministic frame counts, ZX48/128/CPC | `tests/00regression/` (15+ games) |
| Memory measurement | Per-object / per-section size reports | `make mem`, `tools/r1size.sh`, `tools/mem-summary-*.sh`, `tools/memmap.pl` |
| Compiler optimization already on | `-SO3 --opt-code-size --max-allocs-per-node200000`, sdcc_iy | `Makefile.common:202` |

**The gap:** there is **no speed measurement** today — every tool measures size,
none measures cycles or frame time. You cannot optimize what you cannot measure,
so the phase's hard prerequisite (PO1) is a cycle/frame-time harness.

**Hot paths to target (per-frame, ranked by survey):**
1. `collision_check()` — `src/collision.c:25-31`; called `BULLET_MAX_BULLETS × enemies` per frame (nested loop `collision.c:62-91`). Pure 16-bit comparisons; poor sdcc codegen on tight predicates.
2. `animation_sequence_tick()` — `banked_code/common/animation.c:24-57`; per active entity per frame.
3. `GET_TILE_TYPE_AT()` / `PIXEL_TO_CELL_COORD()` — expands to two `/8` + array lookup; ~40+ invocations/frame in enemy bounce + bullet/hero obstacle checks.
4. `enemy_animate_and_move()` loop invariants — `banked_code/common/enemy.c:66-120` (repeated `g->width/height` + `pos+width` recomputation; bounce checks).
5. `btile_animate_all()` — `src/btile.c:107,111` double `dataset_get_banked_btile_ptr()` call; repeated `current_screen_ptr->…` derefs.
6. `bullet_animate_and_move_all()` — `banked_code/common/bullet.c:50` repeated `bi->movement.delay` load in inner loop.

## 3. Decisions (✅ ALL ACCEPTED by user, 2026-06-08 — D1–D5)

**D1 — Retire the byte-identity gate for Phase 8; replace with behavioral +
measured gates.** Every Phase-8 change must (a) keep `tests/00regression/` green
on **all** affected platforms (pixel-identical gameplay), and (b) show a
**measured, non-noise** improvement (or at minimum no regression) in the PO1
metric. Changes that don't measurably help are reverted — no churn for noise.

**D2 — Measurement first, optimization second.** PO1 (a repeatable cycles/frame
harness + committed per-game baselines) lands before any optimization. The rest
of the phase is "propose → measure delta → keep/revert", never blind.

**D3 — Scope = platform-neutral engine + ZX (SP1) backend. Leave JSP alone.**
JSP is already optimized upstream; Phase 8 does not touch `external/jsp`. CPC
gains come for free from the platform-neutral hot paths. `gfx_jsp.c` glue is in
scope only if PO1 shows it on the CPC hot path.

**D4 — Stage by risk, low→high.** Safe C micro-opts (PO2) and measured
local→static (PO3) and flag/pragma tuning (PO4) first; targeted C→asm kernels
(PO5) — the highest risk/reward — last and most heavily gated.

**D5 — Each asm kernel keeps the existing C as a reference fallback** (behind the
same call signature, e.g. a `#ifdef RAGE1_OPT_ASM_COLLISION` switch or a
build-feature), so the C version stays buildable/auditable and both backends keep
compiling. Independent review is mandatory for every asm rewrite (project rule).

## 4. Staged sub-phases (each gated: `tests/00regression/` green on all affected
platforms + a measured PO1 delta + independent review for non-trivial/asm work)

- **PO1 — Speed measurement harness + baselines.** Add a repeatable
  cycles-per-frame (or frame-time) metric over a deterministic scenario, reusing
  the regression harness's fixed-frame runs. **Primary target = ZX via JNEXT**
  (Q1: JNEXT has the better profiling support, and ZX/CPC share the same Z80 so
  platform-neutral-code gains validate on both); an emulator T-state/cycle read
  brackets N frames, exposed as `make perf` / `tools/perf-*.sh`. **CPC/`cap32` used
  occasionally to double-check that the wins carry over.**
  Commit per-game baselines for the hot games (**blobs** = many enemies,
  **default** = full features, **get_weapon** = bullets, **mapgen** = big map).
  *Exit:* a one-command, low-variance number per game/platform.

- **PO2 — Loop-invariant & redundant-deref micro-opts (C, low risk).** Apply the
  survey's §2 items 4/5/6: hoist `g->width/height` and `pos+width`; cache the
  double `dataset_get_banked_btile_ptr()`; hoist `bi->movement.delay`; cache
  repeated `current_screen_ptr->…` derefs. Each measured individually.

- **PO3 — Measured local→static conversion.** On the hottest leaf functions,
  convert stack/IX-indexed locals to file-scope statics **only where PO1 shows a
  win** (per the `tests/local_var_unoptimization/` lesson). Reject where neutral
  or size-negative.

- **PO4 — Compiler flag / pragma exploration.** Per-TU / per-function `#pragma`
  and `-SO3` vs `--opt-code-size` trade-offs on the hot files; `--max-allocs`
  tuning. Cheap, reversible; keep only measured wins, and never regress total
  size beyond an agreed budget (§6 Q2).

- **PO5 — Targeted C→asm kernels (high risk/reward).** Hand-written Z80 for the
  hottest tight kernels PO1 confirms: `collision_check`, `animation_sequence_tick`,
  a fast `tile_type_at` / `pixel_to_cell` helper. Each behind the same C API with
  the C reference retained (D5), each independently reviewed, each measured.

- **PO6 — Optimize existing hot-path hand-asm (likely small).** The survey found
  almost no engine asm in the hot path (asm is mostly audio + CPC HW-I/O). Scope
  this only if PO1 surfaces a hot asm routine.

- **PO7 — Docs + wrap-up.** Record the cycle/size deltas achieved per game; keep
  or retire the PO1 harness as a permanent `make perf`; update `testing.md` and a
  short "optimization log". No removals of any user-visible surface (§5.6).

## 5. Invariants & constraints

- **Behavioral gate, not byte gate.** `tests/00regression/` green on every
  affected platform is the correctness contract. Output WILL differ from
  pre-Phase-8 binaries — that is expected and intended.
- **Both backends keep building and passing:** ZX SP1 (48 + 128) and CPC JSP.
  Platform-neutral optimizations must help or at least not hurt either.
- **Measure-driven only:** no change is committed without a PO1 before/after
  number; noise-level or negative changes are reverted.
- **Memory budget:** speed-first, but total per-game size must not regress beyond
  an agreed small budget (§6 Q2) — RAGE1 is memory-constrained.
- **Multiplatform correctness:** respect the wider abstractions (16-bit coords on
  CPC, FFP types, the gfx/attribute HAL) — optimizations must not re-hardcode ZX
  assumptions into platform-neutral code.
- **Reviewability:** every asm kernel documents the C reference it replaces and is
  reviewed by an independent agent (never its author), per project rules.
- **No removals / permanent aliases** policy (README §5.6) still holds.

## 6. Resolved questions (✅ user, 2026-06-08)

- **Q1 — Measurement mechanism. RESOLVED: profile on ZX (JNEXT) as the PRIMARY
  target; spot-check CPC (`cap32`) occasionally.** Rationale (user): ZX and CPC run
  the same Z80, so optimizations to platform-neutral code are valid for both, and
  **JNEXT has much better profiling support** — so the main optimization work runs in
  ZX mode (emulator cycle/T-state read over the deterministic fixed-frame regression
  runs), with periodic cap32/CPC builds to confirm the enhancements carry over.
- **Q2 — Target & size budget. RESOLVED: speed-first, hard cap "no total size
  regression"** (a per-TU may grow if the total holds).
- **Q3 — Asm scope ceiling. RESOLVED: NO fixed limit.** Keep moving C→asm for as long
  as we find strong optimization candidates (each still gated: regression green +
  measured delta + C fallback retained per D5 + independent review). Expectation
  (user): we likely won't find many, so in practice this lands near ~2–3 kernels — but
  the cap is "strong candidates exhausted," not an arbitrary number.
- **Q4 — Keep-threshold. RESOLVED: set the exact threshold at PO1** once baseline
  variance is known (e.g. ≥2 % on a hot game, or ≥X T-states/frame).
- **Q5 — Per-game vs whole-suite metric. RESOLVED: report all hot games; gate on
  "no regression anywhere + a win on the targeted game".**

## 7. Sequencing & risk

- **PO1 is the gating prerequisite** — the entire phase is guesswork without it;
  it is also the only sub-phase with an unknown (does JNEXT give a stable enough
  cycle/T-state read over the headless harness?). De-risk it first with a spike.
- **Expected value distribution:** PO2 (safe C hoists) and PO5 (asm kernels) carry
  most of the win; PO3/PO4 are smaller, opportunistic. PO6 is likely near-empty.
- **Highest risk:** PO5 asm — behavioral bugs that pass a coarse screenshot but
  break an untested edge case. Mitigations: C fallback retained (D5), independent
  review, and exercising the specific hot game whose path the kernel serves
  (collision → blobs/get_weapon; animation → any animated game).
- **Lowest risk:** PO4 flags/pragmas (fully reversible) and PO2 (local, obvious).
- **Order:** PO1 → PO2 → PO3 → PO4 → PO5 → PO6 → PO7, each gated as in §4.

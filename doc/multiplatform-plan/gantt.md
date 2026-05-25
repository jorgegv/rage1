# RAGE1 cross-platform plan — Gantt / dependency charts

Graphical companion to [README §4](README.md). The 54 subsystem
phases are grouped into 6 chronological **Greek phases** (α…ζ).
Durations on every chart below are uniform placeholders — the
load-bearing content is **dependency topology** and **phase
ordering**, not calendar time.

| Greek phase | Theme | Count | CPC code? | ZX byte-identical? |
|---|---|---|---|---|
| **α** | Foundation (preparation) | 4 | no | n/a (no engine changes) |
| **β** | HAL & asset scaffolding (ZX-only, additive) | 10 | no | yes |
| **γ** | HAL generalisation | 10 | no | yes |
| **δ** | CPC bring-up (flat first, then banked) | 19 | yes | yes (ZX track preserved) |
| **ε** | Hardening + CI matrix expansion | 7 | yes | yes |
| **ζ** | Cleanup | 7 | yes | yes |

---

## 1. Master Gantt — all subsystems, all 54 phases

Swim lanes are subsystems. Horizontal position is determined by
`after` dependencies — Greek phases appear as visible vertical
bands. Tasks marked `crit` (red) are gating: their failure blocks
all CPC work that follows.

```mermaid
gantt
  title RAGE1 cross-platform — master phase dependency chart
  dateFormat YYYY-MM-DD
  axisFormat W%V

  section gfx
  G1 audit              :g1, 2026-01-05, 7d
  G2 GFX_BACKEND        :g2, after g1, 7d
  G3 attr abstraction   :g3, after g2, 7d
  G4 pixel coords       :g4, after g3, 7d
  G5 sprite geometry    :g5, after g4, 7d
  G6 tile-ID            :g6, after g5, 7d
  G7 cpctel stub        :g7, after g6 r1, 7d
  G8 cpctel real        :g8, after r4 g7, 7d
  G9 CPC 3+ games       :g9, after g8, 7d

  section assets
  A1 PLATFORM ZX        :a1, 2026-01-05, 7d
  A2 overlay copy       :a2, after a1, 7d
  A3 dispatch seam      :a3, after a2, 7d
  A4 overlay E2E ZX     :a4, after a3, 7d
  A5 CPC img2tileset    :a5, after a4 r3, 7d
  A6 platform patches   :a6, after a5, 7d
  A7 cleanups/docs      :a7, after a6, 7d

  section toolchain
  T0 z88dk+cpc spike    :crit, t0, 2026-01-05, 7d
  T1 PLATFORM Makefile  :t1, after t0 a1, 7d
  T2 cpc-flat Makefile  :t2, after r2 t1, 7d
  T3 cpc-banked Mkfile  :t3, after b7 t2, 7d
  T4 matrix completion  :t4, after t3, 7d

  section cpc-renderer
  R1 cpctelera submod   :r1, after t0, 7d
  R2 hello-world PoC    :crit, r2, after r1, 7d
  R3 img2tileset wire   :r3, after r2, 7d
  R4 gfx_cpctel real    :r4, after r3 g7, 7d
  R5 hardening          :r5, after r4, 7d

  section audio
  AU1 audit             :au1, 2026-01-05, 7d
  AU2 HAL aliases       :au2, after au1, 7d
  AU3 audio_* names     :au3, after au2, 7d
  AU4 CPC skeleton      :au4, after au3 r2, 7d
  AU5 real CPC audio    :au5, after au4 r4, 7d
  AU6 SOUND_MAP         :au6, after au5, 7d
  AU7 cleanup/docs      :au7, after au6, 7d

  section input
  IN1 audit             :in1, 2026-01-05, 7d
  IN2 HAL skeleton      :in2, after in1, 7d
  IN3 engine HAL mig    :in3, after in2, 7d
  IN4 kbd.c consol.     :in4, after in3, 7d
  IN5 CPC skeleton      :in5, after in4 r2, 7d
  IN6 real CPC input    :in6, after in5 r4, 7d
  IN7 CONTROLLER opt    :in7, after in6, 7d
  IN8 hardening MSX     :in8, after in7, 7d

  section banking
  B1 config externalize :b1, 2026-01-05, 7d
  B2 per-plat ISR YAML  :b2, after b1, 7d
  B3 lowmem threshold   :b3, after b2, 7d
  B4 CPC banking seam   :b4, after b3 t2, 7d
  B5 cpc-flat banking   :b5, after b4, 7d
  B6 cpc-banked infra   :b6, after b5, 7d
  B7 cpc-banked tools   :b7, after b6, 7d
  B8 SUBs on CPC        :b8, after b7, 7d
  B9 cleanup            :b9, after b8, 7d

  section testing
  TS1 ZX baselines      :crit, ts1, 2026-01-05, 7d
  TS2 Caprice32+Docker  :ts2, after t2, 7d
  TS3 first CPC base    :ts3, after r4 g8 ts2, 7d
  TS4 TAP-byte mode     :ts4, after ts3, 7d
  TS5 CI matrix         :ts5, after ts4, 7d
  TS6 retire stubs      :ts6, after ts5 g9, 7d
```

---

## 2. Cross-subsystem dependency DAG (the project "spine")

The Mermaid Gantt above shows **when** each phase runs but does
not draw explicit arrows. The flowchart below shows the
**critical cross-subsystem dependencies** — the spine that
serialises CPC bring-up. Arrows go from prerequisite to consumer.

Greek phases colour the boxes; the gating tasks (`T0`, `R2`,
`TS1`) sit on the critical path.

```mermaid
flowchart LR
  classDef alpha fill:#e8f0ff,stroke:#3a5fcd,color:#000
  classDef beta  fill:#e6ffe6,stroke:#2e8b2e,color:#000
  classDef gamma fill:#fffce6,stroke:#b8a300,color:#000
  classDef delta fill:#ffe6e6,stroke:#b22222,color:#000
  classDef eps   fill:#f3e6ff,stroke:#7a3fbf,color:#000
  classDef zeta  fill:#eaeaea,stroke:#666,color:#000
  classDef gate  fill:#ff6b6b,stroke:#900,color:#fff,stroke-width:3px

  %% Alpha
  TS1[TS1 ZX baselines]:::gate
  T0[T0 toolchain spike]:::gate
  B1[B1 banking config]:::alpha
  G1[G1 gfx audit]:::alpha

  %% Beta
  G2[G2 GFX_BACKEND]:::beta
  A1[A1 PLATFORM ZX]:::beta
  A2[A2 overlay copy]:::beta
  T1[T1 PLATFORM Makefile]:::beta
  B2[B2 ISR YAML]:::beta
  R1[R1 cpctelera submod]:::beta

  %% Gamma
  G6[G6 tile-ID]:::gamma
  A4[A4 overlay E2E]:::gamma
  B3[B3 lowmem]:::gamma

  %% Delta - the gating PoC
  R2[R2 hello-world PoC]:::gate
  R3[R3 img2tileset]:::delta
  R4[R4 gfx_cpctel real]:::delta
  T2[T2 cpc-flat Makefile]:::delta
  G7[G7 cpctel stub]:::delta
  G8[G8 cpctel real]:::delta
  A5[A5 CPC assets]:::delta
  B7[B7 cpc-banked tools]:::delta
  T3[T3 cpc-banked Makefile]:::delta
  TS2[TS2 Caprice32+Docker]:::delta
  TS3[TS3 first CPC baseline]:::delta

  %% Epsilon
  G9[G9 CPC 3+ games]:::eps
  TS5[TS5 CI matrix]:::eps

  %% Zeta
  TS6[TS6 retire stubs]:::zeta

  %% Dependencies
  G1 --> G2 --> G6
  A1 --> A2 --> A4
  B1 --> B2 --> B3
  T0 --> T1
  T0 --> R1
  A1 --> T1
  R1 --> R2
  R2 --> R3
  R2 --> T2
  T1 --> T2
  R3 --> R4
  G6 --> G7
  R1 --> G7
  G7 --> R4
  R4 --> G8
  R4 --> A5
  A4 --> A5
  B3 --> B7
  T2 --> B7
  B7 --> T3
  T2 --> TS2
  TS1 --> TS3
  R4 --> TS3
  G8 --> TS3
  TS2 --> TS3
  G8 --> G9
  TS3 --> TS5
  TS5 --> TS6
  G9 --> TS6
```

The two **deep-red gating boxes** are pre-CPC: nothing past them
proceeds unless they succeed.

- **TS1** — `tests/00regression/` must cover ≥ 80 % of test games
  *before* anyone refactors the engine. Without TS1's safety net
  the "ZX byte-identical" invariant every later phase asserts is
  unverifiable.
- **T0** — z88dk `+cpc` + sdcc_iy + a trivial cpctelera build,
  outside RAGE1. If T0 fails, the entire toolchain story is
  unsound; the plan returns to library survey
  ([cpc-renderer.md](cpc-renderer.md)).
- **R2** — cpctelera-SDCC-3.6.8-vs-z88dk-SDCC-4.3 hello-world.
  Most CPC work is gated on R2 succeeding; fallback is the
  cpc-renderer.md alternatives survey (CPCRSlib).

---

## 3. Per-Greek-phase Gantts

### 3.1 Phase α — Foundation

All four α phases are independent and run in parallel. Their
purpose is to prepare the ground without touching the engine
beyond config files.

```mermaid
gantt
  title Phase α — Foundation (no CPC code; preparation)
  dateFormat YYYY-MM-DD
  axisFormat W%V
  section testing
  TS1 ZX regression baselines (>=80%)   :crit, ts1, 2026-01-05, 7d
  section toolchain
  T0 z88dk+cpc + cpctelera spike        :crit, t0, 2026-01-05, 7d
  section banking
  B1 banking-config externalisation     :b1, 2026-01-05, 7d
  section gfx
  G1 gfx_* audit completion             :g1, 2026-01-05, 7d
```

**Phase-α exit signals:** ZX regression suite covers enough games
to detect future byte-level drift; `+cpc` toolchain proven outside
RAGE1; `etc/rage1-config.yml` carries everything; `gfx_*` audit
baseline frozen.

### 3.2 Phase β — HAL & asset scaffolding (ZX-only, additive)

β introduces new vocabulary (PLATFORM, GFX_BACKEND, HAL skeletons,
sibling-tree overlay machinery) without changing engine
semantics. Every existing ZX game must still build byte-identical.

```mermaid
gantt
  title Phase β — HAL & asset scaffolding (ZX-only, additive)
  dateFormat YYYY-MM-DD
  axisFormat W%V

  section gfx
  G2 GFX_BACKEND rename       :g2, after g1, 7d

  section assets
  A1 PLATFORM directive       :a1, 2026-01-05, 7d
  A2 sibling-tree overlay     :a2, after a1, 7d

  section toolchain
  T1 PLATFORM in Makefile     :t1, after t0 a1, 7d

  section cpc-renderer
  R1 cpctelera submodule      :r1, after t0, 7d

  section audio
  AU1 audio audit             :au1, 2026-01-05, 7d
  AU2 HAL aliases             :au2, after au1, 7d

  section input
  IN1 input audit             :in1, 2026-01-05, 7d
  IN2 HAL skeleton            :in2, after in1, 7d

  section banking
  B2 per-platform ISR YAML    :b2, after b1, 7d
```

**Phase-β exit signals:** every ZX game still byte-identical;
`PLATFORM` recognised; sibling-overlay copy mechanism in place
(empty overlay trees still allowed); `external/cpctelera/` vendored
but not compiled; audio/input HAL aliases compile but route to
existing implementations.

### 3.3 Phase γ — HAL generalisation (ZX byte-identical)

γ removes ZX-derived assumptions from the engine's HAL surface
without introducing CPC code. The engine becomes structurally
ready to plug in a CPC backend, but no CPC backend yet exists.

```mermaid
gantt
  title Phase γ — HAL generalisation (ZX byte-identical)
  dateFormat YYYY-MM-DD
  axisFormat W%V

  section gfx
  G3 attr abstraction         :g3, after g2, 7d
  G4 pixel coords widen       :g4, after g3, 7d
  G5 sprite geometry          :g5, after g4, 7d
  G6 tile-ID                  :g6, after g5, 7d

  section assets
  A3 datagen dispatch seam    :a3, after a2, 7d
  A4 overlay E2E proof on ZX  :a4, after a3, 7d

  section banking
  B3 lowmem threshold params  :b3, after b2, 7d

  section input
  IN3 engine to HAL migration :in3, after in2, 7d
  IN4 kbd.c consolidation     :in4, after in3, 7d

  section audio
  AU3 audio_* names live      :au3, after au2, 7d
```

**Phase-γ exit signals:** `gfx_*`, `audio_*`, `input_*` HALs no
longer carry ZX-only types; datagen.pl has a per-platform
dispatcher branch (currently only ZX populated); ZX byte-identical
invariant survives across the whole sweep.

### 3.4 Phase δ — CPC bring-up (cpc-flat first, then cpc-banked)

δ is the biggest phase (19 sub-phases). CPC code lands here. The
phase **internally serialises** — the first half brings up
cpc-flat (no banking, CPC464 binary that runs on CPC664 too), the
second half adds cpc-banked (CPC6128).

```mermaid
gantt
  title Phase δ — CPC bring-up (cpc-flat first)
  dateFormat YYYY-MM-DD
  axisFormat W%V

  section cpc-renderer
  R2 hello-world PoC          :crit, r2, after r1, 7d
  R3 img2tileset wiring       :r3, after r2, 7d
  R4 real gfx_cpctel + game   :r4, after r3 g7, 7d

  section toolchain
  T2 cpc-flat Makefile        :t2, after r2 t1, 7d

  section banking
  B4 CPC banking config seam  :b4, after b3 t2, 7d
  B5 cpc-flat (no banking)    :b5, after b4, 7d

  section gfx
  G7 gfx_cpctel.c stub        :g7, after g6 r1, 7d
  G8 real CPC wiring          :g8, after r4 g7, 7d

  section input
  IN5 CPC skeleton            :in5, after in4 r2, 7d
  IN6 real CPC input          :in6, after in5 r4, 7d

  section audio
  AU4 CPC skeleton + AT2 reloc:au4, after au3 r2, 7d
  AU5 real CPC audio          :au5, after au4 r4, 7d

  section assets
  A5 CPC img2tileset in dgen  :a5, after a4 r3, 7d

  section testing
  TS2 Caprice32 + Docker      :ts2, after t2, 7d
  TS3 first CPC regression    :ts3, after r4 g8 ts2, 7d
```

```mermaid
gantt
  title Phase δ — CPC bring-up (cpc-banked, second wave)
  dateFormat YYYY-MM-DD
  axisFormat W%V

  section banking
  B6 cpc-banked banking infra :b6, after b5, 7d
  B7 cpc-banked tooling       :b7, after b6, 7d

  section toolchain
  T3 cpc-banked Makefile      :t3, after b7 t2, 7d
```

**Phase-δ exit signals:** `make build-cpc464` + `make build-cpc6128`
both produce loadable images; `games/minimal_cpc/` runs on
Caprice32 and has its first regression baseline; ZX track
unchanged; cpc-flat AND cpc-banked builds both work.

### 3.5 Phase ε — Hardening + CI matrix expansion

ε broadens the CPC track from the first stub game to three+ real
games, adds the SOUND_MAP cross-platform layer, lights up SUBs on
CPC, and expands CI to run the full matrix.

```mermaid
gantt
  title Phase ε — Hardening + CI matrix expansion
  dateFormat YYYY-MM-DD
  axisFormat W%V

  section cpc-renderer
  R5 cpctelera hardening      :r5, after r4, 7d

  section gfx
  G9 CPC across 3+ games      :g9, after g8, 7d

  section input
  IN7 optional CONTROLLER     :in7, after in6, 7d

  section audio
  AU6 SOUND_MAP directive     :au6, after au5, 7d

  section banking
  B8 SUBs on CPC              :b8, after b7, 7d

  section testing
  TS4 TAP-byte invariant      :ts4, after ts3, 7d
  TS5 CI matrix expansion     :ts5, after ts4, 7d
```

**Phase-ε exit signals:** `games/blobs`, `games/crumbs`,
`games/mapgen` running on CPC; CI matrix covers
`zx48 × zx128 × cpc464 × cpc6128`; TAP-byte invariant wired into
CI for ZX deterministic builds.

### 3.6 Phase ζ — Cleanup

ζ is documentation, polishing, and stub retirement. Per
[README §5.6](README.md), **no user-visible surfaces are removed**
— old `.gdata` keywords, Makefile aliases, and forwarding stubs
stay accepted indefinitely. ζ is mostly docs and the merge of
`games/minimal_cpc` back into `games/minimal`.

```mermaid
gantt
  title Phase ζ — Cleanup (docs + stub retirement, no removals)
  dateFormat YYYY-MM-DD
  axisFormat W%V

  section assets
  A6 platform-scoped patches  :a6, after a5, 7d
  A7 cleanups + docs          :a7, after a6, 7d

  section toolchain
  T4 matrix completion docs   :t4, after t3, 7d

  section audio
  AU7 cleanup + docs          :au7, after au6, 7d

  section input
  IN8 hardening + MSX sketch  :in8, after in7, 7d

  section banking
  B9 cleanup + docs           :b9, after b8, 7d

  section testing
  TS6 retire CPC-only stubs   :ts6, after ts5 g9, 7d
```

**Phase-ζ exit signals:** `games/minimal_cpc` merged back into
`games/minimal` (shared game, two platforms); all docs reflect the
post-multi-platform state; CHANGELOG.md records every rename;
plan-execution loop closes.

---

## 4. Critical path (longest chain)

Following the spine of the project from the foundation through to
plan completion:

`TS1` → `T0` → `R1` → **`R2`** (gating) → `R3` → `G7` (depends on `G6`, which depends on `G5` → `G4` → `G3` → `G2` → `G1`) → `R4` → `G8` → `TS3` → `G9` → `TS6`

The **gfx subsystem is the critical-path subsystem**: G1 → G2 → G3
→ G4 → G5 → G6 are strictly serial (each layer of the HAL audit
ripples into the next), and G7 + G8 cannot start until R-track
deliverables also land. If the project is behind, gfx is almost
certainly where time is being spent.

**The R2 gate is the single biggest schedule risk.** Until R2's
hello-world PoC compiles, links, and runs on Caprice32, the
critical path is blocked. The fallback (CPCRSlib) costs roughly an
extra R-track restart but does not invalidate the rest of the
plan; the HAL design is library-agnostic.

---

## 5. How to read these charts

- **Mermaid Gantts** position tasks horizontally by `after`
  dependencies; the rendered chart shows *when* things can run in
  parallel.
- **The flowchart DAG** in §2 shows the explicit cross-subsystem
  arrows that the Gantt's positional encoding only implies.
- **Durations are placeholders** — every box is "7 days" so the
  topology is visible without claiming false precision. Real
  durations come from execution-time tracking, not this doc.
- **Greek phases are vertical bands** in the master Gantt
  (§1) — they're not separately drawn, but every task's horizontal
  position falls inside one band by virtue of its predecessors.
- For per-task detail (sub-task IDs like `G2-3`, `R4-2`, etc.) see
  the per-subsystem doc, not this one.

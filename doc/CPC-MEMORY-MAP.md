# RAGE1 Amstrad CPC memory maps

Reference for the two CPC targets RAGE1 builds:

- **cpc-flat** — CPC 464/664 (and 6128 without banking): one flat 64 KB RAM, no
  bank switching.
- **cpc-banked** — CPC 6128 "Shape A": the upper 64 KB expansion RAM is bank
  switched into the `0x4000` window.

Both targets render with the **JSP** sprite library (not SP1) and run a
RAGE1-owned IM1 interrupt at `0x0038` (no firmware ISR). All addresses below are
sourced from the build: cpc-banked from `etc/rage1-config.yml`
(`memory_map.cpc_banked`, injected via `yq`); cpc-flat from `zpragma-cpc-flat.inc`
+ `external/jsp/lib/jsp_data.c` (the `JSP_TARGET_CPC` table block).

Region names used throughout the CPC bring-up project:

| Name         | Meaning                                                                   |
|--------------|---------------------------------------------------------------------------|
| **JSPBUF**   | The five JSP data tables (BAT, FTT, DTT, BTT, ROTTBL) — one block.        |
| **DSBUF**    | Dataset decompress buffer — datasets dzx0-decompress here in place.       |
| swap window  | The `0x4000-0x7FFF` 16 KB region the Gate Array bank-switches.            |
| RAM0..RAM7   | Physical 16 KB CPC RAM banks (RAM0-3 = base 64 KB, RAM4-7 = expansion).   |
| page A/B/C/D | The four Z80 16 KB slots: A `0x0000`, B `0x4000`, C `0x8000`, D `0xC000`. |

---

## cpc-flat (CPC 464/664) — flat 64 KB, no banking

Both ROMs off; the program owns all 64 KB. JSPBUF sits just below the screen, the
stack lives just below JSPBUF (`REGISTER_SP = 0x9800` for JSP builds — the JSP
build flag wins over the zpragma's `0xBF00`).

```
0x0000 ┌────────────────────────────────────────────────┐
       │ Z80 RST vectors; 0x0038 = IM1 -> rage1_cpc_isr │
0x0040 ├────────────────────────────────────────────────┤
       │ firmware low RAM / z88dk reserved (free)       │
0x1200 ├────────────────────────────────────────────────┤  CRT_ORG_CODE
       │ engine: code + rodata + data + bss             │
       │  ... program grows up ...                      │
       │  ... free ...                                  │
       │  ... stack grows DOWN from 0x9800 ...          │
0x9800 ├────────────────────────────────────────────────┤  REGISTER_SP (JSP build)
       │ JSPBUF - JSP data tables (0x9800-0xBFFF):      │
       │   BAT    0x9800                                │
       │   FTT    0xA000                                │
       │   DTT    0xA100                                │
       │   BTT    0xA200                                │
       │   ROTTBL 0xB200-0xBFFF                         │
0xC000 ├────────────────────────────────────────────────┤
       │ SCREEN RAM (CRTC)                              │
0xFFFF └────────────────────────────────────────────────┘
```

| Range           | Contents                                                  |
|-----------------|-----------------------------------------------------------|
| `0x0000-0x003F` | Z80 restart/IM1 vectors. `0x0038` = `jp rage1_cpc_isr`.   |
| `0x0040-0x11FF` | Firmware low RAM / z88dk's conservative gap (unused).     |
| `0x1200-…`      | Engine code, rodata, data, bss (contiguous from CRT_ORG). |
| `…-0x97FF`      | Free; the stack grows down into here from `0x9800`.       |
| `0x9800-0xBFFF` | **JSPBUF** (5 tables, ~10 KB).                            |
| `0xC000-0xFFFF` | Screen RAM.                                               |

(A non-JSP cpc-flat program — e.g. the `cpc-hello` smoke test — has no JSPBUF and
keeps `REGISTER_SP = 0xBF00`.)

---

## cpc-banked (CPC 6128) — Shape A, `0x4000` swap window

The screen is fixed at `0xC000`, so the bank-switch window is **page B**
(`0x4000-0x7FFF`). Pages A and C are always mapped; only page B swaps. Datasets,
codesets and engine banked-code live in expansion banks RAM4-7 and are paged into
page B under Gate-Array Config 4-7; the JSP renderer reads them out (datasets are
decompressed to DSBUF in page C). See `doc/multiplatform-plan/management/
cpc-banked-bringup.md` (DC3/DC7) for the rationale.

```
        page A (RAM0, always mapped)
0x0000 ┌────────────────────────────────────────────────┐
       │ Z80 RST vectors; 0x0038 = IM1 -> rage1_cpc_isr │
0x0040 ├────────────────────────────────────────────────┤
       │ z88dk reserved gap (free)                      │
0x0200 ├────────────────────────────────────────────────┤  CRT_ORG_CODE
       │ engine code (+ rodata + data) - grows up,      │
       │ spilling across 0x4000 into page B             │
0x4000 ╞════════════════════════════════════════════════╡  page B (RAM1) = swap window
       │ Config 0 (home): engine code/rodata/data tail  │
       │ ends ~0x52A4 ; then free up to JSPBUF          │
0x5800 ├────────────────────────────────────────────────┤
       │ JSPBUF - JSP data tables (0x5800-0x7FFF):      │
       │   BAT    0x5800                                │
       │   FTT    0x6000                                │
       │   DTT    0x6100                                │
       │   BTT    0x6200                                │
       │   ROTTBL 0x7200-0x7FFF                         │
       │ - - - - - - - - - - - - - - - - - - - - - - -  │
       │ Config 4-7: RAM4/5/6/7 paged over the WHOLE    │
       │   0x4000-0x7FFF window (RAM1 hidden):          │
       │   RAM4 = engine banked code (reserved)         │
       │   RAM5/6/7 = datasets + codesets (at 0x4000)   │
0x8000 ╞════════════════════════════════════════════════╡  page C (RAM2, always mapped)
       │ STACK (grows DOWN from SP) 0x8000-0x807F       │
0x8080 ├────────────────────────────────────────────────┤  REGISTER_SP / page_c_data_base
       │ engine BSS (grows UP) 0x8080-~0x893F           │
       │ - - - - free - - - -                           │
0x9800 ├────────────────────────────────────────────────┤  banked_dataset_base
       │ DSBUF - dataset decompress buffer (10 KB),     │
       │ 0x9800-0xBFFF.  RUNTIME-ONLY, so it overlaps   │
       │ the firmware/AMSDOS reserved 0xA700-0xBFFF      │
       │ (HIMEM &A6FB) harmlessly (firmware is seized).  │
0xC000 ╞════════════════════════════════════════════════╡  page D (RAM3)
       │ SCREEN RAM (CRTC)                              │
0xFFFF └────────────────────────────────────────────────┘
```

| Range            | Contents                                                           |
|------------------|--------------------------------------------------------------------|
| `0x0000-0x003F`  | Z80 restart/IM1 vectors. `0x0038` = `jp rage1_cpc_isr`.            |
| `0x0040-0x01FF`  | z88dk reserved gap (reclaimed; CRT_ORG dropped to `0x0200`).       |
| `0x0200-0x3FFF`  | Engine code (page A part).                                         |
| `0x4000-~0x52A4` | Engine code/rodata/data tail (page-B part, Config 0 home).         |
| `~0x52A4-0x57FF` | Free.                                                              |
| `0x5800-0x7FFF`  | **JSPBUF** (page-B home, Config 0). Shadowed when a bank is paged. |
| `0x4000-0x7FFF`  | (Config 4-7) **swap window** — expansion bank RAM4-7.              |
| `0x8000-0x807F`  | Stack (grows down from `REGISTER_SP = 0x8080`).                    |
| `0x8080-~0x893F` | Engine BSS (relocated to page C; grows up). = `page_c_data_base`.  |
| `~0x893F-0x97FF` | Free.                                                             |
| `0x9800-0xBFFF`  | **DSBUF** — dataset decompress buffer (10 KB). `banked_dataset_base`. Runtime-only; overlaps the firmware/AMSDOS reserved `0xA700-0xBFFF`. |
| `0xC000-0xFFFF`  | Screen RAM (page D, RAM3). No code/data.                           |

### Key constraints

- **`CRT_ORG_CODE = 0x0200`** — dropped from z88dk's default `0x1200` to reclaim
  ~4 KB of page-A budget so that engine code/rodata/data ends below the JSPBUF at
  `0x5800`.
- **JSPBUF must be in page B (home RAM1), never in an expansion bank** — it is
  co-located with the JSP render code (also page-B home). If it were in RAM4-7 it
  would be paged out whenever a bank maps into the window. (cpc-flat puts it in
  page C because nothing else competes there; cpc-banked can't — page C holds
  DSBUF + bss + stack.)
- **Only BSS is relocated to page C** (`page_c_data_base`). rodata/data stay
  contiguous with code in page B in the single RUN"-loaded image — org-jumping
  initialised data makes z88dk emit a separate binary that the single load would
  not pick up. (Moving DATA into page C alongside BSS is a planned step.)
- **Page C is laid out persistent-LOW / DSBUF-HIGH**: stack at the bottom
  (`0x8000-0x807F`, `REGISTER_SP = 0x8080`), engine BSS just above it from
  `page_c_data_base`, then DSBUF fills the rest up to the screen
  (`banked_dataset_base = 0x9800 .. 0xBFFF`). DSBUF is the only thing that may sit
  above the firmware/AMSDOS reserved `0xA700-0xBFFF` (HIMEM `&A6FB`), because it is
  written only at runtime after the firmware is seized; the persistent stack+BSS
  must stay below it. `page_c_data_base` / `banked_dataset_base` are tunable per game.
- **`loadbanks` uses a 2 KB firmware CAS buffer at `0x8000-0x87FF`** at boot (z88dk
  `target/cpc/classic/loader.asm`). The low stack shares that region, but only
  AFTER `loadbanks` returns and SP is set, so there is no boot-time conflict.

### Banks (expansion RAM, paged into page B under GA Config 4-7)

| Bank | GA Config | Holds                                                   |
|------|-----------|---------------------------------------------------------|
| RAM4 | 0xC4      | Engine banked code (reserved; empty in the smoke game). |
| RAM5 | 0xC5      | Datasets / codesets.                                    |
| RAM6 | 0xC6      | Datasets / codesets.                                    |
| RAM7 | 0xC7      | Datasets / codesets.                                    |

Each populated bank is shipped as a disc file `GAME.B<n>` and streamed into page B
at `0x4000` by z88dk `loadbanks` at boot. Datasets are stored ZX0-compressed and
decompressed into **DSBUF** at runtime; codesets are paged in and called in place
at `0x4000`.

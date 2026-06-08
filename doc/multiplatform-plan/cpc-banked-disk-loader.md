# CPC-banked disk loader — design note

Status: **APPROVED (approach locked, user review 2026-06-08); pending PoC
validation of R-DL1.** Author: session work for Stage B7 step 8a/9.
Scope: how a cpc-banked (CPC 6128) RAGE1 game is loaded from disc at cold
boot. Sits under `banking.md` (§6 cpc-banked memory map, §3.5 ISR) and
`toolchain.md` Phase T3; supersedes the open "AMSDOS file loader **or** raw
block read" question left in `banking.md:582` / `:390`.

This note is the artifact to review **before** any loader code is written.

---

## 1. Problem statement and hard constraints

A cpc-banked game stores its datasets/codesets in the four expansion RAM banks
(RAM 4–7 = 64 KB) on top of the resident 64 KB base. The on-disc image is
therefore up to **~128 KB**. The loader must put each bank's bytes into the
right physical RAM bank at cold boot, under these **hard constraints**:

- **C1 — Banks stay compressed.** Dataset/codeset bytes are already
  ZX0-compressed in the banks and are decompressed *on demand at runtime* into
  the `0x8000` buffer (mirrors ZX, `banking.md:140`). The loader places the
  **raw compressed bytes verbatim** into each bank. There is **no
  decompress-at-load** step, and compression cannot be used to shrink the load
  (the data is already compressed).
- **C2 — Payload exceeds the address space.** Up to ~64 KB of bank data cannot
  be held resident in the 64 KB Z80 address space. The loader **must stream
  from disc bank-by-bank**, holding at most one 16 KB bank in the paging window
  at any instant.
- **C3 — Pure asmloader entry (DC6).** Entry is the AMSDOS binary
  `RUN"FILE` mechanism — no Locomotive BASIC loader, no headless tokeniser.
  The firmware is alive at load time and is disabled only just before
  `jp main` (`banking.md` §3.5 / DC6).
- **C4 — Memory-tight.** Peak transient RAM use during load must be ≈ one 16 KB
  window + the firmware file buffer; nothing that scales with total bank count.

---

## 2. CPC 6128 RAM configuration recap (why streaming-into-the-window works)

The 6128 Gate Array RAM-expansion command (port `0x7Fxx`, value `0xC0 | cfg`)
selects a 3-bit RAM configuration that remaps 16 KB blocks of the address
space (`banking.md` §3.1.4 / §6). The configurations relevant here:

| Config | `0x0000` | `0x4000` | `0x8000` | `0xC000` |
|-------:|:--------:|:--------:|:--------:|:--------:|
| 0 (base) | RAM 0 | RAM 1 | RAM 2 | RAM 3 |
| 4 | RAM 0 | **RAM 4** | RAM 2 | RAM 3 |
| 5 | RAM 0 | **RAM 5** | RAM 2 | RAM 3 |
| 6 | RAM 0 | **RAM 6** | RAM 2 | RAM 3 |
| 7 | RAM 0 | **RAM 7** | RAM 2 | RAM 3 |

Key property: **Configs 4–7 change only the `0x4000–0x7FFF` block.** The
firmware/ROM region (`0x0000–0x3FFF`), the AMSDOS workspace + 2 KB file buffer
(high RAM, ≈`0xA700–0xBFFF`), and the screen (`0xC000`) all stay mapped exactly
as in Config 0. This is the swap window RAGE1 already uses at runtime
(`swap_window = 0x4000`, `00bswitch.c`).

Therefore the firmware's disc file I/O can transfer bytes **into** `0x4000`
while expansion bank N is paged there — the firmware's own code, workspace, and
buffer are untouched by the Config 4–7 selection. **This is the load-time
analog of `memory_switch_bank()`** and is the single assumption the whole
design rests on (see §6, risk R-DL1 — validated by PoC before any loader code).

---

## 3. Load sequence (cold boot)

```
AMSDOS  RUN"GAME            ; AMSDOS loads the resident entry binary GAME.BIN
                            ; (asmloader + ALL resident code/data: page-A
                            ; 0x1200+ in RAM0, page-C 0x8000+ in RAM2) per its
                            ; AMSDOS header, then jumps to the asmloader entry.
                            ; This image is < 64 KB and loads under Config 0.

asmloader:                  ; firmware still enabled
    DI
    ; --- stream each populated bank from disc into its RAM bank ---
    for each (bank N, disc source) in the bank table:    ; N in {4,5,6,7}
        select Config N                  ; out (0x7Fxx), 0xC0|N  -> RAM N @ 0x4000
        load <disc source> -> 0x4000     ; firmware file I/O, <=16 KB, VERBATIM
        ; (no decompress; bytes are the already-compressed bank image)
    select Config 0                      ; restore base map

    ; --- hand over to the engine ---
    jp main                              ; main = engine CRT entry
```

The asmloader does **not** disable the firmware (decision Q4, 2026-06-08): it
hands straight to `main`, and the existing cpc path — `CRT_DISABLE_FIRMWARE_ISR`
+ `init_interrupts()` (B6 step 6) — owns firmware-disable and IM1 ISR setup,
exactly as it does today. So while the asmloader streams banks the firmware is
fully live (required for its file I/O), and `main()` takes it down.

Peak transient footprint: the 16 KB window (`0x4000–0x7FFF`, reused per bank) +
the firmware's 2 KB file buffer. Independent of how many banks exist → satisfies
C2/C4. A maximal game fills RAM 4–7 (64 KB) plus the resident base (64 KB) and
still loads from a ~128 KB disc image.

---

## 4. Firmware file-I/O mechanism (proposed)

Standard Amstrad firmware jumpblock entries (AMSDOS redirects the cassette
vectors to disc when `|DISC` is active, which is the 6128-with-drive default):

| Entry | Addr | Role |
|-------|------|------|
| `CAS IN OPEN`   | `0xBC77` | open file for input; B=name len, HL=name addr, DE=2 KB buffer addr |
| `CAS IN DIRECT` | `0xBC83` | load the whole open file to HL (chosen address) |
| `CAS IN CLOSE`  | `0xBC7A` | close input file |

Per-bank load (the recommended layout, §5):

```
        ld   de, cas_buffer       ; 2 KB buffer in mapped high RAM (page C, see below)
        ld   b, name_len
        ld   hl, bankN_name       ; e.g. "BANK4.BIN"
        call CAS_IN_OPEN
        ; ... select Config N here (RAM N now at 0x4000) ...
        ld   hl, 0x4000           ; destination = paging window
        call CAS_IN_DIRECT        ; firmware streams the file body into RAM N
        call CAS_IN_CLOSE
```

Placement rules during load (all in regions that stay mapped under Config 4–7):
- **asmloader code + bank table + filenames:** resident in page A (RAM 0,
  `0x1200+`) — mapped in every config.
- **2 KB `CAS IN OPEN` buffer:** page C high RAM (RAM 2, e.g. `0x8000+`) — must
  not overlap the `0x4000–0x7FFF` window nor the AMSDOS workspace.
- **destination:** `0x4000` (the paged bank).

> **Note (flagged uncertainty):** the exact `CAS IN OPEN` → `CAS IN DIRECT`
> register/headerless-file behaviour and the precise AMSDOS workspace extent are
> stated here as the *proposed* mechanism; both are confirmed empirically in the
> PoC (§6) before being relied on. Bank files are emitted **headerless** (raw
> compressed bytes) so `CAS IN DIRECT`'s HL fully determines placement.

---

## 5. On-disc bank-data layout — two options

Both satisfy C1–C4 (streaming, ≤16 KB resident). The choice affects loader
complexity and DSK packaging.

**Option A — per-bank files (RECOMMENDED).** One headerless file per populated
bank: `BANK4.BIN`, `BANK5.BIN`, …. Each loaded whole into the paged window via
`CAS IN DIRECT` (a single whole-file-to-address call). Simplest, most robust
loader; each load is intrinsically ≤16 KB.
- Cost: the DSK holds the loader file + up to 4 bank files.

**Option B — one concatenated data file**, streamed in 16 KB slices. Fewer
files, but `CAS IN DIRECT` loads a *whole* file, so slicing needs
`CAS IN CHAR` byte streaming (or buffered partial reads) — materially more
loader code and slower.

**Recommendation: Option A.** It pushes the heavy lifting into the firmware and
keeps the asmloader a thin per-bank loop.

---

## 6. Critical risk and PoC-first plan

**R-DL1 (gating).** *Does AMSDOS file I/O actually transfer into `0x4000` while
an expansion bank (Config 4–7) is paged there?* §2 argues yes (the firmware's
code/workspace/buffer are all outside the `0x4000–0x7FFF` block), but this is the
assumption the entire approach rests on. If it fails, the fallback is a
firmware-independent custom AMSDOS/track reader — substantially more work.

→ **PoC before any loader/template code** (matches the project's empirical MO,
as with the bswitch and ISR primitives): `games/cpc-disk-bankload-test` —
write a known marker file to the DSK, have a minimal program open it and
`CAS IN DIRECT` it into `0x4000` with RAM 5 paged, restore Config 0, page RAM 5
back and read the marker; assert PASS on cap32 (screenshot evidence).

*Decision (Q1, 2026-06-08): PoC-first is locked, and the firmware-independent
custom track loader is NOT built preemptively — R-DL1 is expected to pass; the
custom reader is held only as the contingency if the PoC fails.*

**R-DL2.** *DSK must hold multiple files.* The current
`zcc -create-app -subtype=dsk` path produces a single-file bootable DSK only;
no `iDSK`/multi-file DSK builder exists in the repo or z88dk's `bin/`. Lead to
investigate first during the PoC: `z88dk-appmake +cpc --bankspace` ("Create
custom bank spaces") — z88dk has first-class CPC banked-binary support that may
already package banks onto a bootable DSK.
*Decision (Q2, 2026-06-08): use existing tooling; do NOT add an `iDSK`-class
tool or a custom DSK writer now — revisit only if the PoC shows the existing
tools cannot produce a multi-file bootable DSK.*

**R-DL3 — RESOLVED (Q3, 2026-06-08).** *AMSDOS workspace vs resident page-C
data.* The AMSDOS workspace (≈`0xA700–0xBFFF`) coincides with the cpc-banked JSP
fixed-buffer region (DC7), which is **not populated until the game starts** —
so it is naturally free during the asmloader's disc-load phase. No extra
reservation is needed; the resident layout already keeps that region for the JSP
buffers, which the loader does not touch. (Confirm against the link map when the
loader lands, but this is no longer a design risk.)

---

## 7. Tooling / code changes (after the PoC validates the approach)

1. **`engine/loader-cpc-banked/asmloader.asm.in`** (+ snippet templates as
   needed): the per-bank streaming loop, Config select via the GA write
   (same encoding as `00bswitch.c`), firmware file calls, restore Config 0,
   `jp main` (NO firmware-disable — `init_interrupts()` owns it, Q4). Carries
   all platform-specific text (loadertool stays generic — `loadertool.pl:249-255`).
2. **`loadertool.pl --platform=cpc-banked`**: add the platform token + loader
   dir (`engine/loader-cpc-banked`) to `%loader_template_dir`; emit the
   per-bank load blocks from `bank_bins.cfg`/`dataset_info.asm`; lift loader-org
   literals into YAML (DC6).
3. **`banktool.pl`**: already emits per-platform bank binaries (step 8). Add
   headerless per-bank file emission for the DSK (or confirm the existing
   `bank_*.bin` are directly usable as the per-bank files).
4. **`Makefile-cpc-banked`**: `banks` + `loader`/`asmloader` + multi-file `dsk`
   targets (the banked analog of `Makefile-zx128`), consuming the
   `BANKED_CODE_*_CPC_BANKED` vars laid down in step 7.
5. **`games/cpc-banked-test`** (step 10): 1 dataset + 1 codeset smoke; cap32
   visual gate; joins the all-test-builds matrix.

ZX byte-identity is preserved throughout: all cpc-banked paths are additive and
the zx128 loader/templates/tooling are untouched.

---

## 8. Decisions (resolved at user review, 2026-06-08)

1. **Approach — LOCKED.** Per-bank files + firmware `CAS IN DIRECT`, **PoC-first**.
   No firmware-independent custom track loader is built preemptively; it is the
   contingency only if the PoC (R-DL1) fails.
2. **DSK packaging — DEFERRED.** Use existing tooling (investigate
   `appmake --bankspace` during the PoC). Do not add an `iDSK`-class tool or a
   custom DSK writer now; revisit only "if the need arises."
3. **R-DL3 — RESOLVED.** The AMSDOS workspace region coincides with the JSP
   buffers (DC7), which are unused before the game starts, so it is free during
   the load phase; no extra reservation needed.
4. **Firmware-disable — `init_interrupts()` keeps it.** The asmloader does NOT
   disable firmware; it restores Config 0 and `jp main`, and the existing CRT +
   `init_interrupts()` path disables firmware / sets the IM1 ISR as it does today.

Still to confirm **empirically in the PoC** (not design risks, just unverified
firmware details): exact `CAS IN OPEN` → `CAS IN DIRECT` headerless-file
behaviour, and that firmware file I/O transfers into a paged expansion bank
(R-DL1, the gating item).

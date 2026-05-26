# Memory Map

For 48K mode games, the memory map is like this:

```
0000-3FFF: ROM                   (16384 BYTES)
4000-5AFF: SCREEN$               ( 6912 BYTES)
5B00-5EFF: BASIC LOADER          ( 1024 BYTES)
5F00-CFFF: C PROGRAM CODE + HEAP (28928 BYTES)
D000-D100: INT VECTOR TABLE      (  257 BYTES)
D101-D1D0: STACK                 (  208 BYTES)
D1D1-D1D3: "jp <isr>" OPCODES    (    3 BYTES)
D1D4-D1EC: <free memory>         (   25 BYTES)
D1ED-FFFF: SP1 LIBRARY DATA      (11795 BYTES)
```

For 128K mode games, the base memory map is as follows:

```
0000-3FFF: ROM                   (16384 BYTES)
4000-5AFF: SCREEN$               ( 6912 BYTES)
5B00-7FFF: LOWMEM BUFFER + HEAP  ( 9472 BYTES)
8000-8100: INT VECTOR TABLE      (  257 BYTES)
8101-8180: STACK                 (  128 BYTES)
8181-8183: "jp <isr>" OPCODES    (    3 BYTES)
8184-D1EC: C PROGRAM CODE        (20585 BYTES)
D1ED-FFFF: SP1 LIBRARY DATA      (11795 BYTES)
```

In 128K mode, the additional banks are mapped into $C000 address range in
the usual way.  Also, the ROM page mapped at address $0000 is the 48K ROM,
since this is required for correct SP1 library initialization.

The memory layout for 128K mode may be changed in the RAGE1 config file,
please refer to the [BANKING-DESIGN.md](BANKING-DESIGN.md) document for a
full reference on the memory banking implementation in RAGE1.

## Distribution of memory banks in 128K mode

The regular mapping of banks 5,2,0 is used at program startup.

- Bank 5 is used for screen, lowmem buffer and heap

- Banks 2 and 0 are used for lowmem code and SP1 data (SP1 code is not
  currently banked in RAGE1)

- Bank 4 is used by RAGE1 for its banked code (owned by RAGE1; non-contended)

- Bank 6 can be used for CODESET 0 (user code and data; non-contended)

- Banks 1,3,7 can be used for DATASETs (user data assets: sprites, tiles,
  screens and rules; contended)

- If needed, some of the DATASET banks can be used for CODESETs (change
  DATAGEN source for that), but keeping in mind that the code will live in
  contended memory, so it will run a bit slower.

- As a rule of thumb, even banks should be used for code, odd banks for
  data.

Note: contended banks: 1,3,5,7; non-contended: 0,2,4,6.

## Per-platform `mmap.inc` policy (Phase B3-2)

The z88dk link step is driven by `mmap.inc`, a `--mmap`-style file that
lists every section the linker has to know about and the memory regions
they belong to. Across the supported platforms RAGE1 follows this
policy (see `doc/multiplatform-plan/banking.md` §B3 for the long form):

- **ZX 128** keeps the canonical `mmap.inc` at the repo root verbatim.
  This file (248 lines, ~97 declared sections) encodes the resident /
  banked / lowmem layout in §"128K mode" above, and is the reference
  the lowmem-symbol check and the section-presence check both validate
  against.

- **ZX 48** has no banking pressure: it links as a single resident
  binary against the default z88dk mmap. No per-platform `mmap.inc`
  variant is needed today and none is planned. If a future change adds
  ZX 48-specific section discipline, drop a `mmap-zx48.inc` next to the
  current `mmap.inc` and feed it to the toolchain via the new
  `tools/check_mmap_sections.sh --mmap <file>` argument (B3-3).

- **Amstrad CPC** will get two variants in Phase B5: `mmap-cpc-flat.inc`
  (CPC 464/664 — 64K flat) and `mmap-cpc-banked.inc` (CPC 6128 — Gate
  Array banking). These files are not present yet; this section
  documents the intent so the tool seam is in place.

The `--mmap` argument added to `tools/check_mmap_sections.sh` (B3-3) and
the `--threshold` argument added to `tools/lowmemsym.pl` (B3-1, default
`0xC000`, sourced from `banking.<platform>.swap_window` in
`etc/rage1-config.yml`) are the two seams that let a future platform
plug its own mmap and its own swap-window address into the existing
build-system checks without touching the tools again.

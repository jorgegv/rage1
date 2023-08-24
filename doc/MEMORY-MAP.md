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

Please refer to the [BANKING-DESIGN.md](BANKING-DESIGN.md) document for a
full reference on the memory banking implementation in RAGE1.

## Distribution of memory banks in 128K mode

The regular mapping of banks 5,2,0 is used at program startup.

- Bank 5 is used for screen, lowmem buffer and heap

- Banks 2 and 0 are used for lowmem code and SP1 data (SP1 code is not
  current banked in RAGE1)

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

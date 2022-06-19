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

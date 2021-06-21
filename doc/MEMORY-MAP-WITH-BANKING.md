# Memory Map when using memory banking

This is the runtime memory map after CRT takes control and ets up
everything. For this map to work interrupts must be disabled at program
start (set the proper pragma!)

```
; ADDRESS (HEX)   LIBRARY   DESCRIPTION
;
; d1ed - ffff     SP1.LIB   All SP1 data structures
; c000 - d1ec     -------   free - available for C programs (4589/0x11ed bytes )
; 8000 - bfff     -------   free - available for C programs (16384/0x4000 bytes)
; 5d00 - 7fff     -------   free - available for C programs (8960/0x2300 bytes)
; 5d5f - 5d00     -STACK-   162 bytes
; 5c5c - 5c5e     -------   JP to im2 service routine (im2 table filled with 0x5c bytes)
; 5c01 - 5c5b     --free-   free - (90/0x5a bytes)
; 5b00 - 5c00     IM2.LIB   im 2 vector table (257 bytes, all 0x5c)
; 4000 - 5aff     SCREEN$   Screen data
; 0000 - 3fff     ROM-1     ROM
;
; -- And while BASIC loads everything:
; 5b00 - ...     -BASIC-    SYSVARS, Loader program, etc. give it some breathing :-)
```

* TODO: add fixed place for loading sound code and data, to make sure it is
not in contended memory

# Memory Map

```
; ADDRESS (HEX)   LIBRARY   DESCRIPTION
;
; d1ed - ffff     SP1.LIB   All SP1 data structures
; d1d4 - d1ec     --free-   25 bytes free
; d1d1 - d1d3     -------   JP to im2 service routine (im2 table filled with 0xd1 bytes)
; d101 - d1d0     -STACK-   208 bytes
; d000 - d100     IM2.LIB   im 2 vector table (257 bytes)
; 5f00 - cfff     -------   free - available for C programs
; 5b00 - 5eff     -BASIC-   Loader program, give it some breathing :-)
```

* TODO: add fixed place for loading sound code and data, to make sure it is
not in contended memory

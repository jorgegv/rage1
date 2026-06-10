
| Region          | 64-mode | 128-mode  | 128 Start Addr   | 128 End Addr  |
|-----------------|---------|-----------|------------------|---------------|
| Engine Code     | ~23 KB  | ~23 KB    | 0x400 (or lower) | up to ~0x57ff |
| BSS+DATA        | ~4 KB   | ~4 KB     | 0xA000           | up to  0xbfff |
| JSP BUF         | ~10 KB  | ~10 KB    | 0x6000           | 0x7fff        |
| DECOMP BUF      | -       | ~11 KB    | 0x8000           | 0x9fff        |
| TOTAL           | ~37 KB  | ~48 KB    |                  |               |
| Avail. for GAME | ~12 KB  | 48 KB (*) |                  |               |

(*) We need additional bank for banked engine code(?), or does the 23KB figure already include it? I don't think so
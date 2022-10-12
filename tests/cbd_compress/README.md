# CBD Compression: Cell Bytes Deduplication

Deduplication of byte-data for Spectrum graphics tiles.

- First iteration (`test1.pl`): searches for duplicated 8-byte sequences
  (pretty trivial - just reuse whole tiles if duplicated at the 8-byte
  boundary)

- Second iteration (`test2.pl`): tries to overlap each new 8-byte sequence
  with the last 8 bytes of the pool, so that less than 8 bytes are emitted
  to the pool it they overlap.

- Third iteration (`test3.pl`): for each new tile we want to emit to the
  pool, try to find (between the remaining tiles) the one that has the most
  overlapping bytes with the last 8 bytes of the pool, and use that as the
  next tile to emit.  This makes sure that at each iteration a locally
  minimal number of bytes are emitted.

  This reorders the original tiles (which the first 2 iterations did not),
  but the new order can be noted and the code generated taking it into
  account.

  The 3rd iteration focuses on local minima for the number of bytes emitted,
  but this does not guarantee that a global minimum is reached (which is
  what we are searching for), so probably the 4th iteration of the algorithm
  will center around some repeated tries with different encoding paths and
  some backtracking.

- Fourth iteration (`test4.pl`): do the third oteration using each of the
  tiles as the first, compare compression results for all and pick the one
  with best results.

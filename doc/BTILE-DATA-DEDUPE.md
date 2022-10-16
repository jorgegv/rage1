# BTile Cell Data Deduplication

## Problem Description

In order to use bigger tiles for creating screens in RAGE1 without making
each screen use potentialy up to 768 bytes (or 1536) for specifying the 8x8
tiles on each screen position, a mechanism called BTILEs (for "Big Tiles")
was designed.

Each BTILE is defined as a set of MxN regular 8x8 tiles.  Screens are then
defined by specifying these BTILEs and their positions, with the net result
that a given screen may be defined by using (for example) just a dozen of
these BTILEs, while defining them with each 8x8 cell would ocupy quite more
bytes.

Of course there is a general table of BTILEs that must be defined somewhere,
and this also occupies memory, but the savings from positioning a single
element which then ocuppies severall cells quickly add up and compensate the
extra memory used.

Additionally, RAGE1 games are intended to use the 128K memory available in
higher Spectrum models, so there can be a high number of BTILEs and/or those
BTILEs can be big ("big" meaning much more than the regular 2x2-cell sprites
that we are all used to in Spectrum games).

The individual BTILE cells may also be useful by themselves alone, or in
groupings that are contained in the original bigger BTILE: lets say a BTILE
is composed of the 8x8 tiles ABCDEFGH, in a 4x2 layout (each double letter
represents a single 8x8 tile):

```
  AABBCCDD
  EEFFGGHH
```

The main (outer) BTILE may be defined as a 4x2 cell one, but perhaps some other
layouts are also useful for our game screens:

```
  AABB        <-- Left half of the big tile
  EEFF

  CCDD        <-- Right half of the big tile
  GGHH

  EEFFGGHH    <-- Top row of the big tile

  AA          <-- Top left cell of the big tile
```

When we are defining these BTILEs in RAGE1 GDATA files, most of the time we
will draw the big BTILE in a PNG file and then tell RAGE1 to get the graphic
data from there, giving source coordinates and dimensions.

It is very easy then to reuse the same graphic PNG data to define the big
BTILE, and then several others which are subsets of the big one and that may
also be used in the screens.

This has one problem: the RAGE1 data compiler assumes that each BTILE is
completely independent of all other BTILEs, and just gets whatever data it
needs from the PNG, then spits out the Spectrum data.  If you tell it to get
the same data several times but in different configurations (BTILEs), then
this data will be duplicated for some of the cells, since they are different
BTILEs.

This is very convenient for the programmer (draw your graphics once, define
several BTILEs), but it is not convenient for the program: memory is a
scarce resource and we are generating duplicate data.

If you add to the mix the Animated BTILE functionality (BTILEs that have
frames, that is, they are defined multiple times), the situation only
worsens.

So we want to have a system that makes it easy for game developers to define
their graphics quickly, and store the data efficiently, but we should also
try to leave the optimization part to the computer instead of having to
optimize manually.

We need to deduplicate the BTILE graphic data: allow us to use data multiple
times for our definitions, and let the compiler ensure that duplicate data
is kept to a minimum.

The generic problem that we want to solve is:

"Given a set of sequences of numbers, find the smalles new sequence that
contains all the original ones as sub-sequences, regardless of their initial
order or final position"

## Possible Solutions

The first problem to solve is to have all BTILE cell data together, so that
it can be properly analyzed and processed.

So far, data for each BTILE (cell-data and pointers that point to that
cell-data) is generated together, and then each BTILE separate from each
other.  This layout is convenient from a developer point of view (all data
related to a given BTILE is together), since it allows you to easily inspect
the generated source code.

But now that the BTILE generation code in RAGE1 is very mature, it makes
sense to rearrange the data generation so that cell-data for all BTILEs is
separated from the pointers and output all together in a single byte-arena. 
The pointers would also be rearranged also to point into zones of this
arena.

This arena can then be analyzed for duplicate sequences that may be
removed/compressed/deduplicated.

Since this rearrangement is trivial, we will assume our cell-data is already
arranged in that way.

Some solutions to the deduplication issue have then been explored and are
descrobed below (there are test programs and data in directory
`tests/cbd_compress`):

- Iteration 1 (`test1.pl`): keeps track of all 8-byte sequences in the
  arena, and just reuses whole tiles if duplicated at the 8-byte boundary
  (pretty trivial)

- Iteration 2 (`test2.pl`): does the same as Iteration 1 and then tries
  to overlap each new 8-byte sequence with the last 8 bytes of the pool, so
  that less than 8 bytes are emitted to the pool it they overlap.

- Iteration 3 (`test3.pl`): for each new tile we want to emit to the
  pool, try to find (between the remaining tiles) the one that has the most
  overlapping bytes with the last 8 bytes of the pool, and use that as the
  next tile to emit.  This makes sure that at each iteration a locally
  minimal number of bytes are emitted.

  This reorders the original tiles (which the first 2 iterations did not),
  but the new order can be noted and the code generated taking it into
  account.

  The 3rd iteration focuses on local minima for the number of bytes emitted,
  but this does not guarantee that a global minimum is reached (which is
  what we are searching for)

- Iteration 4 (`test4.pl`): do the third oteration using each of the
  original tiles as the first one, compare compression results for all and
  pick the one with best results.

## Results

- Results from Iteration 1 and Iteration 2 for some demo data sets were
  encouraging, reaching some 20% savings

- These results were not very representative, since by its very nature this
  algorithm is _very_ dependent on the BTILEs defined

- Results from Iteration 3 were worse than Iterations 1 and 2 by a long shot
  (savings now were on the 10% for the same demo data)

- Results from Iteration 4 showed similar results as Iteration 3 for all
  different starting cells

## Conclusions and Way Forward

- For a given data set, savings have been demonstrated to have great
  variation depending on the Iteration; this shows that indeed the order in
  which the original cells are deduplicated and emitted to the arena is very
  important and that some orders are much better than others to get good
  deduplication ratios.  Iteration 1 and Iteration 2 are special cases of
  Iteration 3.

- This points to doing an exhaustive analysis of all the orders in which the
  cells should be analyzed and emitted, and get the one with the best
  results.  But this is indeed a problem of checking all permutations of N
  original cells, and this problem very quickly gets intractable ( O(N!) )

- In the future, some additional research may be done in order to accelerate
  the exploration of possible better solutions to this problem so that we
  can get better deduplication ratios

So for now, the following actions will be done in RAGE1 for allowing the
developer-friendly BTILE definitions indicated above, and still get good
storage efficiency:

- Change cell-data layout to use a single byte-arena per DATASET and make
  the BTILE data pointers point inside the arena

- Deduplicate cell-data using algorithm from Iteration 2: we first make sure
  that repeated 8-byte sequences (i.e.  repeated cells) are only emitted
  once, and then any adjacent cells that may have common suffix/prefix
  (admittedly a small number) are coalesced for some more byte savings

The memory layout is completely equivalent to the original one regarding
cell storage and pointers, and has no performance impact, it only increases
storage efficiency.

# BANKING DESIGN

Rationale:

Since the SP1 library and the RAGE1 engine itself have started to occupy
quite a lot of memory, there is fewer memory dedicated to game assets
(screens, sprites, tiles, rules, etc.).

There are a few memory optimizations pending, but the real one would be to
switch to 128K compatible games, so that we can use the other 64K for those
assets.

The main problem with that is that paging in the 128K model takes place in
the upper 16K page (base 0xc000), but this is occupied by the SP1 library
data and some other structures. So it is not possible to use it to have
regular assets during the game, but only as a kind of "external" storage.

So the assets reside in whatever page they are loaded at start, but when
they are needed (entering, exiting screen) they must be loaded into "low"
memory: a chunk of memory below 0xc000 which will be reserved for this
purpose.

Design points:

- All of the game code must reside in low memory (below 0xc00)

- There are some assets that are used all the time and must reside in low
  memory: hero and bullet sprites, character set, game state, etc.

- There are other assets that are used only at given times, and that can be
loaded and unloaded on-demand: sprites, tiles, screen rules, sounds, etc.

- For the loadable assets that are reusable, a simple optimization is to
  have them organized in banks.  I.e.  sprite banks, btile banks, sound
  banks, screen banks.

- A "bank" is a group of assets that can be loaded at once.

- The MAP is an array of screens.  SCREENs can be arranged in banks, so the
  MAP contains not only the screen number, but tuples (screen bank, index)

- The SCREEN has new fields for BTILE, SPRITE, SOUND and RULE banks that are
  the ones used for that screen.  The indexes for elements on each screen
  are always referred to the current bank of elements of the given type.

- When ENTER_SCREEN or EXIT_SCREEN, the current banks for all element types
  are checked, and switched to the new banks if needed before/after
  switching screen.

- For switching element banks, the whole bank is copied from high to low
  memory as needed.  With this schema, only the banks for sprites, btiles,
  sounds, screens and rules that are used by the current screen are in low
  memory.

- Element banks need not be big.  In fact, they should be as small as
  possible, in order to fit in low RAM.  We can have a big number of banks
  in high memory, up to 64 KB.

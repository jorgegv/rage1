# Optimization tips

In general, follow advice from https://github.com/z88dk/z88dk/wiki/WritingOptimalCode

The following sections explain the most interesting techniques mentioned there.

## Use static local variables if needed

* Stack allocated vars (i.e.  local vars) are normally accessed by using a
  base pointer (e.g.  `ld a, (ix+7)` ).  But in Z80 this load type is way
  slower than direct address loading (e.g.  `ld hl, 23000` + `ld a,(hl)`).

* You can use local variables in functions, but declare them with "static",
  which makes them use a fixed address, instead of being dynamically stack
  allocated.  This makes the program slightly bigger in memory, but faster. 
  Local scope in vars declared this way is not affected.

* For this to work OK, _never_ initialize a static local variable in the
  same declaration.  Always initialize after declaring it i the function, so
  that initialization runs in all function invocations, and not only on the
  first.

* As with all optimizations, use them where they make sense and be aware of
  the memory/speed trade off

* As a rule of thumb, this optimization pays off in medium-big functions ( >
  15-20 lines) in which the optimized variable is used a lot.  It is usually
  not worth to do it in small functions.

* Apply this optimization one function at a time, and build and check the
  used memory after applying it. You may find that you thought the function
  would decrease in size, but it increases instead.

Example (this is a small function, so it is not worth in this case, but it
shows the technique):

```
void my_fun( int a ) {			void my_fun( int a ) {
  int i = 10;				  static int i;
					  i = 10;
  ...					  ...
  (code)				  (code)
  ...					  ...
}					}
```

## Use 8-bit integers whenever possible

* Z80 is an 8-bit machine and it's optimized for that, so always declare
  counters, indexes, etc. as `uint8_t` if possible.

* For comfortable programming, always include `<stdint.h>` so that you have
  bit-explicit integer types available for use (e.g. `uint8_t`, `uint16_t`)

* Always prefer unsigned to signed integers if possible

## Avoid passing large parameters or a large number of them to a function

* When the number of arguments is greater than, let's say, 2 or 3, consider
  defining a struct for all those params, and passing instead a pointer to
  that struct when calling that function

* When your function receives a single parameter (8 or 16-bit), declare the
  function as `__z88dk_fastcall`.  This will pass your parameter directly in
  L or HL registers (which can be used straight forward inside the called
  routine), and also makes the function not need to clean the stack when
  returning.  This option is specially interesting for functions that are
  called very often.

## Make loop counters count down instead of up

* C constructs like `while ( i-- ) { ... }` can be directly translated to
  DJNZ instructions, which are compact and convenient

* Beware of cases where the items need to be accessed in order from 0 up.
  When counting down, your items will be processed starting from the last.

Example:

```
for ( i = 0; i < MAX_ITEMS; i++ ) {		i = MAX_ITEMS;
  ...						while ( i-- ) {
  (code)					  ...
  ...						  (code)
}						  ...
						}
```

## Code size optimization guidelines

The following guidelines are some of the conclusions of the important code
size reduction that was done during the 0.4.0 development cycle.

### Conditional compilation

Place your code between `#ifdef's` so that it can be conditionally
compiled out if it is not needed.  See
[CONDITIONAL-COMPILATION.md](CONDITIONAL-COMPILATION.md) for details on how
this is done in RAGE1 code.

### Use only the memory needed and no more

Optimize memory usage in data structures, specially for the ones that are
instantiated mutiple times, e.g.  enemy data, tile position information,
etc.  A couple of bytes saved in a structure that is defined dozens of times
quickly add up for substantial memory savings.

Only expand your data structures when/if it is needed.

**Example 1**

- The data structure that holds the tile type for each of the 32x24
  character screen positions initially reserved 1 byte per screen position,
  thus occupying 768 bytes of memory. The check for a tile type was just a
  matter of calculating `32 * row + col` and indexing on the tile type array
  to get the tile type for that position

- But tiles can be only 3 different types so far, so we didn't need 1 full
  byte (8 bits) for the tile type.  In fact, only 2 bits were needed per
  position, so we could even pack 4 positions per byte.  This would bring
  down the memory size of the tile type array to 25% of its original size,
  that is, 192 instead of 768 bytes.

- The price to pay for that bit-packing were slightly more complex functions
  for getting and setting the tile type at a given position.  But the small
  slowdown due to these functions was not noticeable during gameplay, so the
  change was commited

**Example 2**

- There were several struct definitions in which a 16-bit `flags` field had
  been included.  In some structures it was needed, but in others it was
  included as a sort of "defensive" programming design ("we will probably
  need it in the future")

- The reality was that those `flags` fields were heavily underutilized, and
  a) when they were really used, only 1 or 2 flags were being really used;
  b) there were several instances that were not used at all; and c) those
  structures were instantiated all over the game. The net result was that we
  had empty or almost-empty 16-bit `flags` fields all over the place

- Big savings were generated by just changing the `flags` fields to 8-bit,
  and removing the unneeded ones

### Calculate only once, reuse the value

Remember that in 8-bit environments, with low memory and a CPU with a
limited instruction set, even the smallest calculation in C quickly
generates dozens if not hundreds of assembler instructions.

It is thus very convenient that you refactor calculations as much as
possible, by using temporary variables to store calculated variables and
using those values where needed in a given function.

### Replace indirect pointer accesses with constants if possible

A simple C assignment as the following one:

~~~C
sp = all_sprite_graphics[ game_state.hero.num_graphic ];
~~~

Generates 20-30 assembly instructions just for getting the value of a
pointer in an array. But if the `game_state.hero.num_graphic` does not
change during the game and is known (or can be calculated) at compile time,
the assigment can be replaced with code similar to:

~~~C
sp = all_sprite_graphics[ HERO_NUM_GRAPHIC ];
~~~

In this assignment, all data is known at compile time (`all_sprite_graphics`
is at a concrete address), so it only generates 6-8 assembly instructions to
get the value.

As in previous cases, if you have multiple similar assignments scattered in
your code, the memory savings quickly add up.

### Replace indirect pointer accesses with function calls

A similar case to the previous one: if you have a complex assignment, in
which some values are extracted from an array, which are then used to index
another array and extract more data, and so on...  And if this assignment is
done in several places in your code, your complex calculation is a great
candidate for refactoring into its own auxiliary function

Remember that for an 8-bit CPU, a simple C indexed array calculation can
very easily be "a complex calculation"

Also, keep in mind that on 8-bit CPUs, function calls are not as disruptive
to the execution flow as on modern processors.  In modern CPUs, we have
speculative execution, pipelining, caches, etc.  which greatly improve
performance if your code runs "straight", but suffer very badly when the
execution flow changes unexpectedly (functions calls, jumps, returns).

Old CPUs do not have those bells and whistles, and only suffer a small
performance penalty when making a CALL instruction, and this penalty can
probably be well compensated by the memory savings due to the duplicated
code being replaced with a function call.

### Replace indirect pointer accesses with precalculated variables

This a corollary of the previous recommendations: calculate things just once
and reuse the value. You should only recalculate a value when its inputs
change.

**Example**

The current screen pointer is heavily used in RAGE1 for accessing the screen
assets, in a way similar to this:

~~~C
num_enemies = banked_assets->all_screens[ game_state.current_screen ].enemies.num_enemies
~~~

The `banked_assets->all_screens[ game_state.current_screen ]` part of the
assignment is constant when you stay in the same screen (which is most of
the time), but this kind of assignment was being used all over the place in
the main game loop.

We added an additional `current_screen_ptr` field to the main `game_state`
structure to keep the precalculated value for a pointer to the current
screen data.  We only recalculated it in the same function where we switched
screen (and so we kept the `current_screen` and `current_screen_ptr`
variables in sync).  We then replaced the accesses above with:

~~~C
num_enemies = game_state.current_screen_ptr->enemies.num_enemies
~~~

This code, as it has been seen in a previous recommendation, has all symbols
known at compile time, and thus generates much shorter code for accessing
the value.

### Always optimize the common case

As a general rule, always optimize things that are repeated, since they are
the ones that will bring you the most benefit for the time you spend
optimizing them:

- If you are optimizing your code size, search for repeated code sequences in
  your sources, and optimize them with smaller ones

- If you are optimizing for execution speed, search for the most repeated
  loops, and optimize the code inside those loops

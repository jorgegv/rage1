# Optimization tips

In general, follow advice from https://github.com/z88dk/z88dk/wiki/WritingOptimalCode

The following sections explain the most interesting techniques mentioned there.

## Use static local variables

* Stack allocated vars (i.e.  local vars) are normally accessed by using a
  base pointer (e.g.  ld a, (ix+7)).  But in Z80 this load type is way
  slower than direct address loading (e.g.  ld hl, 23000 + ld a,(hl)).

* Use local variables in functions, but declare them with "static", which
  makes them use a fixed address, instead of being dynamically stack
  allocated.  This makes the program slightly bigger in memory, but faster. 
  Local scope in vars declared this way is not affected.

* For this to work OK, _never_ initialize a static local variable in the
  same declaration.  Always initialize after declaring it i the function, so
  that initialization runs in all function invocations, and not only on the
  first.

Example:

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
  counters, indexes, etc. as uint8_t if possible.

* For comfortable programming, always include <stdint.h> so that you have
  bit-explicit integer types available for use (e.g. uint8_t, uint16_t)

* Always prefer unsigned to signed integers if possible

## Avoid passing large parameters or a large number of them to a function

* When the number of arguments is greater than, let's say, 2 or 3, consider
  defining a struct for all those params, and passing instead a pointer to
  that struct when calling that function

## Make loop counters count down instead of up

* C constructs like `while ( i-- ) { ... }` can be directly translated to
  DJNZ instructions, which are compact and convenient

Example:

for ( i = 0; i < MAX_ITEMS; i++ ) {		i = MAX_ITEMS;
  ...						while ( i-- ) {
  (code)					  ...
  ...						  (code)
}						  ...
						}

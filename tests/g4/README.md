# Phase G4 — `gfx_xpos_t == uint16_t` compile-cleanly smoke test

Per the gfx.md Phase G4 phase-exit criteria:

> Code compiles cleanly with `gfx_xpos_t == uint16_t` defined for a
> hypothetical CPC backend (verified by adding a temporary test header).

This directory holds that test header + a tiny test `.c` that exercises the
HAL signatures and the engine-style call patterns that consume pixel
coordinates.  The test does NOT link or run — it only needs to compile
cleanly without warnings or errors, proving the engine code stays
type-safe when the typedef is widened on CPC bring-up (Phase G7).

## Files

- `test_xpos16.h` — overrides `gfx_xpos_t` / `gfx_ypos_t` to `uint16_t` and
  re-declares the minimal HAL surface that consumes pixel coordinates.
- `test_xpos16.c` — exercises the wide-coord HAL signatures using
  engine-style patterns (movement bound clamping, pixel-coord HAL calls,
  print-context init, etc.).

## How to run

```bash
# From the worktree root:
make -f tests/g4/Makefile
```

The Makefile uses the host C compiler (gcc / clang) with `-Wall -Werror
-Wconversion` so any silent truncation would be caught.  A clean exit
means the typedef widening is byte-safe at the engine source level.

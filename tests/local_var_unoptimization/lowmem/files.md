# Files to check

Optimzations legend:

- FASTCALL: optimize single parameter functions with `__z88dk_fastcall`
- STATIC: convert local vars into static local
- UNOPT: unoptimize vars with precalculated expressions

Files:

- [x] engine/src/controller.c - NO CHANGES
- [x] engine/src/screen.c - NO CHANGES
- [x] engine/src/sp1engine.c - NO CHANGES
- [x] engine/src/sprite.c - FASTCALL,STATIC
- [x] engine/src/util.c - FASTCALL
- [x] engine/src/charset.c - NO CHANGES
- [x] engine/src/crumb.c - FASTCALL
- [x] engine/src/sound.c - NO CHANGES
- [x] engine/src/timer.c - NO CHANGES
- [x] engine/src/debug.c - CONDITIONAL COMPILE
- [x] engine/src/interrupts.c - NO CHANGES
- [x] engine/src/memory.c - NO CHANGES
- [x] engine/src/codeset.c - FASTCALL
- [x] engine/src/main.c - NO CHANGES
- [x] engine/src/banked.c - NO CHANGES
- [x] engine/src/dataset.c - NO CHANGES
- [x] engine/src/bullet.c - NO CHANGES
- [x] engine/src/collision.c - UNOPT
- [x] engine/src/enemy.c
- [x] engine/src/flow.c
- [x] engine/src/hero.c
- [x] engine/src/hotzone.c
- [x] engine/src/map.c - FASTCALL
- [x] engine/src/game_loop.c
- [x] engine/src/btile.c
- [x] engine/src/game_state.c
- [x] engine/src/inventory.c

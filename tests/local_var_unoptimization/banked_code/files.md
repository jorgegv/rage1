# Optimization of local vars

Files to review and associated baseline after optimization:

- [x] engine/banked_code/common/animation.c - NO CHANGES
- [x] engine/banked_code/common/beeper.c - NO CHANGES
- [x] engine/banked_code/common/btile.c - NO CHANGES
- [x] engine/banked_code/common/bullet.c - OK - optimize1.txt
- [x] engine/banked_code/common/enemy.c - OK - optimize2.txt
- [x] engine/banked_code/common/hero.c - OK - optimize3.txt
- [x] engine/banked_code/128/btile.c - NO CHANGES
- [x] engine/banked_code/128/dataset.c - NO CHANGES
- [x] engine/banked_code/128/init.c - NO CHANGES
- [x] engine/banked_code/128/tracker_arkos2.c - NO CHANGES
- [x] engine/banked_code/128/tracker.c - NO CHANGES
- [x] engine/banked_code/128/tracker_vortex2.c - NO CHANGES
- [x] engine/banked_code/128/util.c - NO CHANGES

Conclusions:

- It's not a matter of "never use intermediate local vars" or "always use
  intermediate local vars".  There are places where the code is complex and
  the manual optimization pays off, and places where the code is simple and
  you must let the compiler optimize.

- Strategy should be to test every optimization and only pick one when the
  code size is smaller. Case by case and function by function.

- Always test with the full build baseline, do not compile each file
  independently.

# Arkos proof-of-concept tests

* `periodic` directory: an Arkos demo program where the Disark technique has
  been used to get a location independent ASM source file for the Arkos
  player (see https://www.julien-nevo.com/arkostracker/index.php/source-conversion-with-disark/).
  This source is used in direct-loop mode (i.e. _not_ using it from IM2 ISR
  handler), the same way as it is used when integrated in RAGE1.

* `binary-tests` directory: the tests that needed to be done until we made
  sure that the Arkos player compiled exactly to the same bytes in its
  original form (RASM format), intermediate form (PASMO) and final form
  (Z88DK's Z80ASM)

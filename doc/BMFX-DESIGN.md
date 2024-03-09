# BMFX DESIGN

This document describes the design of the BMFX (Beeper Multiple FX) sound effects engine.

BMFX used only the standard beeper and this can be used in any ZX Spectrum model.

- The sounds play at fixed periods (ideally on interrupts, so every 20ms, or
  1/50s).

- All sound is made up of short mini-beeps of a fixed duration (we call them
  TICKs, 2ms by default), short enough that the gameplay is not affected from the user point
  of view.  Think Manic-Miner, or Dynamite Dan style sound effects or music.

- A sound FX is made up of several beeps, which are (tone,duration) pairs.
  The duration is specified in ticks.

- The FX is played during several periods, and on each period, a tick at the
  given tone is played. A state for that sound is kept so that the engine
  knows where to find the tick that should be played next.

- The engine can play several FX simultaneously, by using a fixed number of
  channels (3 by default). When an FX is requested to play, it is stored in the first
  available channel and immediately starts playing.

- On each period, all active channels are checked and the FX configured at
  that channel is played at its current position, then the position counters
  are updated.

- If there are no active FX playing (i.e. all channels are not active), then
  no time is spent.

With the above mentioned configuration, up to 6ms of every 20ms can be used
for playing sound FX.

# RAGE1: Retro Adventure Game Engine, release 1

RAGE1 is an adventure game engine for the ZX Spectrum based on the great SP1
sprite library by Alvin Albrecht.

Its initial purpose is the generation of adventure games with zenital
pespective, but it will evolve to support other types of games, e.g.
platforms, etc.

Inspiration for this engine comes from Mojon Twins' MK1 La Churrera. In fact
`beeper.asm` is shamelessly copied from their code. Credit goes to them :-)

The public GIT repository for this engine is https://github.com/jorgegv/rage1

Bug reports, comments, enhancements and pull requests are very welcome.

See `doc` directory for engine usage and development documentation.
Apologies for not being complete; if in doubt, navigate the source :-)

See `doc/TODO.md` for some short term enhancements which are in the works,
and feel free to suggest more by opening GitHub issues!

## Quick Start

* Make sure you have a Z88DK distribution in directory `z88dk` at the same
  directory level as this repo, compiled with SDCC support
* Check the `doc/REQUIREMENTS.md` file for some minimal requirements, and install them if needed
* Execute the following to compile and run the demo game with FUSE (Unix
Spectrum Emulator):

```
source env.sh
make build
make run
```

* The game has also been tested with ZesarUX, but I find FUSE better suited for quick testing

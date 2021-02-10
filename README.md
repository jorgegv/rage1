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

See [TODO](doc/TODO.md) for some short term enhancements which are in the works,
and feel free to suggest more by opening GitHub issues!

You can also chat about the engine, your ideas, proposals and possibly games
built around it in the [GitHub RAGE1 Discussions forum](https://github.com/jorgegv/rage1/discussions/12)

## Linux Quick Start

* Download and install [requirements](doc/REQUIREMENTS.md)
* Make sure your Z88DK distribution lives in directory `z88dk` at the same
  directory level as the RAGE1 repo, compiled with SDCC support. E.g.
  ```
  my_sources/
  ├── rage1
  └── z88dk
  ```
* Execute the following to compile and run the demo game with FUSE (Unix
Spectrum Emulator):
  ```
  source env.sh
  make build
  make run
  ```
* The demo game and engine has also been tested with ZesarUX, but I find FUSE better suited for quick testing

## Windows Quick Start

* Download and install [requirements](doc/REQUIREMENTS.md)
* Add Fuse installation directory to path in user environment variables
* Open Cygwin terminal, cd to the Rage1 directory and run:
  ```
  make build
  make run
  ```
* NOTE: In Windows it is not necessary to source `env.sh`

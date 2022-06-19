# RAGE1 Roadmap

## 0.1.0 - Released on 2020-12-12

- Initial public release
- Basic game definition: tools and game data file format
- Basic game functionality: tiles, sprites, collision detection, shots,
  items, global game loop and state management
- Simple test game

## 0.2.0 - Released on 2021-04-27

New features:

- Game scripting and rule system
- Support for BeepFX sound effect definitions
- Screen text mode compiler and enhanced probabilistic screen backgrounds
- Customizable game functions and screen areas
- More versatile sprite and btile handling (sequences, enable/disable, etc)

## 0.3.0 - Released on 2021-06-27

New features:

- Flowgen enhancements
- New memory mapping report tools
- New minimal playable game that you can use as a starting point right away
- New enemy animations
- Devel doc for implementation of common behaviours and events

## 0.4.0 - Released: 2021-10-02

New features:

- Allow automatic use of 128K extra banks for game data
- Allow compilation to 48K/128K target with just a single config setting
- Use FEATURE definitions and conditional compilation to allow trimming
  _all_ unused code in a given game

## 0.5.0 - Expected release: TBD

New features:

- Integrate a music player for 128K mode (see #3)
- RAGE1 Game Tutorial based on my own development of Famargon
- Full syntax checker for GDATA files, to allow better error reporting to
  the user (very related to the previous point :-) )

## Future development

- Generalized game data/code in alternate memory banks
- Sideview games, platformers, gravity (see #5)
- Multiplayer games (see #2)
- ...you name it...

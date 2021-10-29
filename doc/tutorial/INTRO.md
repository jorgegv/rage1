# Introduction to RAGE1

The main goal of RAGE1 is to allow you to develop a game writing the least possible code. We all know that writing code is fun, but it is much less fun to write the same code repeatedly. This was the main reason for the development of the engine: I started to write a game, and then I realized that I could write multiple games with similar play mechanics but different stories and plots, so I decided to refactor all common code in RAGE1.

The engine is written in C with some specific assembly parts. You can develop your game in C or ASM also, the engine will recognize both file types and compile them correctly; you just need to put them in the correct places.

For better optimization, the engine is not organized as a library but instead as a body of code that is fully compiled along with your game, and that configures itself with your game parameters. Several tools and Makefiles are included that process you game data files and generate the proper C code and configuration files for the engine so that the final result is your fully optimized game.

The main components of a RAGE1 game are:

- The RAGE1 engine: this is composed by several code folders, tools and build Makefiles that allow you to compile and run your game by just typing `make build && make run`
- Your game assets: these are all the customization items and elements that make your game: graphic tiles, enemy sprites, hero graphics, game map, behaviour rules and general game configuration
- Your custom game code: the engine has several hooks in critical places of the gameplay (e.g. menu screen, intro, game loop, game over and end game screens, etc.) that call whatever code you need to run at those places

A RAGE1 game thus consists mainly of two directories: `game_data` and `game_src`. Those directories contain the elements mentioned above (assets and code).

The third component (the RAGE1 engine) is used directly from its GIT repository: just clone the repo and you are ready to create/compile your game.


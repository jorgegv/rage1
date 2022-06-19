# Game Design and Structure

## General Design Procedure

The procedure that I followed with Famargon was the following:

1.  Think of an adventure idea or plot: make up a general story, think about
    the main characters, goals, possible enemies, items, etc.  You don't
    need to be too concise, just something to get you started.

2.  Make a draft of your hero graphics, items, enemies (paper)

3.  Draw a few (2 or 3) of the initial screens (paper) and connect them in a
    map

4.  Draw your graphics in some graphics tool (e.g.  GIMP, Photoshop), export
    them in a format that RAGE1 can load (PNG), define them in RAGE1 data
    files

5.  Create data files for the game map screens: add tiles, enemies, rules,
    etc.

6.  Test the game and continue adding elements (map screens, tiles, enemies,
    rules, items) to support your game story

7.  Repeat until you are satisfied with your game

## Directory Layout

Let's see what the directory structure would look like when developing a
game.  We will suppose our working directory is `src`, and the directory
structure below it would be similar to this:

```
src
├── famargon
│   ├── doc
│   ├── game_data
│   │   ├── btiles
│   │   ├── flow
│   │   ├── game_config
│   │   ├── heroes
│   │   ├── map
│   │   ├── png
│   │   └── sprites
│   ├── game_src
│   └── misc
└── rage1
```

As you can see, under directory `src` we have a dedicated directory for our
game (`famargon` for my game, you name yours :-) ), with some directories
inside it.  At the same level, we have the `rage1` directory, which is just
a clone of the RAGE1 GIT repository.

With this directory layout, you would do the following steps for building your game:

- Change to the `rage1` directory: `cd rage1`

- Run the build command setting your game directory as a target: `make build
  target_game=../famargon`

After a few minutes, your game will be compiled inside the `rage1` directory
into a  TAP file called `game.tap` which you can then distribute or use as
you wish.  After the `game.tap` file is created you can also type `make run`
and FUSE (the Free Unix Spectrum Emulator) will be used to load and run your
game from the TAP file.

Don't worry about the directory structure, you won't need to create it
manually: there are tools in RAGE1 that allow you to create a minimal but
fully functional game that compiles out of the box and that you can use to
build your game upon: you start with a minimal working game and starting
adding features and elements.

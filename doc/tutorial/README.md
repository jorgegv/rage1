# RAGE1 Game Development Tutorial

This document is a guide to game development with the RAGE1 engine.  RAGE1
stands for Retro Adventure Game Engine, release 1: it is a development kit
for adventure games running on the ZX Spectrum family of computers (48K and
128K models).

The general goal of RAGE1 is to allow you to focus in the design of your
game without writing more code than it is strictly needed: general gameplay,
puzzles, game rules, introductions, special actions, startup and ending
sequences, hero and enemy sprites, background graphics...  these are the
main unique things that define your game and that you should mostly worry
about, and let the engine do the boring work for you (moving hero and
enemies, checking conditions, etc.)

Users of this tutorial should be familiar with a Text Editor (e.g.  Notepad,
Vim, Emacs :-P ) and an image editor which can export images in PNG format
(e.g.  Gimp, MSPaint).  They should also be somewhat familiar with running
commands in the Command Line, but no compiler experience should be needed.

This document is a detailed walkthrough of the creation of a full game with
RAGE1, using the first phase of **Famargon** as an example (**Famargon** is
my little Spectrum family game).  My main goal is to provide a general
understanding of the process of developing a game with RAGE1, from the early
design phases to the finished game.

Any comment, addition, fix or whatever you want to add to this document is
very welcome.  You can mail me at `zx@jogv.es` or issue a Pull Request in
GitHub (preferred!)

Tutorial Table of Contents (WIP):

0. [Introduction to RAGE1](INTRO.md)
1. [Ensure RAGE1 requirements are installed and working](REQUIREMENTS.md)
2. [Game structure and design](SKELETON.md)
3. [Game story and goals](STORY.md)
4. [Design the hero](HERO.md)
5. [Design the screens](SCREENS.md)
6. [Create the decorations](BTILES.md)
7. [Design the map and move between screens](MAP.md)
8. [Add some enemies](ENEMIES.md)
9. [Add inventory items and manage inventory](INVENTORY.md)
10. [Add gameplay rules](RULES.md)
11. [Implement special game functions](FUNCTIONS.md)
12. [Add sound effects](SOUND.md)
13. [Compile for 128K](BUILD128.md)
14. [Adding music for 128K](MUSIC128.md)
15. [Using extra memory banks for game data](DATASETS.md)
16. [Using extra memory banks for game code](CODESETS.md)

_WARNING: This tutorial is a Work In Progress, so you can expect to find
broken links and sections still not written.  This warning will be removed
when the tutorial is finished._

**Special note for Windows users:** please accept my apologies in advance. 
My main development environment for RAGE1 is Linux, so this tutorial may
show a heavy bias towards the Linux way of doing things.  I will gladly
accept any comments, suggestions and pull requests for addressing
Windows-related concerns.

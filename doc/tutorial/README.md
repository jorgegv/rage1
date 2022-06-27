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

The procedure I followed with Famargon was roughly the following:

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

7.  Repeat until you are satisfied with your game - In short: start with a
    working small game, then continue adding things until you feel it's
    complete.

The chapters in this tutorial map to that procedure and are detailed in the
next section in this file.

Any comment, addition, fix or whatever you want to add to this document is
very welcome.  You can mail me at [`zx@jogv.es`](mailto:zx@jogv.es) or issue
a Pull Request in GitHub (preferred!)

_WARNING! This tutorial is a Work In Progress, so you can expect to find
broken links and sections still not written.  This warning will be removed
when the tutorial is finished._

**Special note for Windows users:** please accept my apologies in advance. 
My main development environment for RAGE1 is Linux, so this tutorial may
show a heavy bias towards the Linux way of doing things.  I will gladly
accept any comments, suggestions and pull requests for addressing
Windows-related concerns.

## Tutorial Table of Contents (WIP):

0. [Introduction to RAGE1](TUT000-INTRO.md)

1. [Ensure RAGE1 requirements are installed and working](TUT010-REQUIREMENTS.md)

2. [Game structure and design](TUT020-SKELETON.md)

3. [Game story and goals](TUT030-STORY.md) _[To be completed]_

4. [Design the hero](TUT040-HERO.md) _[To be completed]_

5. [Design the screens](TUT050-SCREENS.md) _[To be completed]_

6. [Create the decorations](TUT060-BTILES.md) _[To be completed]_

7. [Design the map and move between screens](TUT070-MAP.md) _[To be completed]_

8. [Add some enemies](TUT080-ENEMIES.md) _[To be completed]_

9. [Add inventory items and manage inventory](TUT090-INVENTORY.md) _[To be completed]_

10. [Add gameplay rules](TUT100-RULES.md) _[To be completed]_

11. [Implement special game functions](TUT110-FUNCTIONS.md) _[To be completed]_

12. [Add sound effects](TUT120-SOUND.md) _[To be completed]_

13. [Compile for 128K](TUT130-BUILD128.md) _[To be completed]_

14. [Adding music for 128K](TUT140-MUSIC128.md) _[To be completed]_

15. [Using extra memory banks for game data](TUT150-DATASETS.md) _[To be completed]_

16. [Using extra memory banks for game code](TUT160-CODESETS.md) _[To be completed]_


# RECIPES

The following describes common behaviours which are commonly used in
adventure games, and how you would implement within RAGE1.  It is not an
exhaustive guide with cut-and-paste examples, it is more of a reminder of
how those behaviours can be accomplished by using the library.

## Putting an item on a map screen

Item definition in the code, and detection, grabbing and showing in the
inventory while in the game, is automatic.

- Make sure the BTILE for the item has been defined

- Just add an ITEM line to the SCREEN definition in the map.  You'll need to
  reserve an item ID (a 0-15 integer) and decide its position on the screen.

(Check DATAGEN docs for the correct syntax and parameters)

## Jumping from one screen to another

Typical behaviour for going from the current screen to the next: when the
hero touches a special "exit screen" area, it swicthes to the screen that is
conected to that area

This is accomplished by using HOTZONES and FLOWGEN rules.  Let's assume you
want to implement the switching from Screen A to Screen B and vice versa.

- First, you would define a hotzone in Screen A, with a name and pixel
  coordinates (x,y,width and height).  This is the area in Screen A that
  takes you to Screen B

- Then you would do the same in Screen B, for the area that takes you back
  into Screen A

- Then you define a Game Loop FLOW rule in Screen A that checks if the hero
  is running over the Screen A hotzone.  If it is, it executes an action of
  type WARP_TO_SCREEN to switch into Screen B

- Then again you define the reciprocal Game Loop rules in Screen B for the
  Screen B hotzone that takes you to Screen A

- The hotzones can be decorated with some DECORATION btiles, in case they
  are not the obvious exit places in the screens.  The decoration and the
  hotzones are overlaid.

The DATAGEN code would be similar to this:

```
BEGIN_SCREEN
	NAME ScreenA
(...)
	// optional: decoration
        DECORATION      NAME=Stairs     BTILE=Stairs ROW=16 COL=10 ACTIVE=1
	// hotzone for screen warping
        HOTZONE         NAME=WarpToScreenB     X=88 Y=136 PIX_WIDTH=8 PIX_HEIGHT=16 ACTIVE=1
(...)
END_SCREEN
```

And the FLOWGEN code would be like:

```
BEGIN_RULE
        SCREEN  ScreenA
        WHEN    GAME_LOOP
        CHECK   HERO_OVER_HOTZONE WarpToScreenB
        DO      WARP_TO_SCREEN DEST_SCREEN=ScreenB DEST_HERO_X=100 DEST_HERO_Y=136
END_RULE
```

The reciprocal zone and rule from Screen B to SCreen A would be similar.

(As always, check the exhaustive syntax guide in DATAGEN docs)

## Automatically drop an item somewhere in the game

Let's say you have an item in your game which appears on Screen A (and can
be grabbed there), but it should be taken to some place in Screen B, in
order to activate some game condition condition.

When you grab the item in Screen A, it should disappear from the screen (and
appear in your inventory), and when you take into the destination place, it
should appear dropped there and disappear from the inventory.

You would do it like this:

- First you would define an item in Screen A using the procedure mentioned
  in a previous recipe.  With this, you get the regular item management

- Then you define a hotzone in Screen B (which we will call the "holder"
  hotzone for that object)

- Optionally, you can overlay a DECORATION btile over the holder hotzone, in
  order to give the player some hint that something should be brought there.

- Also, you define an OBSTACLE in Screen B, which overlaps with the holder
  hotzone, with an associated BTILE which is identical to the one from the
  item you are managing, and you configure it in ACTIVE=0 initial state.

  BEWARE! The BTILE for the dropped object CANNOT be the same as the
  ITEM's!! The item btile is stored in the home dataset (because it is an
  item), but the screen btiles are always referred to the dataset where the
  screen is defined.

- Then you define a Game Loop RULE in Screen B that does the following:
  - IF:
    - The hero is over the Holder hotzone
    - AND it has the item in his/her inventory
  - THEN:
    - Activate the BTILE in Screen B (this makes the item appear where it
      should be dropped - It is not the item, it is an obstacle with
      a similar/equal tile, but the player does not know that :-) )
    - AND Deactivate the (optional) holder decoration
    - AND Remove the item from the inventory
    - AND Set whatever flag you need to note that the item has been dropped
    in its place

The DATAGEN code would be like:

```
BEGIN_SCREEN
	NAME ScreenA
(...)
	// of course, ITEM and HOLDER need not be in the same screen
        ITEM            NAME=Lapiz      BTILE=Lapiz     ROW=20 COL=2 ITEM_INDEX=4
(...)
END_SCREEN

BEGIN_SCREEN
	NAME ScreenB
(...)
        HOTZONE         NAME=LapizHolder        X=152 y=112 PIX_WIDTH=24 PIX_HEIGHT=16 ACTIVE=1
        DECORATION      NAME=LapizHolder        BTILE=LapizHolder       ROW=14 COL=20 ACTIVE=1
        OBSTACLE        NAME=Lapiz              BTILE=Lapiz             ROW=14 COL=20 ACTIVE=0
(...)
END_SCREEN
```

And the FLOWGEN code would be like:

```
BEGIN_RULE
        SCREEN  ScreenB
        WHEN    GAME_LOOP
        CHECK   HERO_OVER_HOTZONE LapizHolder
        CHECK   ITEM_IS_OWNED 0x10
        DO      DISABLE_BTILE LapizHolder
        DO      ENABLE_BTILE Lapiz
        DO      REMOVE_FROM_INVENTORY 0x10
END_RULE
```

Remember that ITEM_ID=bit_number and ITEM_MASK=bit_mask, so for ITEM_ID=4,
ITEM_MASK=0x10 (the fourth bit is 1)

(As always, check the exhaustive syntax guide in DATAGEN docs)

## Action at a distance: enabling/disabling an element from another screen

Acting (enabling/disabling) an element (btile/sprite, etc.) when the
condition to check and the element are on the same screen is easy: it can be
done with just a game loop FLOW rule check and the associated actions.

But when the condition is checked on Screen A and the element to act upon is
on Screen B, it is slightly more complicated: you need to pass a bit of
information (= the condition that was met) from Screen A to Screen B.

And this is exactly what SCREEN FLAGS are for.

The procedure would be the following:

- In Screen A, setup a GAME_LOOP rule to check for the condition to be met
- If the condition is met, set a SCREEN FLAG in Screen B (where the element
  to be acted upon resides). You can use a SET_SCREEN_FLAG action to do
  this.
- In Screen B, setup an ENTER_SCREEN rule that checks the SCREEN FLAG you
  used in the previous rule in Screen A (use a SCREEN_FLAG_IS_SET check)
- If the flag is active, act upon the (now local) element (enable/disable
  the btile, enemy, etc.), and also, RESET the screen flag to avoid further
  processing (use a RESET_SCREEN_FLAG action)

With this schema, you are passing 1 bit of information from Screen A to
Screen B.  Both rules have to agree on using the same SCREEN FLAG number, of
course.

## Having an open/closed door that allows entering a room

You may want to have two rooms communicated by a door that can be open or
closed during the game, so that the hero can cross it if it is open, but not
if it is closed (standard door behaviour :-)

How to get this effect:

- Define the HOTZONEs that communicate the screens as usual, create them for
  the "open" position (i.e.  allows crossing the door and going from one
  screen to the next)

- Define 2 different door tiles with the size of the hole that communicates
  both screens, one for "open" state and another one for "closed".

- In the map SCREEN definition, position both tiles on the same spot,
  covering the screen-switching hotzone. The "closed" door btile must be
  defined as type OBSTACLE (the hero can't passthrough it), and the "open"
  door btile must be defined as DECORATION (the hero can walk over it)

- Make sure both tiles on the SCREEN have different names (e.g. ending in
  ".._open" or ".._closed"), and also have attribute CAN_CHANGE_STATE=1 and
  ACTIVE=0/1, depending on initial state.

- With the previous setup, you can open/close the door by enabling/disabling
  the proper tiles by name using FLOW rules in the normal way.  Since the
  "closed" tile is of type OBSTACLE, it won't allow he hero to pass, but
  when it's "open" the tile is a DECORATION and the hero will walk over it
  and reach the hotzone to switch screen.

If you are generating the game map with MAPGEN and with automatic
screen-switching HOTZONEs (recommended!), the simplest way to accomplish the
previous workflow is to draw the map without door tiles, leaving empty space
at their positions (so the auto hotzones get detected and generated).  Then
manually add the open/closed door tiles with PATCH_SCREEN sections in patch
files under `game_data/patches/map`.  Patching allows you to regenerate the
map anytime without overwriting your additions.

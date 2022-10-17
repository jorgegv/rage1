# RAGE1 In-Game Events System

There was a need to be able to run some actions in response to certain
events during the game. These could have been implemented as FLOW rules to
be run during GAME_LOOP, but this had two big cons:

- First, there was not a global table, so these events needed to be
  configured on each screen they had to be run. This is inefficient with
  regards to memory usage, since the same data would be repeated in several
  screens.

- And second, running them in GAME_LOOP is inefficient performance-wise,
  since all these rules would be run in every game loop. This does not scale
  to a big number of rules and heavily affects game performance.

To solve the aforementioned problems, a new event system has been
implemented, with the following characteristics:

- It is global, that is, you configure it once for all the game screens
  (solving the first problem)

- It is run exclusively when there are events available to be processed: the
  game loop only runs this table if the `game_state.game_events` field is
  not zero.  This means that most of the time this rule table is not being
  executed and thus has nos impact in game performance (solving the second
  problem)

- As a bonus, it is implemented as a special FLOW table, so it is configured
  using FLOW rule syntax and we can reuse all the checks and actions
  available for writing FLOW rules.

## How to react to events

You just write a FLOW rule file where you add the special event rules. The
suggested place and file name is `flow/Events.gdata` under `game_data`
directory.

The syntax would be almost the same than for a regular rule associated to a
screen:

```
BEGIN_RULE
	SCREEN	__EVENTS__
	CHECK	EVENT_HAS_HAPPENED E_ENEMY_WAS_HIT
	DO	PLAY_SOUND SOUND_ENEMY_HIT
END_RULE
```

There are some special considerations for these rules:

- The screen associated to event rules must be the reserved name
  `__EVENTS__`. No screen may be defined with that name (DATAGEN fails if
  you try to do it), so you are safe.

- A `WHEN` clause is not needed, and it is ignored if provided.

- You can filter the event that has happened by using the new FLOW check
  EVENT_HAS_HAPPENED (see below for the complete list of events available). 
  You can also have no `CHECK` clauses in the rule, in which case the
  actions will be run whenever _any_ event happens.

- You can add also additional `CHECK` clauses as needed if you want to
  filter more: e.g.  you may be interested in doing something only if some
  event happens on a given screen.

- You can have one or more `DO` clauses as is usual in FLOW rules, so that
  different actions are triggered on the same conditions.

## Available events

The full list of available events is:

- `E_HERO_WAS_HIT`: the hero was hit by an enemy, but it did not die as a
  result. This event is generated when using the special `DAMAGE_MODE` hero
  configuration. If using the "enemy touch kills you" simple mode, this
  event is not generated, see below.

- `E_ENEMY_WAS_HIT`: an enemy was hit by a bullet and died.

- `E_ITEM_WAS_GRABBED`: the hero grabbed an item.

- `E_CRUMB_WAS_GRABBED`: the hero grabbed a crumb.

- `E_HERO_DIED`: the hero was hit by an enemy in simple damage mode, and
  died as a result.

- `E_BULLET_WAS_SHOT`: the hero shot a bullet.

This is the exhaustive list of events, and new events will be added to it as
they are added to the engine.

## Example Usage

You can check the `Events.gdata` file in the `default` game to see how the
event system can be configured.

As an example (and a way of testing the system!), all in-game sounds were
migrated to this event system, so that they can be fully configured by the
user now.

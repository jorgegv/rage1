////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is ublished under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _FLOW_H
#define _FLOW_H

#include <arch/spectrum.h>

// flow rule check constants
// always update RULE_CHECK_MAX when adding new checks!
#define RULE_CHECK_GAME_FLAG_IS_SET		0
#define RULE_CHECK_GAME_FLAG_IS_RESET		1
#define RULE_CHECK_LOOP_FLAG_IS_SET		2
#define RULE_CHECK_LOOP_FLAG_IS_RESET		3
#define RULE_CHECK_USER_FLAG_IS_SET		4
#define RULE_CHECK_USER_FLAG_IS_RESET		5
#define RULE_CHECK_LIVES_EQUAL			6
#define RULE_CHECK_LIVES_MORE_THAN		7
#define RULE_CHECK_LIVES_LESS_THAN		8
#define RULE_CHECK_ENEMIES_ALIVE_EQUAL		9
#define RULE_CHECK_ENEMIES_ALIVE_MORE_THAN	10
#define RULE_CHECK_ENEMIES_ALIVE_LESS_THAN	11
#define RULE_CHECK_ENEMIES_KILLED_EQUAL		12
#define RULE_CHECK_ENEMIES_KILLED_MORE_THAN	13
#define RULE_CHECK_ENEMIES_KILLED_LESS_THAN	14
#define RULE_CHECK_CALL_CUSTOM_FUNCTION		15
#define RULE_CHECK_ITEM_IS_OWNED		16

#define RULE_CHECK_MAX				16

// flow rule action constants
// always update RULE_ACTION_MAX when adding new actions!
#define RULE_ACTION_SET_USER_FLAG		0
#define RULE_ACTION_RESET_USER_FLAG		1
#define RULE_ACTION_PLAY_SOUND			2
#define RULE_ACTION_INC_LIVES			3
#define RULE_ACTION_CALL_CUSTOM_FUNCTION	4
#define RULE_ACTION_END_OF_GAME			5
#define RULE_ACTION_ACTIVATE_EXIT_ZONES		6
#define RULE_ACTION_ENABLE_HOTZONE		7
#define RULE_ACTION_DISABLE_HOTZONE		8

#define RULE_ACTION_MAX				8

struct flow_rule_check_s {
    uint8_t type;
    union {
        uint16_t					unused;		// for checks that do not need data
        struct { uint16_t	flag; }			flag_state;	// USER_FLAG_*, GAME_FLAG_*, LOOP_FLAG_*
        struct { uint8_t	count; }		lives;		// INC_LIVES
        struct { uint16_t	count; }		enemies;	// ENEMIES_ALIVE_*, ENEMIES_KILLED_*
        struct { uint8_t	(*function)(void); }	custom;		// CALL_CUSTOM_FUNCTION
        struct { uint16_t	item_id; }		item;		// ITEM_IS_OWNED
    } data;
};

struct flow_rule_action_s {
    uint8_t type;
    union {
        uint16_t					unused;		// for actions that do not need data
        struct { uint8_t	count; }		lives;		// INC_LIVES
        struct { uint8_t	sound_id; }		play_sound;	// PLAY_SOUND
        struct { uint16_t	flag; }			user_flag;	// SET_USER_FLAG, RESET_USER_FLAG
        struct { uint16_t	count; }		enemies;	// ENEMIES_ALIVE_*, ENEMIES_KILLED_*
        struct { void		(*function)(void); }	custom;		// CALL_CUSTOM_FUNCTION
        struct { uint8_t	num_hotzone; }		hotzone;	// ENABLE/DISABLE_HOTZONE
    } data;
};

// data definition for a rule
struct flow_rule_s {
    // what to check
    struct flow_rule_check_s check;
    // what to do if checks are all successful
    struct flow_rule_action_s action;
};

struct flow_rule_table_s {
    uint8_t num_rules;
    struct flow_rule_s **rules;
};

// executes user flow rules
void check_flow_rules(void);

#endif //_FLOW_H

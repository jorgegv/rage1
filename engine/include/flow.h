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
#define RULE_CHECK_USER_FLAG_IS_SET		1

#define RULE_CHECK_MAX				1

// flow rule action constants
// always ipdate RULE_ACTION_MAX when adding new actions!
#define RULE_ACTION_SET_USER_FLAG		0
#define RULE_ACTION_RESET_USER_FLAG		1
#define RULE_ACTION_PLAY_SOUND			2

#define RULE_ACTION_MAX				2

// data definition for a rule
struct flow_rule_s {

    // what to check
    uint8_t check;
    union {
        struct { uint16_t flag; }	flag_is_set;
    } check_data;

    // what to do if check successful
    uint8_t action;
    union {
        struct { uint8_t sound_id; }	play_sound;	// PLAY_SOUND
        struct { uint16_t flag; }	user_flag;	// SET_USER_FLAG, RESET_USER_FLAG
    } action_data;

};

struct flow_rule_table_s {
    uint8_t num_rules;
    struct flow_rule_s **rules;
};

struct flow_info_s {
        struct flow_rule_table_s enter_screen;
        struct flow_rule_table_s exit_screen;
        struct flow_rule_table_s hero_hit;
        struct flow_rule_table_s enemy_hit;
        struct flow_rule_table_s item_grabbed;
        struct flow_rule_table_s game_loop;
};

// executes user flow rules
void check_flow_rules(void);

#endif //_FLOW_H

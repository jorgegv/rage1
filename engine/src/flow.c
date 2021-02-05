////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is ublished under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include "flow.h"
#include "game_state.h"
#include "beeper.h"
#include "hero.h"
#include "hotzone.h"
#include "map.h"

#include "debug.h"

// Dispatch tables for rule checks and actions
typedef uint8_t (*rule_check_fn_t)( struct flow_rule_check_s * );
typedef void (*rule_action_fn_t)( struct flow_rule_action_s * );

extern rule_check_fn_t rule_check_fn[];
extern rule_action_fn_t rule_action_fn[];

// executes a complete rule table
void run_flow_rule_table( struct flow_rule_table_s *t ) {
    // beware Z80 optimizations!  The rule table is an ordered list, so it
    // has to be run in order from 0 to (num_rules-1)
    uint8_t i,j;
    static struct flow_rule_check_s *check;
    static struct flow_rule_action_s *action;
    for ( i = 0; i < t->num_rules; i++ ) {
        struct flow_rule_s *r = t->rules[i];
        // run the checks in order, return as soon as one returns false
        for ( j = 0; j < r->num_checks; j++ ) {
            check = &r->checks[j];
            if ( ! rule_check_fn[ check->type ]( check ) )
                goto next_rule;
        }
        // if we reach here, all checks were true; run the actions in order
        for ( j = 0; j < r->num_actions; j++ ) {
            action = &r->actions[j];
            rule_action_fn[ action->type ]( action );
        }
    next_rule:
    }
}

// check_flow_rules: execute rules in flowgen data tables for the current
// screen.  See documentation for implementation details
void check_flow_rules(void) {

    ////////////////////////////////////////////////////////
    // WHEN_ENTER_SCREEN and WHEN_EXIT_SCREEN rules
    ////////////////////////////////////////////////////////
    
    if ( GET_LOOP_FLAG( F_LOOP_ENTER_SCREEN ) ) {
        // run EXIT_SCREEN rules for the previous screen
        // but skip if game just started and this is the first game loop run
        if ( ! GET_GAME_FLAG( F_GAME_START ) )
            run_flow_rule_table( &map[ game_state.previous_screen ].flow_data.rule_tables.exit_screen );
        // run ENTER_SCREEN rules
        run_flow_rule_table( &map[ game_state.current_screen ].flow_data.rule_tables.enter_screen );
    }

    ////////////////////////////////////////////////////////
    // WHEN_GAME_LOOP rules
    ////////////////////////////////////////////////////////

    run_flow_rule_table( &map[ game_state.current_screen ].flow_data.rule_tables.game_loop );

}

////////////////////////////////////////////////////////////////////
// rules: functions for 'check' dispatch table
// prototype: 
//   uint8_t do_rule_check_xxxx( struct flow_rule_check_s *check )
////////////////////////////////////////////////////////////////////

uint8_t do_rule_check_game_flag_set( struct flow_rule_check_s *check ) {
    return ( GET_GAME_FLAG( check->data.flag_state.flag ) ? 1 : 0 );
}

uint8_t do_rule_check_game_flag_reset( struct flow_rule_check_s *check ) {
    return ( GET_GAME_FLAG( check->data.flag_state.flag ) ? 0 : 1 );
}

uint8_t do_rule_check_loop_flag_set( struct flow_rule_check_s *check ) {
    return ( GET_LOOP_FLAG( check->data.flag_state.flag ) ? 1 : 0 );
}

uint8_t do_rule_check_loop_flag_reset( struct flow_rule_check_s *check ) {
    return ( GET_LOOP_FLAG( check->data.flag_state.flag ) ? 0 : 1 );
}

uint8_t do_rule_check_user_flag_set( struct flow_rule_check_s *check ) {
    return ( GET_USER_FLAG( check->data.flag_state.flag ) ? 1 : 0 );
}

uint8_t do_rule_check_user_flag_reset( struct flow_rule_check_s *check ) {
    return ( GET_USER_FLAG( check->data.flag_state.flag ) ? 0 : 1 );
}

uint8_t do_rule_check_lives_equal( struct flow_rule_check_s *check ) {
    return ( game_state.hero.num_lives == check->data.lives.count ? 1 : 0 );
}

uint8_t do_rule_check_lives_more_than( struct flow_rule_check_s *check ) {
    return ( game_state.hero.num_lives > check->data.lives.count ? 1 : 0 );
}

uint8_t do_rule_check_lives_less_than( struct flow_rule_check_s *check ) {
    return ( game_state.hero.num_lives < check->data.lives.count ? 1 : 0 );
}

uint8_t do_rule_check_enemies_alive_equal( struct flow_rule_check_s *check ) {
    return ( game_state.enemies_alive == check->data.enemies.count ? 1 : 0 );
}

uint8_t do_rule_check_enemies_alive_more_than( struct flow_rule_check_s *check ) {
    return ( game_state.enemies_alive > check->data.enemies.count ? 1 : 0 );
}

uint8_t do_rule_check_enemies_alive_less_than( struct flow_rule_check_s *check ) {
    return ( game_state.enemies_alive < check->data.enemies.count ? 1 : 0 );
}

uint8_t do_rule_check_enemies_killed_equal( struct flow_rule_check_s *check ) {
    return ( game_state.enemies_killed == check->data.enemies.count ? 1 : 0 );
}

uint8_t do_rule_check_enemies_killed_more_than( struct flow_rule_check_s *check ) {
    return ( game_state.enemies_killed > check->data.enemies.count ? 1 : 0 );
}

uint8_t do_rule_check_enemies_killed_less_than( struct flow_rule_check_s *check ) {
    return ( game_state.enemies_killed < check->data.enemies.count ? 1 : 0 );
}

uint8_t do_rule_check_call_custom_function( struct flow_rule_check_s *check ) {
    return check->data.custom.function();
}

uint8_t do_rule_check_item_is_owned( struct flow_rule_check_s *check ) {
    return ( INVENTORY_HAS_ITEM( &game_state.inventory, check->data.item.item_id ) ? 1 : 0 );
}

////////////////////////////////////////////////////////////////////
// rules: functions for 'action' dispatch table
// prototype:
//   void do_rule_action_xxxx( struct flow_rule_action_s *action )
////////////////////////////////////////////////////////////////////

void do_rule_action_set_user_flag( struct flow_rule_action_s *action ) {
    SET_USER_FLAG( action->data.user_flag.flag );
}

void do_rule_action_reset_user_flag( struct flow_rule_action_s *action ) {
    RESET_USER_FLAG( action->data.user_flag.flag );
}

void do_rule_action_play_sound( struct flow_rule_action_s *action ) {
    beep_fx( action->data.play_sound.sound_id );
}

void do_rule_action_inc_lives( struct flow_rule_action_s *action ) {
    game_state.hero.num_lives += action->data.lives.count;
    hero_update_lives_display();
}

void do_rule_action_call_custom_function( struct flow_rule_action_s *action ) {
    action->data.custom.function();
}

void do_rule_action_end_of_game( struct flow_rule_action_s *action ) {
    SET_GAME_FLAG( F_GAME_END );
}

void do_rule_action_activate_exit_zones( struct flow_rule_action_s *action ) {
    hotzone_activate_all_endofgame_zones();
}

void do_rule_action_enable_hotzone( struct flow_rule_action_s *action ) {
    SET_HOTZONE_FLAG( map[ game_state.current_screen ].hotzone_data.hotzones[ action->data.hotzone.num_hotzone ],
        F_HOTZONE_ACTIVE );
}

void do_rule_action_disable_hotzone( struct flow_rule_action_s *action ) {
    RESET_HOTZONE_FLAG( map[ game_state.current_screen ].hotzone_data.hotzones[ action->data.hotzone.num_hotzone ],
        F_HOTZONE_ACTIVE );
}

// dispatch tables for check and action functions

// Table of check functions. The 'check' value from the rule is used to
// index into this table and execute the appropriate function
rule_check_fn_t rule_check_fn[ RULE_CHECK_MAX + 1 ] = {
    do_rule_check_game_flag_set,
    do_rule_check_game_flag_reset,
    do_rule_check_loop_flag_set,
    do_rule_check_loop_flag_reset,
    do_rule_check_user_flag_set,
    do_rule_check_user_flag_reset,
    do_rule_check_lives_equal,
    do_rule_check_lives_more_than,
    do_rule_check_lives_less_than,
    do_rule_check_enemies_alive_equal,
    do_rule_check_enemies_alive_more_than,
    do_rule_check_enemies_alive_less_than,
    do_rule_check_enemies_killed_equal,
    do_rule_check_enemies_killed_more_than,
    do_rule_check_enemies_killed_less_than,
    do_rule_check_call_custom_function,
    do_rule_check_item_is_owned,
};

// Table of action functions.  The 'action' value from the rule is used to
// index into this table and execute the appropriate function
rule_action_fn_t rule_action_fn[ RULE_ACTION_MAX + 1 ] = {
    do_rule_action_set_user_flag,
    do_rule_action_reset_user_flag,
    do_rule_action_play_sound,
    do_rule_action_inc_lives,
    do_rule_action_call_custom_function,
    do_rule_action_end_of_game,
    do_rule_action_activate_exit_zones,
    do_rule_action_enable_hotzone,
    do_rule_action_disable_hotzone,
};

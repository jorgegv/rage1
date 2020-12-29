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

// Dispatch tables for rule checks and actions
typedef uint8_t (*rule_check_fn_t)( struct flow_rule_s * );
typedef void (*rule_action_fn_t)( struct flow_rule_s * );

extern rule_check_fn_t rule_check_fn[];
extern rule_action_fn_t rule_action_fn[];

// executes a complete rule table
void run_flow_rule_table( struct flow_rule_table_s *t ) {
    // beware Z80 optimizations!  The rule table is an ordered list, so it
    // has to be run in order from 0 to (num_rules-1)
    uint8_t i;
    for ( i = 0; i < t->num_rules; i++ ) {
        struct flow_rule_s *r = t->rules[ i ];
        if ( rule_check_fn[ r->check ]( r ) )
            rule_action_fn[ r->action ]( r );
    }
}

// check_flow_rules: execute rules in flowgen data tables for the current
// screen.  See documentation for implementation details
void check_flow_rules(void) {

    ////////////////////////////////////////////////////////
    // WHEN_ENTER_SCREEN and WHEN_EXIT_SCREEN rules
    ////////////////////////////////////////////////////////
    
    if ( GET_GAME_FLAG( F_GAME_ENTER_SCREEN ) ) {
        // run EXIT_SCREEN rules for the previous screen
        // but skip if game just started and this is the first game loop run
        if ( ! GET_GAME_FLAG( F_GAME_START ) )
            run_flow_rule_table( &map[ game_state.previous_screen ].flow_data.exit_screen );
        // run ENTER_SCREEN rules
        run_flow_rule_table( &map[ game_state.current_screen ].flow_data.enter_screen );
    }

    ////////////////////////////////////////////////////////
    // WHEN_GAME_LOOP rules
    ////////////////////////////////////////////////////////

    run_flow_rule_table( &map[ game_state.current_screen ].flow_data.game_loop );

}

////////////////////////////////////////////////////////////////////
// rules: functions for 'check' dispatch table
// prototype: 
//   uint8_t do_rule_check_xxxx( struct flow_rule_s *r )
////////////////////////////////////////////////////////////////////

uint8_t do_rule_check_game_flag_set( struct flow_rule_s *r ) {
    return ( GET_GAME_FLAG( r->check_data.flag_is_set.flag ) ? 1 : 0 );
}

uint8_t do_rule_check_user_flag_set( struct flow_rule_s *r ) {
    return ( GET_USER_FLAG( r->check_data.flag_is_set.flag ) ? 1 : 0 );
}

////////////////////////////////////////////////////////////////////
// rules: functions for 'action' dispatch table
// prototype:
//   void do_rule_action_xxxx( struct flow_rule_s *r )
////////////////////////////////////////////////////////////////////

void do_rule_action_set_user_flag( struct flow_rule_s *r ) {
    SET_USER_FLAG( r->action_data.user_flag.flag );
}

void do_rule_action_reset_user_flag( struct flow_rule_s *r ) {
    RESET_USER_FLAG( r->action_data.user_flag.flag );
}

void do_rule_action_play_sound( struct flow_rule_s *r ) {
    beep_fx( r->action_data.play_sound.sound_id );
}

// dispatch tables for check and action functions

// Table of check functions. The 'check' value from the rule is used to
// index into this table and execute the appropriate function
rule_check_fn_t rule_check_fn[ RULE_CHECK_MAX + 1 ] = {
    do_rule_check_game_flag_set,
    do_rule_check_user_flag_set,
};

// Table of action functions.  The 'action' value from the rule is used to
// index into this table and execute the appropriate function
rule_action_fn_t rule_action_fn[ RULE_ACTION_MAX + 1 ] = {
    do_rule_action_set_user_flag,
    do_rule_action_reset_user_flag,
    do_rule_action_play_sound,
};


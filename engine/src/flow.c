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

// table of check functions.  Rule check value is used to index into this
// table and execute the appropriate function
uint8_t (*rule_check_function)( struct flow_rule_s * ) [ RULE_CHECK_MAX ];

// table of action functions.  Rule action value is used to index into this
// table and execute the appropriate function
void (*rule_action_function)( struct flow_rule_s * ) [ RULE_ACTION_MAX ];

// executes a complete rule table
void run_flow_rule_table( struct flow_rule_table_s *t ) {
    // beware Z80 optimizations!  The rule table is an ordered list, so it
    // has to be run in order from 0 to (num_rules-1)
    uint8_t i;
    for( i = 0; i < t->num_rules; i++ ) {
        static struct flow_rule_s *r;
        r = t->rules[ i ];
        if ( rule_check_function[ r->check ]( r ) )
            rule_action_function[ r->action ]( r );
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

}


////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is ublished under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include "rage1/flow.h"
#include "rage1/game_state.h"
#include "rage1/sound.h"
#include "rage1/hero.h"
#include "rage1/hotzone.h"
#include "rage1/map.h"
#include "rage1/btile.h"
#include "rage1/debug.h"
#include "rage1/screen.h"
#include "rage1/collision.h"
#include "rage1/inventory.h"
#include "rage1/dataset.h"

#include "game_data.h"

// disable "unreferenced function argument" warning, there are some
// functions here that don't use their parameter
# pragma disable_warning 85

// Dispatch tables for rule checks and actions
typedef uint8_t (*rule_check_fn_t)( struct flow_rule_check_s * ) __z88dk_fastcall;
typedef void (*rule_action_fn_t)( struct flow_rule_action_s * ) __z88dk_fastcall;

extern rule_check_fn_t rule_check_fn[];
extern rule_action_fn_t rule_action_fn[];

// executes a complete rule table
void run_flow_rule_table( struct flow_rule_table_s *t ) {
    // beware Z80 optimizations!  The rule table is an ordered list, so it
    // has to be run in order from 0 to (num_rules-1)
    uint8_t i,j;
    struct flow_rule_check_s *check;
    struct flow_rule_action_s *action;
    for ( i = 0; i < t->num_rules; i++ ) {
        struct flow_rule_s *r = t->rules[i];
        // run the checks in order, skip to next rule as soon as one check returns false
        for ( j = 0; j < r->num_checks; j++ ) {
            check = &r->checks[j];
            if ( ! rule_check_fn[ check->type ]( check ) )
                goto next_rule;
        }
        // if we reach here, all checks were true, or there were no checks; run the actions in order
        for ( j = 0; j < r->num_actions; j++ ) {
            action = &r->actions[j];
            rule_action_fn[ action->type ]( action );
        }
    next_rule:
        continue;
    }
}

// check_flow_rules: execute rules in flowgen data tables for the current
// screen.  See documentation for implementation details
void check_flow_rules(void) {

    ////////////////////////////////////////////////////////
    // WHEN_GAME_LOOP rules
    ////////////////////////////////////////////////////////

    if ( game_state.current_screen_ptr->flow_data.rule_tables.game_loop.num_rules )
        run_flow_rule_table( &game_state.current_screen_ptr->flow_data.rule_tables.game_loop );

    ////////////////////////////////////////////////////////
    // WHEN_ENTER_SCREEN and WHEN_EXIT_SCREEN rules
    ////////////////////////////////////////////////////////
    
    // run ENTER_SCREEN rules for the initial screen at game start
    if ( GET_GAME_FLAG( F_GAME_START ) ) {
        if ( game_state.current_screen_ptr->flow_data.rule_tables.enter_screen.num_rules )
            run_flow_rule_table( &game_state.current_screen_ptr->flow_data.rule_tables.enter_screen );
    }

    // run rules when switching screens
    if ( GET_LOOP_FLAG( F_LOOP_WARP_TO_SCREEN ) ) {
        // run EXIT_SCREEN rules for the previous screen
        if ( game_state.current_screen_ptr->flow_data.rule_tables.exit_screen.num_rules )
            run_flow_rule_table( &game_state.current_screen_ptr->flow_data.rule_tables.exit_screen );

        // switch screen
        // game_state.current_screen_ptr is updated here!
        game_state_switch_to_next_screen();

        // run ENTER_SCREEN rules
        if ( game_state.current_screen_ptr->flow_data.rule_tables.enter_screen.num_rules )
            run_flow_rule_table( &game_state.current_screen_ptr->flow_data.rule_tables.enter_screen );
    }
}

////////////////////////////////////////////////////////////////////
// rules: functions for 'check' dispatch table
// prototype: 
//   uint8_t do_rule_check_xxxx( struct flow_rule_check_s *check )
////////////////////////////////////////////////////////////////////

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_GAME_FLAG_IS_SET
uint8_t do_rule_check_game_flag_is_set( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( GET_GAME_FLAG( check->data.flag_state.flag ) ? 1 : 0 );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_GAME_FLAG_IS_RESET
uint8_t do_rule_check_game_flag_is_reset( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( GET_GAME_FLAG( check->data.flag_state.flag ) ? 0 : 1 );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_LOOP_FLAG_IS_SET
uint8_t do_rule_check_loop_flag_is_set( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( GET_LOOP_FLAG( check->data.flag_state.flag ) ? 1 : 0 );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_LOOP_FLAG_IS_RESET
uint8_t do_rule_check_loop_flag_is_reset( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( GET_LOOP_FLAG( check->data.flag_state.flag ) ? 0 : 1 );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_USER_FLAG_IS_SET
uint8_t do_rule_check_user_flag_is_set( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( GET_USER_FLAG( check->data.flag_state.flag ) ? 1 : 0 );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_USER_FLAG_IS_RESET
uint8_t do_rule_check_user_flag_is_reset( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( GET_USER_FLAG( check->data.flag_state.flag ) ? 0 : 1 );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_LIVES_EQUAL
uint8_t do_rule_check_lives_equal( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( game_state.hero.num_lives == check->data.lives.count ? 1 : 0 );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_LIVES_MORE_THAN
uint8_t do_rule_check_lives_more_than( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( game_state.hero.num_lives > check->data.lives.count ? 1 : 0 );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_LIVES_LESS_THAN
uint8_t do_rule_check_lives_less_than( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( game_state.hero.num_lives < check->data.lives.count ? 1 : 0 );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_ENEMIES_ALIVE_EQUAL
uint8_t do_rule_check_enemies_alive_equal( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( game_state.enemies_alive == check->data.enemies.count ? 1 : 0 );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_ENEMIES_ALIVE_MORE_THAN
uint8_t do_rule_check_enemies_alive_more_than( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( game_state.enemies_alive > check->data.enemies.count ? 1 : 0 );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_ENEMIES_ALIVE_LESS_THAN
uint8_t do_rule_check_enemies_alive_less_than( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( game_state.enemies_alive < check->data.enemies.count ? 1 : 0 );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_ENEMIES_KILLED_EQUAL
uint8_t do_rule_check_enemies_killed_equal( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( game_state.enemies_killed == check->data.enemies.count ? 1 : 0 );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_ENEMIES_KILLED_MORE_THAN
uint8_t do_rule_check_enemies_killed_more_than( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( game_state.enemies_killed > check->data.enemies.count ? 1 : 0 );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_ENEMIES_KILLED_LESS_THAN
uint8_t do_rule_check_enemies_killed_less_than( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( game_state.enemies_killed < check->data.enemies.count ? 1 : 0 );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_CALL_CUSTOM_FUNCTION
uint8_t do_rule_check_call_custom_function( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return check_custom_functions[ check->data.custom.function_id ]();
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_ITEM_IS_OWNED
uint8_t do_rule_check_item_is_owned( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( INVENTORY_HAS_ITEM( &game_state.inventory, check->data.item.item_id ) ? 1 : 0 );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_HERO_OVER_HOTZONE
uint8_t do_rule_check_hero_over_hotzone( struct flow_rule_check_s *check ) __z88dk_fastcall {
    struct hotzone_info_s *hz;

    hz = &game_state.current_screen_ptr->hotzone_data.hotzones[ check->data.hotzone.num_hotzone ];

    // if the hotzone has a state, consider if it is active or not
    if ( hz->state_index != ASSET_NO_STATE )
        return ( GET_HOTZONE_FLAG( game_state.current_screen_asset_state_table_ptr[ hz->state_index ].asset_state, F_HOTZONE_ACTIVE ) &&
            collision_check( &game_state.hero.position, &hz->position )
            );
    else
        // if the hotzone does not have a state, it is always active
        return collision_check( &game_state.hero.position, &hz->position );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_SCREEN_FLAG_IS_SET
uint8_t do_rule_check_screen_flag_is_set( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( GET_SCREEN_FLAG( game_state.current_screen_asset_state_table_ptr[ SCREEN_STATE_INDEX ].asset_state, check->data.flag_state.flag ) ? 1 : 0 );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_SCREEN_FLAG_IS_RESET
uint8_t do_rule_check_screen_flag_is_reset( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( GET_SCREEN_FLAG( game_state.current_screen_asset_state_table_ptr[ SCREEN_STATE_INDEX ].asset_state, check->data.flag_state.flag ) ? 0 : 1 );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_FLOW_VAR_EQUAL
uint8_t do_rule_check_flow_var_equal( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( all_flow_vars[ check->data.flow_var.var_id ] == check->data.flow_var.value );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_FLOW_VAR_MORE_THAN
uint8_t do_rule_check_flow_var_more_than( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( all_flow_vars[ check->data.flow_var.var_id ] > check->data.flow_var.value );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_FLOW_VAR_LESS_THAN
uint8_t do_rule_check_flow_var_less_than( struct flow_rule_check_s *check ) __z88dk_fastcall {
    return ( all_flow_vars[ check->data.flow_var.var_id ] < check->data.flow_var.value );
}
#endif

////////////////////////////////////////////////////////////////////
// rules: functions for 'action' dispatch table
// prototype:
//   void do_rule_action_xxxx( struct flow_rule_action_s *action )
////////////////////////////////////////////////////////////////////

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_SET_USER_FLAG
void do_rule_action_set_user_flag( struct flow_rule_action_s *action ) __z88dk_fastcall {
    SET_USER_FLAG( action->data.user_flag.flag );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_RESET_USER_FLAG
void do_rule_action_reset_user_flag( struct flow_rule_action_s *action ) __z88dk_fastcall {
    RESET_USER_FLAG( action->data.user_flag.flag );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_PLAY_SOUND
void do_rule_action_play_sound( struct flow_rule_action_s *action ) __z88dk_fastcall {
    sound_request_fx( action->data.play_sound.sound_id );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_INC_LIVES
void do_rule_action_inc_lives( struct flow_rule_action_s *action ) __z88dk_fastcall {
    game_state.hero.num_lives += action->data.lives.count;
    hero_update_lives_display();
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_CALL_CUSTOM_FUNCTION
void do_rule_action_call_custom_function( struct flow_rule_action_s *action ) __z88dk_fastcall {
    action_custom_functions[ action->data.custom.function_id]();
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_END_OF_GAME
void do_rule_action_end_of_game( struct flow_rule_action_s *action ) __z88dk_fastcall {
    SET_GAME_FLAG( F_GAME_END );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_WARP_TO_SCREEN
void do_rule_action_warp_to_screen( struct flow_rule_action_s *action ) __z88dk_fastcall {
    // only change coords if directed to do it
    if ( ! ( action->data.warp_to_screen.flags & ACTION_WARP_TO_SCREEN_KEEP_HERO_X ) )
        hero_set_position_x( &game_state.hero, action->data.warp_to_screen.hero_x );
    if ( ! ( action->data.warp_to_screen.flags & ACTION_WARP_TO_SCREEN_KEEP_HERO_Y ) )
        hero_set_position_y( &game_state.hero, action->data.warp_to_screen.hero_y );
    game_state.next_screen = action->data.warp_to_screen.num_screen;
    SET_LOOP_FLAG( F_LOOP_WARP_TO_SCREEN );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_ENABLE_HOTZONE
void do_rule_action_enable_hotzone( struct flow_rule_action_s *action ) __z88dk_fastcall {
    struct hotzone_info_s *hz;

    hz = &game_state.current_screen_ptr->hotzone_data.hotzones[ action->data.hotzone.num_hotzone ];
    // only do it if there is a state, ignore if there is not
    if ( hz->state_index != ASSET_NO_STATE )
        SET_HOTZONE_FLAG( game_state.current_screen_asset_state_table_ptr[ hz->state_index ].asset_state,
            F_HOTZONE_ACTIVE );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_DISABLE_HOTZONE
void do_rule_action_disable_hotzone( struct flow_rule_action_s *action ) __z88dk_fastcall {
    struct hotzone_info_s *hz;

    hz = &game_state.current_screen_ptr->hotzone_data.hotzones[ action->data.hotzone.num_hotzone ];
    // only do it if there is a state, ignore if there is not
    if ( hz->state_index != ASSET_NO_STATE )
        RESET_HOTZONE_FLAG( game_state.current_screen_asset_state_table_ptr[ hz->state_index ].asset_state,
            F_HOTZONE_ACTIVE );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_ENABLE_BTILE
void do_rule_action_enable_btile( struct flow_rule_action_s *action ) __z88dk_fastcall {
    struct btile_pos_s *t = &game_state.current_screen_ptr->btile_data.btiles_pos[ action->data.btile.num_btile ];
    SET_BTILE_FLAG( game_state.current_screen_asset_state_table_ptr[ t->state_index ].asset_state, F_BTILE_ACTIVE );
    btile_draw( t->row, t->col, dataset_get_banked_btile_ptr( t->btile_id ) , t->type, &game_area);
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_DISABLE_BTILE
void do_rule_action_disable_btile( struct flow_rule_action_s *action ) __z88dk_fastcall {
    struct btile_pos_s *t = &game_state.current_screen_ptr->btile_data.btiles_pos[ action->data.btile.num_btile ];
    RESET_BTILE_FLAG( game_state.current_screen_asset_state_table_ptr[ t->state_index ].asset_state, F_BTILE_ACTIVE );
    btile_remove( t->row, t->col, dataset_get_banked_btile_ptr( t->btile_id ) );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_ADD_TO_INVENTORY
void do_rule_action_add_to_inventory( struct flow_rule_action_s *action ) __z88dk_fastcall {
    ADD_TO_INVENTORY( &game_state.inventory, action->data.item.item_id );
    inventory_show();
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_REMOVE_FROM_INVENTORY
void do_rule_action_remove_from_inventory( struct flow_rule_action_s *action ) __z88dk_fastcall {
    REMOVE_FROM_INVENTORY( &game_state.inventory, action->data.item.item_id );
    inventory_show();
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_SET_SCREEN_FLAG
void do_rule_action_set_screen_flag( struct flow_rule_action_s *action ) __z88dk_fastcall {
    SET_SCREEN_FLAG( all_screen_asset_state_tables[ action->data.screen_flag.num_screen ].states[ SCREEN_STATE_INDEX ].asset_state, action->data.screen_flag.flag );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_RESET_SCREEN_FLAG
void do_rule_action_reset_screen_flag( struct flow_rule_action_s *action ) __z88dk_fastcall {
    RESET_SCREEN_FLAG( all_screen_asset_state_tables[ action->data.screen_flag.num_screen ].states[ SCREEN_STATE_INDEX ].asset_state, action->data.screen_flag.flag );
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_FLOW_VAR_STORE
void do_rule_action_flow_var_store( struct flow_rule_action_s *action ) __z88dk_fastcall {
    all_flow_vars[ action->data.flow_var.var_id ] = action->data.flow_var.value;
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_FLOW_VAR_INC
void do_rule_action_flow_var_inc( struct flow_rule_action_s *action ) __z88dk_fastcall {
    all_flow_vars[ action->data.flow_var.var_id ]++;
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_FLOW_VAR_ADD
void do_rule_action_flow_var_add( struct flow_rule_action_s *action ) __z88dk_fastcall {
    all_flow_vars[ action->data.flow_var.var_id ] += action->data.flow_var.value;
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_FLOW_VAR_DEC
void do_rule_action_flow_var_dec( struct flow_rule_action_s *action ) __z88dk_fastcall {
    all_flow_vars[ action->data.flow_var.var_id ]--;
}
#endif

#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_FLOW_VAR_SUB
void do_rule_action_flow_var_sub( struct flow_rule_action_s *action ) __z88dk_fastcall {
    all_flow_vars[ action->data.flow_var.var_id ] -= action->data.flow_var.value;
}
#endif

// dispatch tables for check and action functions

// Table of check functions. The 'check' value from the rule is used to
// index into this table and execute the appropriate function
rule_check_fn_t rule_check_fn[ RULE_CHECK_MAX + 1 ] = {
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_GAME_FLAG_IS_SET
    do_rule_check_game_flag_is_set,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_GAME_FLAG_IS_RESET
    do_rule_check_game_flag_is_reset,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_LOOP_FLAG_IS_SET
    do_rule_check_loop_flag_is_set,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_LOOP_FLAG_IS_RESET
    do_rule_check_loop_flag_is_reset,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_USER_FLAG_IS_SET
    do_rule_check_user_flag_is_set,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_USER_FLAG_IS_RESET
    do_rule_check_user_flag_is_reset,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_LIVES_EQUAL
    do_rule_check_lives_equal,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_LIVES_MORE_THAN
    do_rule_check_lives_more_than,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_LIVES_LESS_THAN
    do_rule_check_lives_less_than,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_ENEMIES_ALIVE_EQUAL
    do_rule_check_enemies_alive_equal,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_ENEMIES_ALIVE_MORE_THAN
    do_rule_check_enemies_alive_more_than,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_ENEMIES_ALIVE_LESS_THAN
    do_rule_check_enemies_alive_less_than,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_ENEMIES_KILLED_EQUAL
    do_rule_check_enemies_killed_equal,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_ENEMIES_KILLED_MORE_THAN
    do_rule_check_enemies_killed_more_than,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_ENEMIES_KILLED_LESS_THAN
    do_rule_check_enemies_killed_less_than,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_CALL_CUSTOM_FUNCTION
    do_rule_check_call_custom_function,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_ITEM_IS_OWNED
    do_rule_check_item_is_owned,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_HERO_OVER_HOTZONE
    do_rule_check_hero_over_hotzone,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_SCREEN_FLAG_IS_SET
    do_rule_check_screen_flag_is_set,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_SCREEN_FLAG_IS_RESET
    do_rule_check_screen_flag_is_reset,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_FLOW_VAR_EQUAL
    do_rule_check_flow_var_equal,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_FLOW_VAR_MORE_THAN
    do_rule_check_flow_var_more_than,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_CHECK_FLOW_VAR_LESS_THAN
    do_rule_check_flow_var_less_than,
#else
    NULL,
#endif
};

// Table of action functions.  The 'action' value from the rule is used to
// index into this table and execute the appropriate function
rule_action_fn_t rule_action_fn[ RULE_ACTION_MAX + 1 ] = {
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_SET_USER_FLAG
    do_rule_action_set_user_flag,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_RESET_USER_FLAG
    do_rule_action_reset_user_flag,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_PLAY_SOUND
    do_rule_action_play_sound,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_INC_LIVES
    do_rule_action_inc_lives,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_CALL_CUSTOM_FUNCTION
    do_rule_action_call_custom_function,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_END_OF_GAME
    do_rule_action_end_of_game,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_WARP_TO_SCREEN
    do_rule_action_warp_to_screen,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_ENABLE_HOTZONE
    do_rule_action_enable_hotzone,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_DISABLE_HOTZONE
    do_rule_action_disable_hotzone,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_ENABLE_BTILE
    do_rule_action_enable_btile,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_DISABLE_BTILE
    do_rule_action_disable_btile,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_ADD_TO_INVENTORY
    do_rule_action_add_to_inventory,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_REMOVE_FROM_INVENTORY
    do_rule_action_remove_from_inventory,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_SET_SCREEN_FLAG
    do_rule_action_set_screen_flag,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_RESET_SCREEN_FLAG
    do_rule_action_reset_screen_flag,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_FLOW_VAR_STORE
    do_rule_action_flow_var_store,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_FLOW_VAR_INC
    do_rule_action_flow_var_inc,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_FLOW_VAR_ADD
    do_rule_action_flow_var_add,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_FLOW_VAR_DEC
    do_rule_action_flow_var_dec,
#else
    NULL,
#endif
#ifdef BUILD_FEATURE_FLOW_RULE_ACTION_FLOW_VAR_SUB
    do_rule_action_flow_var_sub,
#else
    NULL,
#endif
};

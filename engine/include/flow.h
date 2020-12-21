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

struct flow_rule_s {
};

struct flow_rule_table_s {
    uint8_t num_rules;
    struct flow_rule_s *rules[];
};

struct flow_info_s {
        struct flow_rule_table_s enter_screen;
        struct flow_rule_table_s exit_screen;
        struct flow_rule_table_s hero_hit;
        struct flow_rule_table_s enemy_hit;
        struct flow_rule_table_s item_grabbed;
        struct flow_rule_table_s game_loop;
};

#endif //_FLOW_H

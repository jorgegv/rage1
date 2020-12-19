////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is ublished under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _FLOW_RULE_H
#define _FLOW_RULE_H

struct flow_rule_s {
};

struct flow_rule_table_s {
    uint8_t num_rules;
    struct flow_rule_s *rules[];
};

#endif //_FLOW_RULE_H

////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is ublished under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _GAME_CONFIG_H
#define _GAME_CONFIG_H

struct game_config_s {
    struct {
        void (*run_menu)(void);
        void (*run_intro)(void);
        void (*run_game_end)(void);
        void (*run_game_over)(void);
    } game_functions;
};
extern struct game_config_s game_config;

#endif // _GAME_CONFIG_H

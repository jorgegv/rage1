////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _HOTZONE_H
#define _HOTZONE_H

#include <stdint.h>

struct hotzone_info_s {
    uint8_t type;
    uint8_t row,col;
    uint8_t width,height;
    uint16_t flags;
    struct {
        uint8_t screen_num;
        uint8_t hero_x,hero_y;
    } destination_screen;
};

uint8_t hotzone_is_inside( struct hotzone_info_s *h, uint8_t x, uint8_t y );
void hotzone_activate_all_endofgame_zones(void);
void hotzone_deactivate_all_endofgame_zones(void);

// hotzone types
#define HZ_TYPE_WARP		0x00
#define HZ_TYPE_END_OF_GAME	0x01

// hotzone flags macros and definitions
#define GET_HOTZONE_FLAG(s,f)	( (s).flags & (f) )
#define SET_HOTZONE_FLAG(s,f)	( (s).flags |= (f) )
#define RESET_HOTZONE_FLAG(s,f)	( (s).flags &= ~(f) )

#define F_HOTZONE_ACTIVE	0x0001

#endif // _HOTZONE_H

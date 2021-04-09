////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _COLLISION_H
#define _COLLISION_H

#include "rage1/types.h"
#include "rage1/sprite.h"

uint8_t collision_check( struct position_data_s *a,struct position_data_s *b );
void collision_check_hero_with_sprites( void );
void collision_check_bullets_with_sprites( void );

#endif // _COLLISION_H

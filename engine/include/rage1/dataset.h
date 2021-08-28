////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#ifndef _DATASET_H
#define _DATASET_H

#include <stdint.h>

// structure for storing the bank number and address offset for a given
// dataset

struct dataset_map_s {
    uint8_t	bank_num;	// bank number
    uint16_t	offset;		// address offset from 0xC000
};

void dataset_activate( uint8_t ds );

#endif // _DATASET_H

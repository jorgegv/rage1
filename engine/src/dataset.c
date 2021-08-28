////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <stdint.h>
#include <intrinsic.h>

#include "rage1/dataset.h"

void dataset_activate( uint8_t ds ) {
// interrupts need to be disabled because the timer tick routine accesses
// data that may be over 0xC000

    intrinsic_di();
// select source memory bank for dataset ds
// asset_set_tables( (struct asset_data_s *)BANKED_DATASET_BASE_ADDRESS );
// select back memory bank 0
    intrinsic_ei();
}

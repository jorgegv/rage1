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
#include <string.h>
#include <compress/zx0.h>

#include "rage1/dataset.h"
#include "rage1/memory.h"
#include "rage1/game_state.h"

#include "game_data.h"

// Global structs that hold the current banked and home asset tables.  They
// must go in low memory, so they are instead included in lowmem/asmdata.asm
// struct dataset_assets_s *banked_assets;
// struct dataset_assets_s *home_assets;

uint8_t dataset_currently_active = 255;

#ifdef BUILD_FEATURE_ZX_TARGET_128
void dataset_activate( uint8_t d ) {

    // if the dataset is already active, do nothing
    if ( d == dataset_currently_active )
        return;

    // switch the proper memory bank for the given dataset
    memory_switch_bank( dataset_info[ d ].bank_num );

    // copy dataset data into LOWMEM buffer
    // data is ZX0 compressed, so decompress to destination address
    // beware: dzx0_* arguments are (source,dest), unlike memcpy and friends!
    dzx0_standard( (void *) ( 0xC000 + dataset_info[ d ].offset ), (void *) BANKED_DATASET_BASE_ADDRESS );

    // switch back to bank 0
    memory_switch_bank( 0 );

    // Save the dataset that was activated - Beware!  This has to be done
    // AFTER switching back to bank 0!
    dataset_currently_active = d;
}
#endif

void init_datasets(void) {
    // setup home dataset
    home_assets = &all_assets_dataset_home;

#ifdef BUILD_FEATURE_ZX_TARGET_128
    // setup banked dataset; it is always at the same address
    banked_assets = (struct dataset_assets_s *) BANKED_DATASET_BASE_ADDRESS;
    // activate dataset
    dataset_activate( 0 );
#endif

#ifdef BUILD_FEATURE_ZX_TARGET_48
    banked_assets = home_assets;
#endif
}

struct map_screen_s *dataset_get_current_screen_ptr( void ) {
    return &banked_assets->all_screens[ screen_dataset_map[ game_state.current_screen ].dataset_local_screen_num ];
}

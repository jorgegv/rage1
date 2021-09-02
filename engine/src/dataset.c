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

#include "rage1/dataset.h"
#include "rage1/memory.h"
#include "rage1/dataset.h"

// global struct that holds the current assets table
struct dataset_assets_s current_assets;

// switches asset tables (e.g. when loading a new dataset)
void dataset_load_asset_tables( struct dataset_assets_s *s ) {
    memcpy( &current_assets, s, sizeof( current_assets ) );
}

void dataset_activate( uint8_t ds ) {

    // intrinsic_di();	// not needed any more

    // select source memory bank for dataset ds
    memory_switch_bank( dataset_map[ ds ].bank_num );

    // copy dataset at (0xC000 + dataset.offset) to page frame at 0x5B00
    memcpy( (void *) BANKED_DATASET_BASE_ADDRESS, (void *) ( 0xC000 + dataset_map[ ds ].offset ), dataset_map[ ds ].size );

    // select back memory bank 0
    memory_switch_bank( 0 );

    // intrinsic_ei();	// not needed any more

    // setup asset tables, they are always at dataset offset 0
    dataset_load_asset_tables( (struct dataset_assets_s *) BANKED_DATASET_BASE_ADDRESS );

}

void init_datasets(void) {
//    dataset_load_asset_tables( &all_assets_dataset_0 );
//    dataset_loas_asset_tables( (struct dataset_assets_s *)BANKED_DATASET_BASE_ADDRESS );
    // start game with dataset 0
    dataset_activate( 0 );
}
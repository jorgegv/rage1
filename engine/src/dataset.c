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
#include "rage1/dataset.h"

// Global structs that hold the current banked and home asset tables.  They
// must go in low memory, so they are instead included in lowmem/asmdata.asm
// struct dataset_assets_s *banked_assets;
// struct dataset_assets_s *home_assets;

void dataset_activate( uint8_t ds ) {
    // switch the proper memory bank for the given dataset
    memory_switch_bank( dataset_map[ ds ].bank_num );

    // copy dataset data into LOWMEM buffer
    // data is ZX0 compressed, so decompress to destination address
    // beware: dzx0_* arguments are (source,dest), unlike memcpy and friends!
    dzx0_standard( (void *) ( 0xC000 + dataset_map[ ds ].offset ), (void *) BANKED_DATASET_BASE_ADDRESS );

    // switch back to bank 0
    memory_switch_bank( 0 );
}

void init_datasets(void) {
    // setup home dataset
//    home_assets = &dataset_home;

    // setup banked dataset; it is always at the same address
    banked_assets = (struct dataset_assets_s *) BANKED_DATASET_BASE_ADDRESS;

    // activate dataset
    dataset_activate( 0 );
}

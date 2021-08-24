////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <string.h>

#include "rage1/asset.h"

// global struct that holds the current assets table
struct asset_data_s current_assets;

// switches asset tables (e.g. when loading a new dataset)
void asset_set_tables( struct asset_data_s *s ) {
    memcpy( &current_assets, s, sizeof( current_assets ) );
}

void init_assets(void) {
    asset_set_tables( &all_assets_dataset_0 );
}

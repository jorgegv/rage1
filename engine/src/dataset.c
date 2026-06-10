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
#include "rage1/interrupts.h"

#include "game_data.h"

// Global structs that hold the current banked and home asset tables.  They
// must go in low memory, so they are instead included in lowmem/asmdata.asm
// struct dataset_assets_s *banked_assets;
// struct dataset_assets_s *home_assets;

// B5-4: guard updated from BUILD_FEATURE_ZX_TARGET_128 to the canonical
// banked-platform condition.  ZX 128 defines both macros; the new
// condition is equivalent there (byte-identical).  cpc-flat compiles out.
#if defined( BUILD_FEATURE_PLATFORM_ZX128 ) || defined( BUILD_FEATURE_PLATFORM_CPC_BANKED )
void dataset_activate( uint8_t d ) __z88dk_fastcall {
    uint8_t previous_memory_bank;

    // if the dataset is already active, do nothing
    if ( game_state.active_dataset == d )
        return;

    // INTERIM FIX (cpc-banked): on cpc-banked the IM1 interrupt dispatch path
    // (the +cpc CRT interposer's z88dk-clib vector dispatcher + its vector
    // tables) currently resides in the 0x4000-0x7FFF swap window; a tick firing
    // while a dataset bank is paged in there vectors into paged-out code and
    // crashes.  Hold interrupts off across the whole Config-N
    // window using the nesting interlock (inner memory_switch_bank EIs are
    // suppressed while nesting stays >0).  ZX128 is unaffected (its swap window
    // is 0xC000, ISR is below it) so it is guarded out and stays byte-identical.
    // Permanent fix (planned) = own the IM1 vector with a low-memory ISR, after
    // which interrupts can stay live across the decompress and this can be removed.
#ifdef BUILD_FEATURE_PLATFORM_CPC_BANKED
    intrinsic_di_if_needed();
#endif

    // save previous memory bank, switch the proper memory bank for the
    // given dataset
    previous_memory_bank = memory_switch_bank( dataset_info[ d ].bank_num );

    // copy dataset data into LOWMEM buffer
    // data is ZX0 compressed, so decompress to destination address
    // beware: dzx0_* arguments are (source,dest), unlike memcpy and friends!
    dzx0_standard( (void *) ( DATASET_LOAD_BASE + dataset_info[ d ].offset ), (void *) BANKED_DATASET_BASE_ADDRESS );

    // switch back to previous memory bank
    memory_switch_bank( previous_memory_bank );

#ifdef BUILD_FEATURE_PLATFORM_CPC_BANKED
    intrinsic_ei_if_needed();
#endif

    // Save the dataset that was activated here and in game_state - Beware!
    // This has to be done AFTER switching back to bank 0!
    game_state.active_dataset = d;

}

// Force the loading of a dataset, even it is the current one.  Useful when we have destroyed the
// low mem buffer with some other data and we want to rebuild it
void dataset_activate_force( uint8_t d ) __z88dk_fastcall {
    game_state.active_dataset = NO_DATASET;
    dataset_activate( d );
}
#endif // BUILD_FEATURE_PLATFORM_ZX128 || BUILD_FEATURE_PLATFORM_CPC_BANKED

void init_datasets(void) {
    // setup home dataset
    home_assets = &all_assets_dataset_home;

#if defined( BUILD_FEATURE_PLATFORM_ZX128 ) || defined( BUILD_FEATURE_PLATFORM_CPC_BANKED )
    // setup banked dataset; it is always at the same address
    banked_assets = (struct dataset_assets_s *) BANKED_DATASET_BASE_ADDRESS;
    // activate dataset
    dataset_activate( 0 );
#endif

// cpc-flat and zx48 have no banking; banked_assets aliases home_assets
#if defined( BUILD_FEATURE_ZX_TARGET_48 ) || defined( BUILD_FEATURE_PLATFORM_CPC_FLAT )
    banked_assets = home_assets;
#endif
}

// acceleration functions
struct btile_s *dataset_get_banked_btile_ptr( uint16_t btile_id ) __z88dk_fastcall {
    return &banked_assets->all_btiles[ btile_id ];
}

struct sprite_graphic_data_s *dataset_get_banked_sprite_ptr( uint8_t sprite_id ) __z88dk_fastcall {
    return &banked_assets->all_sprite_graphics[ sprite_id ];
}

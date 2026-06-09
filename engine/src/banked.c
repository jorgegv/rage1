#include "rage1/btile.h"
#include "rage1/game_state.h"
#include "rage1/dataset.h"
#include "rage1/bullet.h"
#include "rage1/screen.h"
#include "rage1/memory.h"

#include "game_data.h"

#include "rage1/banked.h"

// B7 step 9.3: init_banked_code() sets up main_shared_data, which is ONLY read
// by engine code compiled as BANKED (-D_BANKED_CODE_BUILD, in a separate bank).
// The cpc-banked first-runnable build keeps the engine RESIDENT (no banked
// engine code; bank 4 reserved-but-empty), so it does NOT call this and would
// otherwise pull in the unlinked init_main_shared_data(). Guard stays ZX-128
// until the banked-engine-code increment lands (DC3-A, measure-driven). ZX128
// byte-identical. (The dataset/codeset banking widenings live in map.c/memory.c.)
#ifdef BUILD_FEATURE_ZX_TARGET_128
void init_banked_code( void ) {
    struct main_shared_data_s data = {
        .game_state			= &game_state,
        .home_assets			= home_assets,
        .banked_assets			= banked_assets,
        .screen_pos_tile_type_data	= screen_pos_tile_type_data,
        .bullet_state_data		= bullet_state_data,
    };
    init_main_shared_data( &data );
}
#endif

#include "rage1/btile.h"
#include "rage1/game_state.h"
#include "rage1/dataset.h"
#include "rage1/bullet.h"
#include "rage1/screen.h"
#include "rage1/memory.h"

#include "game_data.h"

#include "rage1/banked.h"

// B7 step 9.2: widen from BUILD_FEATURE_ZX_TARGET_128 to the canonical
// banked-platform predicate so cpc-banked links init_banked_code() too. ZX 128
// defines both macros, so this is byte-identical on ZX; ZX 48 / cpc-flat (no
// banking) still compile it out.
#if defined( BUILD_FEATURE_PLATFORM_ZX128 ) || defined( BUILD_FEATURE_PLATFORM_CPC_BANKED )
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

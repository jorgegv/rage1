#include "rage1/btile.h"
#include "rage1/game_state.h"
#include "rage1/dataset.h"
#include "rage1/bullet.h"
#include "rage1/screen.h"
#include "rage1/memory.h"

#include "game_data.h"

#include "rage1/banked.h"

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

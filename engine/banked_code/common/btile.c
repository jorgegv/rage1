////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#include "features.h"

#include "rage1/animation.h"
#include "rage1/btile.h"
#include "rage1/game_state.h"
#include "rage1/map.h"

#include "game_data.h"

#include "rage1/banked.h"

#ifdef BUILD_FEATURE_ANIMATED_BTILES

void btile_animate_all( void ) {
    uint8_t btile_pos_id;
    uint8_t max_frame;
    struct btile_pos_s *btile_pos;
    struct btile_s *btile;

    uint8_t i = game_state.current_screen_ptr->animated_btile_data.num_btiles;
    while ( i-- ) {
        btile_pos_id = game_state.current_screen_ptr->animated_btile_data.btiles[ i ];
        btile_pos = game_state.current_screen_ptr->btile_data.btiles_pos[ btile_pos_id ];
        max_frame = dataset_get_banked_btile_ptr( btile_pos->btile_id )->sequences[ t->anim_>current.sequence ].num_frames - 1;
        // animation_sequence_tick returns 1 if a frame change is needed, 0 if not
        if ( animation_sequence_tick( t->anim, max_frame ) ) {
            // we draw if there is no state ( no state = always active ), or if the btile is active
            if ( ( btile_pos->state_index == ASSET_NO_STATE ) ||
                IS_BTILE_ACTIVE( all_screen_asset_state_tables[ s->global_screen_num ].states[ btile_pos->state_index ].asset_state ) )
                btile = dataset_get_banked_btile_ptr( btile_pos->btile_id );
                btile_draw_frame( btile_pos->row, btile_pos->col, 
                    btile, btile_pos->type, &game_area,
                    btile->sequences[ btile_pos->anim->current.sequence ].frame_numbers[ btile_pos->anim->current.sequence_counter ]
                );
        }
    }
}

#endif // BUILD_FEATURE_ANIMATED_BTILES

#include <stdint.h>
#include <string.h>
#include <arch/zx.h>
#include <intrinsic.h>

#include "features.h"

#include "rage1/sub.h"

#ifdef BUILD_FEATURE_SINGLE_USE_BLOB

// The SUBs are already stored in the table in the order that they must be
// run.  The ORDER parameter is used by DATAGEN and others to generate the
// ASM data file with the SUBs in the correct order.

// disable incompatible pointer types warning - Careful!
#pragma disable_warning 244

// HACK!! Put this code in its own special section with this HACK!
// wish the following line worked...but no :-(
// #pragma section rage1_subs_loader
void __set_section1( void ) __naked {
__asm
    SECTION rage1_subs_loader
__endasm;
}

// Loads the SUBs from tape. They are stored headerless, we know the info ;-)
void subs_load( void ) {
    uint8_t i;

    // ints must be disabled!  When we reach here, ROM ints are still
    // enabled, and the ISR modifies the SYSVARs, which are just at $5B00,
    // so it would corrupt our data!
    intrinsic_di();
    for ( i = 0; i < num_subs; i++ )
        // warning 244 is triggered by load_address being cast to void *
        zx_tape_load_block( sub_info[ i ].load_address, sub_info[ i ].size, ZXT_TYPE_DATA );
}

// HACK!! see comment above
void __set_section2( void ) __naked {
__asm
    SECTION rage1_subs_loader
__endasm;
}

// Runs the SUBs in order
void subs_run( void ) {
    uint8_t i;

    // ints should be already disabled by subs_oad, but just in case...
    intrinsic_di();
    for ( i = 0; i < num_subs; i++ ) {
        switch ( sub_info[ i ].type ) {
#ifdef BUILD_FEATURE_SINGLE_USE_BLOB_SP1BUF
            case SUB_TYPE_SP1BUF:
                sub_info[ i ].load_address();
                break;
#endif
#ifdef BUILD_FEATURE_SINGLE_USE_BLOB_DSBUF
            case SUB_TYPE_DSBUF:
                if ( sub_info[ i ].needs_swap )
                    // warning 244 is triggered by load_address and execute_address being cast to void *
                    memswap( sub_info[ i ].load_address, sub_info[ i ].execute_address, sub_info[ i ].size );
                sub_info[ i ].execute_address();
                if ( sub_info[ i ].needs_swap )
                    // warning 244 is triggered by load_address and execute_address being cast to void *
                    memswap( sub_info[ i ].load_address, sub_info[ i ].execute_address, sub_info[ i ].size );
                break;
#endif
            default:
                break;
        }
    }
}
#endif // BUILD_FEATURE_SINGLE_USE_BLOB

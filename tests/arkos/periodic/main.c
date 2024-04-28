#include <intrinsic.h>
#include <stdint.h>

// Arkos C prototypes
void ply_akg_init( void *song, unsigned int subsong ) __z88dk_callee;
void ply_akg_play( void );
void ply_akg_stop( void );
void ply_akg_initsoundeffects( void *effects_table ) __z88dk_fastcall;
void ply_akg_playsoundeffect( uint16_t effect, uint16_t channel, uint16_t inv_volume ) __z88dk_callee;

extern uint8_t song[];
extern uint8_t *all_sound_effects[];


uint8_t counter = 0;
uint8_t effect = 1;
void main( void ) {
    ply_akg_init( song, 0 );
    ply_akg_initsoundeffects( all_sound_effects );
    while ( 1 ) {
        (*(uint8_t *)0x4000)++;

        // every 2 seconds, play fx
        if ( counter++ == 100 ) {
            (*(uint8_t *)0x4002)++;
            counter = 0;
            ply_akg_playsoundeffect( effect++, 1, 0 );
            if ( effect > 5 )
                effect = 1;
        }

        intrinsic_di();
        ply_akg_play();
        intrinsic_ei();
        intrinsic_halt();
    }
}

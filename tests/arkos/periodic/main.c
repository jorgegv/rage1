#include <intrinsic.h>
#include <stdint.h>

// Arkos C prototypes
void ply_akg_init( void *song, unsigned int subsong ) __z88dk_callee;
void ply_akg_play( void );
void ply_akg_stop( void );
void ply_akg_initsoundeffects( void *effects_table ) __z88dk_fastcall;
void _ply_akg_playsoundeffect( unsigned int effect ) __z88dk_fastcall;

extern uint8_t song[];

void main( void ) {
    ply_akg_init( song, 0 );
    while ( 1 ) {
        (*(uint8_t *)0x4000)++;
        intrinsic_di();
        ply_akg_play();
        intrinsic_ei();
        intrinsic_halt();
    }
}

// RAGE1 CPC 6128 (cpc-banked) bank-switch primitive validation (B6-1/B6-2).
//
// Empirically validates the cpc-banked bank-switch PRIMITIVE
// (engine/src/00bswitch.c memory_switch_bank()) on a real 128K machine /
// cap32.  It stamps a distinct marker byte into each expansion RAM bank
// {4,5,6,7} through the 0x4000 swap window, returns to the home config
// (bank 0 = GA Config 0), then reads each bank back and checks the markers
// survived independently.  Only a correct Gate-Array RAM-config select
// (out 0xC0|config -> port 0x7F) makes all four markers read back intact:
//   - if the switch is a no-op, every write hits the same physical RAM and
//     only the last-written marker survives -> FAIL;
//   - if two configs alias the same bank, their markers clash -> FAIL.
//
// This game links ONLY engine/src/00bswitch.c (CPC_LINK_BSWITCH=1) and
// supplies the interrupt_nesting_level interlock symbol locally, so no other
// engine code is pulled in.

#include <stdint.h>

#include "features.h"

#ifndef BUILD_FEATURE_PLATFORM_CPC_BANKED
#error "cpc-bswitch-test must be built for cpc6128 (PLATFORM_CPC_BANKED)"
#endif

// the cpc-banked bank-switch primitive (engine/src/00bswitch.c)
extern uint8_t memory_switch_bank( uint8_t bank ) __z88dk_fastcall;

// z88dk +cpc firmware-backed character output (as used by cpc-hello-banked)
extern int printk( const char *fmt, ... );

// memory_switch_bank()'s atomic-section nesting counter.  Normally defined in
// engine/src/cpc/asmdata_cpc.c; provided here so the test links just the
// primitive TU and nothing else.
uint8_t interrupt_nesting_level;

// any address inside the 0x4000-0x7FFF swap window (page B) works; the window
// base is clearest.  volatile so the read-back is not optimised away.
#define SWAP_WINDOW	( (volatile uint8_t *) 0x4000 )

int main( void ) {
    static const uint8_t banks[ 4 ] = { 4, 5, 6, 7 };
    static const uint8_t marks[ 4 ] = { 0x44, 0x55, 0x66, 0x77 };
    uint8_t i, got, all_ok = 1;

    printk( "RAGE1 cpc-banked BANK-SWITCH test\r\n\r\n" );

    // phase 1: stamp each expansion bank through the swap window
    for ( i = 0; i < 4; i++ ) {
        memory_switch_bank( banks[ i ] );
        *SWAP_WINDOW = marks[ i ];
    }
    memory_switch_bank( 0 );		// back to the home config

    // phase 2: read each bank back; markers must be intact + independent
    for ( i = 0; i < 4; i++ ) {
        memory_switch_bank( banks[ i ] );
        got = *SWAP_WINDOW;
        memory_switch_bank( 0 );	// return home before firmware output
        printk( "RAM %u: wrote %x  read %x  %s\r\n",
                (uint16_t) banks[ i ], (uint16_t) marks[ i ], (uint16_t) got,
                ( got == marks[ i ] ) ? "OK" : "FAIL" );
        if ( got != marks[ i ] )
            all_ok = 0;
    }

    printk( "\r\n%s\r\n", all_ok ? "RESULT: PASS" : "RESULT: FAIL" );

    // freeze so the emulator screenshot can be taken
    for ( ;; ) { }

    return 0;
}

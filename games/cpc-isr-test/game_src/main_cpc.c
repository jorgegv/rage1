// RAGE1 CPC 6128 (cpc-banked) IM1 ISR validation (B6-8).
//
// Proves the cpc-banked CPC interrupt path actually ticks on a real 128K
// machine / cap32: the +cpc CRT (CRT_DISABLE_FIRMWARE_ISR=1, set in
// zpragma-cpc-banked.inc) owns the 0x0038 IM1 vector and calls our registered
// 300 Hz fast handler, which engine/src/interrupts.c divides by six to drive
// RAGE1's 50 Hz tick (current_time advances).  banking.md §3.5 / §3.5.1.
//
// The ISR body + counter live in page A (RAM0), permanently mapped under every
// MMR Config, so the ISR is valid regardless of paging; this test exercises it
// with no banking active (Config 0 throughout).
//
// Links engine/src/interrupts.c + engine/src/cpc/asmdata_cpc.c (the latter
// defines current_time / periodic_tasks_enabled / interrupt_nesting_level) via
// CPC_LINK_ISR=1; no other engine code is pulled.

#include <stdint.h>

#include "features.h"

#ifndef BUILD_FEATURE_PLATFORM_CPC_BANKED
#error "cpc-isr-test must be built for cpc6128 (PLATFORM_CPC_BANKED)"
#endif

#include "rage1/interrupts.h"		// current_time, init_interrupts()

extern int printk( const char *fmt, ... );

// Fixed CPU spin (no dependency on the ISR, so it cannot hang if the ISR is
// dead).  ~1.5-2 s of wall time at 4 MHz (observed: the 50 Hz tick advances
// current_time.ticks by ~86), short enough that the delay + the result print
// finish well inside cap32-shot.sh's 8 s capture window.
static void busy_delay( void ) {
    volatile uint16_t i;
    for ( i = 0; i < 30000U; i++ ) { }
}

int main( void ) {
    uint32_t t1, t2;
    uint8_t  s1, s2;

    printk( "RAGE1 cpc-banked IM1 ISR test\r\n\r\n" );

    init_interrupts();			// wire the 300 Hz fast handler, ei

    t1 = current_time.ticks;  s1 = current_time.sec;
    busy_delay();			// ~1 s; the 50 Hz tick should advance ~50
    t2 = current_time.ticks;  s2 = current_time.sec;

    // a few seconds at 50 Hz keeps ticks well under 16 bits, so %u is safe
    printk( "ticks: %u -> %u\r\n", (uint16_t) t1, (uint16_t) t2 );
    printk( "secs : %u -> %u\r\n", (uint16_t) s1, (uint16_t) s2 );

    if ( t2 > t1 )
        printk( "\r\nISR 50Hz TICK: PASS\r\n" );
    else
        printk( "\r\nISR DEAD (no ticks): FAIL\r\n" );

    for ( ;; ) { }
    return 0;
}

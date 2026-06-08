// RAGE1 CPC 6128 (cpc-banked) hello-world smoke game (T3-9)
//
// Minimal standalone C programme that proves the cpc6128 / cpc-banked
// toolchain pipeline end-to-end at Phase T3a:
//
//   datagen.pl -p cpc6128   ->  features.h (PLATFORM_CPC6128 / PLATFORM_CPC_BANKED)
//   zcc +cpc -compiler=sdcc  ->  linked binary
//   zcc -create-app -subtype=dsk -> game.dsk (bootable, RUN"FILE)
//
// NO banking is exercised here — this only validates that build-cpc6128 routes
// through Makefile-cpc-banked and produces a runnable .dsk. The bank-switch
// primitive, datasets and codesets land in Phase B6/B7. The RAGE1 engine is
// NOT linked at this phase (same as the cpc-flat cpc-hello game).

#include <stdint.h>

#ifdef __SDCC
#include "features.h"
#endif

// Sanity: fail to compile unless datagen emitted the cpc6128 / cpc-banked macros.
#ifndef BUILD_FEATURE_PLATFORM_CPC6128
#error "BUILD_FEATURE_PLATFORM_CPC6128 not defined — did datagen.pl run with -p cpc6128?"
#endif
#ifndef BUILD_FEATURE_PLATFORM_CPC_BANKED
#error "BUILD_FEATURE_PLATFORM_CPC_BANKED not defined — did datagen.pl run with -p cpc6128?"
#endif

// z88dk +cpc CRT stdio (firmware-backed character output at this phase).
extern int printk(const char *fmt, ...);

int main(void) {
    printk("RAGE1 CPC6128 Hello-World\r\n");
    printk("Phase T3a - cpc-banked bring-up\r\n");
    printk("\r\n");
    printk("PLATFORM: cpc6128 (cpc-banked)\r\n");
    printk("ORG:      0x1200 (CRT_ORG_CODE)\r\n");
    printk("\r\n");
    printk("Toolchain OK - game.dsk produced.\r\n");

    // Freeze so the emulator screenshot can be taken.
    for (;;) { }

    return 0;
}

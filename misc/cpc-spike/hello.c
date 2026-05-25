/*
 * RAGE1 cross-platform plan — Phase T0 spike (CPC toolchain proof).
 *
 * This file is a throwaway smoke-test. Goal: prove that
 *   zcc +cpc
 * produces a working AMSDOS binary using the z88dk-bundled CPC library.
 *
 * Spike will be deleted before Phase T1 per toolchain.md §Phase T0.
 *
 * The spike uses z88dk's native <arch/cpc.h> primitives. See
 * misc/cpc-spike/README.md for the cpctelera-source-link finding that
 * required this fallback path.
 *
 * Trivial draw primitive used: cpc_SetMode (direct gate-array video
 * mode change) + cpc_SetBorder (border colour set). These are the
 * z88dk-native analogues of cpctelera's cpct_setVideoMode and a
 * border-fill primitive.
 */

#include <arch/cpc/cpc.h>

void main( void ) {

    /* Switch to MODE 1 (320x200, 4 colours) via direct gate-array write. */
    cpc_SetMode( 1 );

    /* Cycle the border so the screen visibly changes when the binary
       runs. Colour 6 is bright red in the CPC firmware palette. */
    cpc_SetBorder( 6 );

    /* Hang. CPC has no clean exit path from a raw binary — the BASIC
       interpreter is gone after AMSDOS RUN"". */
    for ( ;; ) { }
}

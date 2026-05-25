/*
 * RAGE1 cross-platform plan — Phase T0-4 spike: prove #pragma bank
 * compiles on the +cpc target.
 *
 * Goal (per toolchain.md §T0-4):
 *   "prove #pragma bank syntax compiles on +cpc, not that it produces
 *    a runtime-perfect CPC6128 banked image."
 *
 * Layout:
 *   - main()          stays in the main code section
 *   - banked_fn()     is placed in bank 4 via #pragma bank 4
 *   - main() calls banked_fn() — the linker should resolve the call
 *     through whatever bank-trampoline mechanism z88dk emits for +cpc.
 */

#include <arch/cpc/cpc.h>

#pragma bank 4
void banked_fn( void ) {
    /* Touch a CPC primitive from banked code, so the call doesn't get
       dead-stripped and so we exercise the linker's symbol resolution
       across banks. */
    cpc_SetBorder( 3 );
}

void main( void ) {
    cpc_SetMode( 1 );
    cpc_SetBorder( 6 );
    banked_fn();
    for ( ;; ) { }
}

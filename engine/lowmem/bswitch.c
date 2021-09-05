////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <stdint.h>
#include <arch/zx.h>

// Memory Banking configuration for port $7FFD:
//
// - Bits 0-2: RAM page (0-7) to map into memory at 0xc000 - OR'ed with the
//   bank number passed as argument
//
// - Bit 3: Select normal (0) or shadow (1) screen to be displayed.  The
//   normal screen is in bank 5, whilst the shadow screen is in bank 7. 
//   Note that this does not affect the memory between 0x4000 and 0x7fff,
//   which is always bank 5.
//
// - Bit 4: ROM select.  ROM 0 is the 128k editor and menu system; ROM 1
//   contains 48K BASIC.
//
// - Bit 5: If set, memory paging will be disabled and further output to
//   this port will be ignored until the computer is reset.
//
// So we want: bits 0-2: bank number to map; bit 3: 0 (normal screen);
// bit 4: 1 (48K ROM - *see below); bit 5: 0 (allow paging)
//
// Desired value: 00010000 | num_bank
//
// We would not care about bit 5 (ROM select) since we are not calling any
// code there.  But SP1 startup copies character bitmaps from ROM for tiles
// 32-127, so that ASCII chars can be regularly used as tiles and output
// text out of the box.  So we NEED the 48K ROM to be paged for SP1 to
// correctly initialize those tiles.

#define DEFAULT_IO_7FFD_BANK_CFG	( 0x10 )

void memory_switch_bank( uint8_t bank ) {
    // mask the 3 lowest bits of bank, then add it to the default value for
    // IO_7FDD
    IO_7FFD = ( DEFAULT_IO_7FFD_BANK_CFG | ( bank & 0x07 ) );
}

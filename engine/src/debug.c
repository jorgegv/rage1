////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#include <arch/spectrum.h>
#include <games/sp1.h>
#include <input.h>

#include "debug.h"

uint8_t initialized = 0;

struct sp1_Rect debug_area = { 0, 1, 30, 1 };
struct sp1_pss debug_ctx = { &debug_area, SP1_PSSFLAG_INVALIDATE, 0, 0, 0, INK_WHITE | PAPER_BLACK, 0, 0 };

void debug_out( char *txt ) {
    if ( *txt == '\n' ) {
        sp1_ClearRectInv( &debug_area, INK_WHITE | PAPER_BLACK, ' ', SP1_RFLAG_TILE | SP1_RFLAG_COLOUR );
        sp1_SetPrintPos( &debug_ctx, 0, 0 );
        txt++;
    }
    sp1_PrintString( &debug_ctx, txt );
}

uint8_t *digits="0123456789abcdef";

uint8_t ito_buffer[7];
char *itohex( uint16_t i ) {
    uint8_t c = 4;
    while ( c-- > 0 ) {
        ito_buffer[c] = digits[ i & 0x0f ];
        i >>= 4;
    }
//    ito_buffer[4]='h';
//    ito_buffer[5]='\0';
    ito_buffer[4]='\0';
    return &ito_buffer[0];
}

char *i8toa( uint8_t i ){
    ito_buffer[0] = '0' + i / 100;
    ito_buffer[1] = '0' + ( i % 100 ) / 10;
    ito_buffer[2] = '0' + i % 10;
    ito_buffer[3] = '\0';
    return &ito_buffer[0];
}

void debug_waitkey(void) {
    in_wait_key();
    in_wait_nokey();
}

void debug_flush(void) {
    sp1_UpdateNow();
}

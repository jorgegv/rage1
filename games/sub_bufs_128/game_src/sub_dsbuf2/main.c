#include <spectrum.h>
#include <stdint.h>
#include <input.h>

#define CHARS	(( uint8_t * )0x3D00)

void set_border( uint8_t color ) __z88dk_fastcall {
__asm

   in a,(254)
   and $40
   
   rra
   rra
   or l
   
   out (254),a
__endasm;
}

void print_char( uint8_t row, uint8_t col, char c, uint8_t attr ) {
    uint8_t i;
    uint8_t *dst, *src;

    src = CHARS + ( c - ' ' ) * 8;
    dst = zx_cxy2saddr( col, row );
    for ( i = 0; i < 8; i++ ) {
        *dst = *src;
        dst = zx_saddrpdown( dst );
        src++;
    }
    *zx_cxy2aaddr( col, row ) = attr;
}

void print_string( uint8_t row, uint8_t col, char *txt, uint8_t attr ) {
    while ( *txt ) {
        print_char( row, col++, *txt++, attr );
        if ( col == 32 ) {
            col = 0;
            row++;
        }
    }
}

void blank_screen( uint8_t attr ) {
    uint8_t r,c;
    for ( r = 0; r < 24; r++ )
        for ( c = 0; c < 32; c++ )
            *zx_cxy2aaddr( c, r ) = attr;
}

void sleep( void ) {
    uint16_t c;
    c = 0;
    while( ++c );
}

void main( void ) {
    set_border( INK_BLACK );
    blank_screen( INK_BLACK | PAPER_BLACK );

    print_string( 10, 6, "                    ", INK_BLACK | PAPER_GREEN );
    print_string( 11, 6, " This is DSBUF2 SUB ", INK_BLACK | PAPER_GREEN );
    print_string( 12, 6, "                    ", INK_BLACK | PAPER_GREEN );

    print_string( 15, 6, "** Press any key **", INK_WHITE | PAPER_BLACK );

    in_WaitForNoKey();
    in_WaitForKey();
    in_WaitForNoKey();

    print_string( 17, 6, "**  Key pressed  **",INK_WHITE | PAPER_BLACK );

    sleep();
}

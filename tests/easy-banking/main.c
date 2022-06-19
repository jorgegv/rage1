// zcc +zx -vn --list -s -m --c-code-in-asm -lndos main.c bank6.c -create-app -o banked.bin

#include <stdio.h>

extern int banked_function( void ) __banked;

void main( void ) {
    printf( "Hello world from main bank!\n" );
    printf( "** Value from bank 6: 0x%04x\n", banked_function() );
    while ( 1 ) ;
}

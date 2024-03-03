// zcc +zx -o sub -create-app main.c -pragma-redirect=CRT_FONT=_font_8x8_clairsys_bold

#include <conio.h>
#include <stdlib.h>
#include <input.h>

void main( void ) {

    bordercolor( BLACK );
    textbackground( BLACK );
    textcolor( WHITE );
    clrscr();

    cputs( "\x01\x20" );	// 32-char mode

    textbackground( BLUE );
    textcolor( YELLOW );

    gotoxy( 6,10 );
    cputs( "                    " );
    gotoxy( 6,11 );
    cputs( " This is SP1BUF SUB " );
    gotoxy( 6,12 );
    cputs( "                    " );

    textbackground( BLACK );
    textcolor( WHITE );
    gotoxy( 6,15 );
    cputs( "** Press any key **" );

    in_WaitForNoKey();
    in_WaitForKey();
    in_WaitForNoKey();

    gotoxy( 6,17 );
    cputs( "**  Key pressed  **" );
    sleep( 2 );
}

////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is ublished under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

#pragma output REGISTER_SP		= 0xd000    // place stack at $d000 at startup
#pragma output CRT_STACK_SIZE		= 500
#pragma output CRT_ENABLE_RESTART	= 1         // not returning to basic
#pragma output CRT_ENABLE_CLOSE		= 0         // do not close files on exit
#pragma output CLIB_EXIT_STACK_SIZE	= 0         // no exit stack
#pragma output CLIB_MALLOC_HEAP_SIZE	= -1      // malloc heap size (not sure what is needed exactly)
#pragma output CLIB_STDIO_HEAP_SIZE	= 0         // no memory needed to create file descriptors
#pragma output CLIB_FOPEN_MAX		= 0         // no allocated FILE structures, -1 for no file lists too
#pragma output CLIB_OPEN_MAX		= 0         // no fd table

#include <input.h>

#include "beeper.h"

void main(void) {
   int k = 0;
   while (1) {
      while ( ! ( k = in_inkey() ) );
      switch (k) {
         case '0':
            beep_fx(0);
            break;
         case '1':
            beep_fx(1);
            break;
         case '2':
            beep_fx(2);
            break;
         case '3':
            beep_fx(3);
            break;
         case '4':
            beep_fx(4);
            break;
         case '5':
            beep_fx(5);
            break;
         case '6':
            beep_fx(6);
            break;
         case '7':
            beep_fx(7);
            break;
         case '8':
            beep_fx(8);
            break;
         case '9':
            beep_fx(9);
            break;
         case 'a':
            beep_fx(10);
            break;
         case 'b':
            beep_fx(11);
            break;
      }
      in_wait_nokey();
   }
}

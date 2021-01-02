////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is published under a GNU GPL license version 3 or later.  See
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

#include <intrinsic.h>
#include <arch/spectrum.h>
#include <input.h>
#include <games/sp1.h>

#include "screen.h"
#include "sp1engine.h"
#include "debug.h"
#include "memory.h"
#include "interrupts.h"
#include "game_data.h"
#include "controller.h"
#include "hero.h"

void main(void)
{
   init_memory();
   init_sp1();
   init_interrupts();
   init_controllers();
   init_screen_sprite_tables();
   init_hero();

   debug_out( "init_sp1 OK" );
   debug_flush();
   debug_waitkey();
   while (1) {
      run_intro_screen();
   }
}

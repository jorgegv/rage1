////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is ublished under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

// COMPILE TIME CRT CONFIGURATION FOR 128K MODE BUILD

// don't change these values!!
#pragma output CRT_ORG_CODE           = 0x8184	// org of compile
#pragma output REGISTER_SP            = 0x8181	// just below ISR
#pragma output CRT_STACK_SIZE         = 128	// just enough

#pragma output CRT_ENABLE_CLOSE       = 0	// don't bother closing files on exit
#pragma output CRT_ENABLE_EIDI        = 1	// disable interrupts at start
#pragma output CRT_ENABLE_RESTART     = 1	// do not return to basic

#pragma output CLIB_MALLOC_HEAP_SIZE  = 0	// heap: initialized manually
#pragma output CLIB_STDIO_HEAP_SIZE   = 0	// no stdio heap (no files)

#pragma output CLIB_FOPEN_MAX         = -1	// no FILE* list
#pragma output CLIB_OPEN_MAX          = -1	// no fd table


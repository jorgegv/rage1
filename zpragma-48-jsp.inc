////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is ublished under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

// COMPILE TIME CRT CONFIGURATION FOR 48K MODE BUILD WITH JSP SPRITE ENGINE
// JSP moves IV table to 0xE000 (byte 0xE1), ISR at 0xE1E1
// Stack starts just below ISR; code org unchanged at 0x5F00

// don't change these values!!
#pragma output CRT_ORG_CODE           = 0x5f00	// org of compile (same as SP1)
#pragma output REGISTER_SP            = 0xe1e1	// just below JSP ISR
#pragma output CRT_STACK_SIZE         = 208	// just enough

#pragma output CRT_ENABLE_CLOSE       = 0	// don't bother closing files on exit
#pragma output CRT_ENABLE_EIDI        = 1	// disable interrupts at start
#pragma output CRT_ENABLE_RESTART     = 1	// do not return to basic

#pragma output CLIB_MALLOC_HEAP_SIZE  = 0	// heap: initialized manually
#pragma output CLIB_STDIO_HEAP_SIZE   = 0	// no stdio heap (no files)

#pragma output CLIB_FOPEN_MAX         = -1	// no FILE* list
#pragma output CLIB_OPEN_MAX          = -1	// no fd table

#pragma output __MMAP                 = -1	// use user-supplied memory map: mmap.inc

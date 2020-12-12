////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
// 
// This code is ublished under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
// 
////////////////////////////////////////////////////////////////////////////////

// COMPILE TIME CRT CONFIGURATION

#pragma output CRT_ORG_CODE           = 25124      // org of compile
#pragma output REGISTER_SP            = 0xd000     // typical stack location when using sp1
#pragma output CRT_STACK_SIZE         = 512

#pragma output CRT_ENABLE_CLOSE       = 0          // don't bother closing files on exit
#pragma output CRT_ENABLE_EIDI        = 0x1        // disable interrupts at start
#pragma output CRT_ENABLE_RESTART     = 0x1

#pragma output CLIB_MALLOC_HEAP_SIZE  = -1
#pragma output CLIB_STDIO_HEAP_SIZE   = 0          // no stdio heap (no files)

#pragma output CLIB_FOPEN_MAX         = -1         // no FILE* list
#pragma output CLIB_OPEN_MAX          = -1         // no fd table


// Compile with:
//
//   zcc +zx -vn -SO3 -m -compiler=sdcc -clib=sdcc_iy --max-allocs-per-node200000 --no-crt data.c -o data.bin
//
// Dump binary in hex with:
//
//   od -tx1 data.bin
//
// This data should be compiled to base address 5B00, so that when it's
// decompressed to that address everything works OK

#include <stdint.h>

#pragma output CRT_ORG_DATA = 0x5B00

struct my_data {
    uint8_t	f1,f2;
    uint16_t	f3;
};
extern struct my_data d1, d2;

struct my_data *my_data_ptr	= &d1;	// this should contain 0x5B02
struct my_data d1		= { 1, 2, 0x3456 };	
struct my_data d2		= { 7, 8, 0x9012 };
struct my_data *my_data_ptr2	= &d2;	// this should contain 0x5B06

// binary dump of the generated data file should be these 12 bytes, in order:
// 02 5B 01 02 56 34 07 08 12 90 06 5B

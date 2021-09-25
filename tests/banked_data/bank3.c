#pragma output bank 3

static void _orgit(void) __naked {
__asm
    org	0x5b00
__endasm;
}

unsigned char *dataptr3 = "BANK3";

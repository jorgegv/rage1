#include <stdint.h>

// ports for all kbd rows
uint8_t kbd_row_ports[] = { 0xf7,0xfd,0xfb,0xfe,0xef,0xdf,0xbf,0x7f };

uint16_t capture_key_scancode( void ) __z88dk_fastcall __naked {
__asm

    ; we scan all rows repeatedly
check_loop:
    ld hl,_kbd_row_ports
    ld b,8
check_row:
    ld a,(hl)
    in a,(0xfe)
    and 0x1f
    cp 0x1f			; key is pressed if bit = 0
    jr nz,got_key
    inc hl
    djnz check_row
    jr check_loop

    ; ...until one key is pressed
got_key:
    ld c,a			; C = key pressed

    ld a,8
    sub b			; A = index in row table ( 8 - counter )

    ld hl,_kbd_row_ports	; search the row port table
    ld b,a			; B = index in row table
search_loop:
    inc hl
    djnz search_loop
    ld l,(hl)			; L = row port value

    ld a,c			; negate the key press value
    cpl				; the library expects it
    and 0x1f
    ld h,a    			; H = key pressed

    ; return HL = krepress scancode
    ret

__endasm;
}

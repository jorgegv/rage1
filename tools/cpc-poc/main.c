// RAGE1 CPC R2 PoC — proves the Option (b) translation pipeline end to end:
//   hand-translated cpctelera primitives (engine/src/cpc/*.asm) +
//   zcc +cpc -compiler=sdcc  ->  a CPC image that renders mode-1 text.
//
// Deliberately bypasses the RAGE1 engine. cpctelera itself is never compiled
// (see doc/multiplatform-plan/cpc-renderer.md §4.2 / §6, R1-5).

#include <stdint.h>

// --- C-callable ABI of the translated cpctelera primitives (engine/src/cpc) ---
extern void cpct_setVideoMode( uint8_t mode )                 __z88dk_fastcall;
extern void cpct_setPALColour( uint8_t pen, uint8_t hw_ink )  __z88dk_callee;
extern void cpct_setDrawCharM1( uint8_t fg_pen, uint8_t bg_pen ) __z88dk_callee;
extern void cpct_drawStringM1( void *string, void *video_mem )   __z88dk_callee;

// CPC hardware colour values (from cpctelera colours.h)
#define HW_BLACK          0x14
#define HW_BLUE           0x04
#define HW_BRIGHT_YELLOW  0x0A
#define HW_BRIGHT_WHITE   0x0B

#define CPC_VMEM ((uint8_t *)0xC000)

int main(void) {
    __asm
        di                      ;; take the machine from the firmware for the PoC
    __endasm;

    cpct_setVideoMode(1);       // mode 1: 320x200, 4 colours

    // Palette: pen 0 = background (blue), pen 1 = text (bright yellow)
    cpct_setPALColour(0, HW_BLUE);
    cpct_setPALColour(1, HW_BRIGHT_YELLOW);
    cpct_setPALColour(2, HW_BRIGHT_WHITE);
    cpct_setPALColour(3, HW_BLACK);

    // Clear the 16K screen to pen 0 (mode-1 pixels all 0)
    for (uint16_t i = 0; i < 0x4000; i++)
        CPC_VMEM[i] = 0x00;

    cpct_setDrawCharM1(1, 0);   // foreground pen 1, background pen 0

    // Three lines of text (video rows are 0x50 bytes apart in mode 1)
    cpct_drawStringM1("RAGE1 CPC  --  R2 PoC",        CPC_VMEM + 0x50 *  4 + 8);
    cpct_drawStringM1("MODE 1 TEXT OK",                CPC_VMEM + 0x50 *  6 + 8);
    cpct_drawStringM1("TRANSLATED CPCTELERA ASM",      CPC_VMEM + 0x50 *  8 + 8);
    cpct_drawStringM1("zcc +cpc  (no sdasz80)",        CPC_VMEM + 0x50 * 10 + 8);

    __asm
        di                      ;; freeze for a clean emulator screenshot
    __endasm;
    for (;;) { }
    return 0;
}

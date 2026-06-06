// RAGE1 CPC R2 PoC — mode-1 text rendered on CPC via the translated cpctelera
// primitives in engine/src/cpc/ (cpct_video.asm + cpct_strings_m1.asm).
//
// Proves the Phase 4 R2 pipeline: z88dk +cpc compiles/links the hand-translated
// sdas->z80asm CPC primitives into a bootable .dsk that sets mode 1 + a 4-pen
// palette and draws firmware-font text.
//
// (The R3 PNG->sprite extension that once lived here used cpctelera's
// cpct_img2tileset converter; cpctelera was revoked and removed at R10 — see
// doc/multiplatform-plan/cpc-renderer.md §0 — so this PoC is the R2 text proof.)
//
// Build: see tools/cpc-poc/Makefile.

#include <stdint.h>

// --- C-callable ABI of the translated cpctelera primitives (engine/src/cpc) ---
extern void cpct_setVideoMode( uint8_t mode )                 __z88dk_fastcall;
extern void cpct_setPALColour( uint8_t pen, uint8_t hw_ink )  __z88dk_callee;
extern void cpct_setDrawCharM1( uint8_t fg_pen, uint8_t bg_pen ) __z88dk_callee;
extern void cpct_drawStringM1( void *string, void *video_mem )   __z88dk_callee;

// CPC GA INK values for cpct_setPALColour (it ORs 0x40 internally, so these
// are HW_value - 0x40 = the low 6 bits of the Gate-Array hardware INK).
#define HW_DK_BLUE        0x04    // FW 1  (HW 0x44) — pen 0 (background)
#define HW_BRIGHT_YELLOW  0x0A    // FW 24 (HW 0x4A) — pen 1 (text foreground)
#define HW_BRIGHT_CYAN    0x13    // FW 20 (HW 0x53) — pen 2
#define HW_BRIGHT_RED     0x0C    // FW 6  (HW 0x4C) — pen 3

#define CPC_VMEM          ((uint8_t *)0xC000)
#define CPC_SCR_BYTES_ROW 0x50u    // 80 bytes per pixel row in mode 1

int main(void) {
    __asm
        di                      ;; take the machine from the firmware for the PoC
    __endasm;

    cpct_setVideoMode(1);       // mode 1: 320x200, 4 colours

    cpct_setPALColour(0, HW_DK_BLUE);
    cpct_setPALColour(1, HW_BRIGHT_YELLOW);
    cpct_setPALColour(2, HW_BRIGHT_CYAN);
    cpct_setPALColour(3, HW_BRIGHT_RED);

    // Clear the 16K screen to pen 0 (mode-1 pixels all 0)
    for (uint16_t i = 0; i < 0x4000u; i++)
        CPC_VMEM[i] = 0x00u;

    // R2: firmware-font text via the translated cpct_drawStringM1
    cpct_setDrawCharM1(1, 0);   // foreground pen 1, background pen 0
    cpct_drawStringM1("RAGE1 CPC  --  R2 PoC",            CPC_VMEM + CPC_SCR_BYTES_ROW * 4 + 8);
    cpct_drawStringM1("MODE 1 TEXT via cpct_drawStringM1", CPC_VMEM + CPC_SCR_BYTES_ROW * 6 + 8);
    cpct_drawStringM1("translated cpctelera primitives",   CPC_VMEM + CPC_SCR_BYTES_ROW * 8 + 8);

    __asm
        di                      ;; freeze for a clean emulator screenshot
    __endasm;
    for (;;) { }
    return 0;
}

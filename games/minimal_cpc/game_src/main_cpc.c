// minimal_cpc — RAGE1 CPC static-render test game (Phase R4)
//
// Smallest game that proves the RAGE1 gfx HAL -> cpctelera mapping on real CPC
// hardware.  It supplies its OWN main() so the engine's interrupt-driven game
// loop (datasets / controllers / banking) is NOT linked; the R4 bar is a
// STATIC render exercising:
//   - gfx_init()            -> mode 1 + palette + mono LUT + screen clear
//   - gfx_tile_register()   -> mono glyph cache (8 UDG bytes/cell)  (README §5.8/§5.9)
//   - gfx_tile_put()        -> mono LUT 1bpp->mode-1 blit, BOTH flavours
//                              (registered slot <256, and a >=256 mono pointer)
//   - gfx_print_string()    -> text via the mono glyph path
//   - gfx_cpctel_draw_sprite_cell() -> pre-baked 2bpp mode-1 sprite (README §5.9)
//   - gfx_invalidate()/gfx_update() -> HAL flush (no-op on the direct-write CPC backend)
//
// DEFERRED (documented): real input scan (IN6), audio (AU5), the interrupt
// loop / banking (G8/B6).  All stubbed for R4.
//
// The sprite bytes are pre-baked OFFLINE by tools/cpc_asset_convert.pl from
// game_src/assets/sprite.png and checked in (assets/sprite.c/.h) — NOT via
// datagen's CPC PNG path (that is Phase A5).

#include <stdint.h>

#include "features.h"
#include "rage1/gfx.h"

// Pre-baked mode-1 sprite (4 bytes wide x 16 rows), generated from
// assets/sprite.png by tools/cpc_asset_convert.pl.  <types.h> shim resolves
// cpctelera's u8 typedef (assets/types.h, on the -I path).
#include "assets/sprite.h"

// Public CPC render helper from the cpctel backend (engine/src/gfx_cpctel.c).
extern void gfx_cpctel_draw_sprite_cell( uint8_t row, uint8_t col,
                                         uint8_t *data, uint8_t bw, uint8_t h );

// ---------------------------------------------------------------------------
// A tiny embedded 1bpp mono font (8 bytes/glyph, bit7 = leftmost pixel) for
// just the glyphs this demo prints.  These are the SAME 8-byte UDG bytes the
// ZX build uses — the CPC mono path expands them to mode-1 at blit time
// (README §5.9).  Indexed below by glyph slot.
// ---------------------------------------------------------------------------

// Glyph slot assignments (arbitrary, < 256 = registered mono slot flavour).
enum {
    G_SPACE = 32,
    G_R = 'R', G_A = 'A', G_G = 'G', G_E = 'E', G_1 = '1',
    G_C = 'C', G_P = 'P', G_O = 'O', G_K = 'K',
    G_M = 'M', G_N = 'N', G_I = 'I', G_L = 'L',
    G_TILE = 200   // a decorative solid tile glyph
};

// 8x8 1bpp patterns (".##....." style, MSB = leftmost).  Compact hand-pixelled
// uppercase letters + digit 1 + a filled box tile.
#define ROW(b7,b6,b5,b4,b3,b2,b1,b0) \
    ((uint8_t)((b7<<7)|(b6<<6)|(b5<<5)|(b4<<4)|(b3<<3)|(b2<<2)|(b1<<1)|b0))

static const uint8_t font_R[8] = {
    ROW(1,1,1,1,1,1,0,0), ROW(1,1,0,0,0,1,1,0), ROW(1,1,0,0,0,1,1,0),
    ROW(1,1,1,1,1,1,0,0), ROW(1,1,1,1,0,0,0,0), ROW(1,1,0,1,1,0,0,0),
    ROW(1,1,0,0,1,1,0,0), ROW(0,0,0,0,0,0,0,0) };
static const uint8_t font_A[8] = {
    ROW(0,0,1,1,1,0,0,0), ROW(0,1,1,0,1,1,0,0), ROW(1,1,0,0,0,1,1,0),
    ROW(1,1,0,0,0,1,1,0), ROW(1,1,1,1,1,1,1,0), ROW(1,1,0,0,0,1,1,0),
    ROW(1,1,0,0,0,1,1,0), ROW(0,0,0,0,0,0,0,0) };
static const uint8_t font_G[8] = {
    ROW(0,1,1,1,1,1,0,0), ROW(1,1,0,0,0,1,1,0), ROW(1,1,0,0,0,0,0,0),
    ROW(1,1,0,1,1,1,1,0), ROW(1,1,0,0,0,1,1,0), ROW(1,1,0,0,0,1,1,0),
    ROW(0,1,1,1,1,1,0,0), ROW(0,0,0,0,0,0,0,0) };
static const uint8_t font_E[8] = {
    ROW(1,1,1,1,1,1,1,0), ROW(1,1,0,0,0,0,0,0), ROW(1,1,0,0,0,0,0,0),
    ROW(1,1,1,1,1,0,0,0), ROW(1,1,0,0,0,0,0,0), ROW(1,1,0,0,0,0,0,0),
    ROW(1,1,1,1,1,1,1,0), ROW(0,0,0,0,0,0,0,0) };
static const uint8_t font_1[8] = {
    ROW(0,0,0,1,1,0,0,0), ROW(0,0,1,1,1,0,0,0), ROW(0,0,0,1,1,0,0,0),
    ROW(0,0,0,1,1,0,0,0), ROW(0,0,0,1,1,0,0,0), ROW(0,0,0,1,1,0,0,0),
    ROW(0,0,1,1,1,1,0,0), ROW(0,0,0,0,0,0,0,0) };
static const uint8_t font_C[8] = {
    ROW(0,1,1,1,1,1,0,0), ROW(1,1,0,0,0,1,1,0), ROW(1,1,0,0,0,0,0,0),
    ROW(1,1,0,0,0,0,0,0), ROW(1,1,0,0,0,0,0,0), ROW(1,1,0,0,0,1,1,0),
    ROW(0,1,1,1,1,1,0,0), ROW(0,0,0,0,0,0,0,0) };
static const uint8_t font_P[8] = {
    ROW(1,1,1,1,1,1,0,0), ROW(1,1,0,0,0,1,1,0), ROW(1,1,0,0,0,1,1,0),
    ROW(1,1,1,1,1,1,0,0), ROW(1,1,0,0,0,0,0,0), ROW(1,1,0,0,0,0,0,0),
    ROW(1,1,0,0,0,0,0,0), ROW(0,0,0,0,0,0,0,0) };
static const uint8_t font_O[8] = {
    ROW(0,1,1,1,1,1,0,0), ROW(1,1,0,0,0,1,1,0), ROW(1,1,0,0,0,1,1,0),
    ROW(1,1,0,0,0,1,1,0), ROW(1,1,0,0,0,1,1,0), ROW(1,1,0,0,0,1,1,0),
    ROW(0,1,1,1,1,1,0,0), ROW(0,0,0,0,0,0,0,0) };
static const uint8_t font_K[8] = {
    ROW(1,1,0,0,0,1,1,0), ROW(1,1,0,0,1,1,0,0), ROW(1,1,0,1,1,0,0,0),
    ROW(1,1,1,1,0,0,0,0), ROW(1,1,0,1,1,0,0,0), ROW(1,1,0,0,1,1,0,0),
    ROW(1,1,0,0,0,1,1,0), ROW(0,0,0,0,0,0,0,0) };
static const uint8_t font_M[8] = {
    ROW(1,1,0,0,0,1,1,0), ROW(1,1,1,0,1,1,1,0), ROW(1,1,1,1,1,1,1,0),
    ROW(1,1,0,1,0,1,1,0), ROW(1,1,0,0,0,1,1,0), ROW(1,1,0,0,0,1,1,0),
    ROW(1,1,0,0,0,1,1,0), ROW(0,0,0,0,0,0,0,0) };
static const uint8_t font_N[8] = {
    ROW(1,1,0,0,0,1,1,0), ROW(1,1,1,0,0,1,1,0), ROW(1,1,1,1,0,1,1,0),
    ROW(1,1,0,1,1,1,1,0), ROW(1,1,0,0,1,1,1,0), ROW(1,1,0,0,0,1,1,0),
    ROW(1,1,0,0,0,1,1,0), ROW(0,0,0,0,0,0,0,0) };
static const uint8_t font_I[8] = {
    ROW(0,1,1,1,1,1,1,0), ROW(0,0,0,1,1,0,0,0), ROW(0,0,0,1,1,0,0,0),
    ROW(0,0,0,1,1,0,0,0), ROW(0,0,0,1,1,0,0,0), ROW(0,0,0,1,1,0,0,0),
    ROW(0,1,1,1,1,1,1,0), ROW(0,0,0,0,0,0,0,0) };
static const uint8_t font_L[8] = {
    ROW(1,1,0,0,0,0,0,0), ROW(1,1,0,0,0,0,0,0), ROW(1,1,0,0,0,0,0,0),
    ROW(1,1,0,0,0,0,0,0), ROW(1,1,0,0,0,0,0,0), ROW(1,1,0,0,0,0,0,0),
    ROW(1,1,1,1,1,1,1,0), ROW(0,0,0,0,0,0,0,0) };
static const uint8_t font_space[8] = { 0,0,0,0,0,0,0,0 };

// A decorative tile: a hollow box with a centre dot — exercises the mono LUT
// with a non-trivial pattern.
static uint8_t tile_box[8] = {
    ROW(1,1,1,1,1,1,1,1), ROW(1,0,0,0,0,0,0,1), ROW(1,0,0,1,1,0,0,1),
    ROW(1,0,1,1,1,1,0,1), ROW(1,0,1,1,1,1,0,1), ROW(1,0,0,1,1,0,0,1),
    ROW(1,0,0,0,0,0,0,1), ROW(1,1,1,1,1,1,1,1) };

// Register a glyph into the engine's mono glyph cache (slot < 256).
static void reg( uint8_t slot, const uint8_t *udg ) {
    gfx_tile_register( (gfx_tile_id_t)slot, (uint8_t *)udg );
}

int main(void) {
    // 1. Bring up the renderer through the real engine HAL.
    //    init_gfx() -> gfx_init() (gfx_cpctel.c): mode 1, palette, mono LUT,
    //    glyph cache init, screen clear.
    init_gfx();

    // 2. Register the glyphs we will print (mono slot flavour, < 256).
    reg( G_SPACE, font_space );
    reg( G_R, font_R ); reg( G_A, font_A ); reg( G_G, font_G );
    reg( G_E, font_E ); reg( G_1, font_1 ); reg( G_C, font_C );
    reg( G_P, font_P ); reg( G_O, font_O ); reg( G_K, font_K );
    reg( G_M, font_M ); reg( G_N, font_N );
    reg( G_I, font_I ); reg( G_L, font_L );
    reg( G_TILE, tile_box );

    // 3. Draw a row of the registered tile (mono LUT, < 256 slot flavour).
    {
        uint8_t c;
        for ( c = 2; c < 10; c++ )
            gfx_tile_put( 4, c, (gfx_attr_t)0, (gfx_tile_id_t)G_TILE );
    }

    // 4. Draw the SAME box via the >=256 POINTER flavour (README §5.8): pass
    //    the address of the 8 mono UDG bytes directly.  Proves both tile
    //    dispatch branches land through the mono LUT.
    {
        uint8_t c;
        for ( c = 12; c < 20; c++ )
            gfx_tile_put( 4, c, (gfx_attr_t)0, (gfx_tile_id_t)(uintptr_t)tile_box );
    }

    // 5. Print text through the mono glyph path.
    {
        // "RAGE1 CPC" then "MINIMAL CPC OK"
        gfx_rect_t pos1 = { 0, 0, 0, 0 };
        gfx_print_ctx_t ctx = GFX_PRINT_CTX_INIT( pos1, 0 );
        gfx_print_set_pos( &ctx, 8, 2 );
        gfx_print_string( &ctx, "RAGE1 CPC" );
        gfx_print_set_pos( &ctx, 10, 2 );
        gfx_print_string( &ctx, "MINIMAL CPC OK" );
    }

    // 6. Draw the pre-baked 2bpp sprite (README §5.9 — sprites stay 2bpp).
    //    Placed at cell (1,2): width G_MINIMAL_CPC_SPRITE_W bytes, height H rows.
    gfx_cpctel_draw_sprite_cell( 1, 2,
        (uint8_t *)g_minimal_cpc_sprite,
        G_MINIMAL_CPC_SPRITE_W, G_MINIMAL_CPC_SPRITE_H );
    // A second copy to the right, to make the static layout unambiguous.
    gfx_cpctel_draw_sprite_cell( 1, 30,
        (uint8_t *)g_minimal_cpc_sprite,
        G_MINIMAL_CPC_SPRITE_W, G_MINIMAL_CPC_SPRITE_H );

    // 7. HAL flush (no-op on the direct-write CPC backend, but part of the
    //    contract every backend must accept).
    gfx_update();

    // 8. R4 is a static render: freeze so the emulator screenshot is stable.
    //    (Real interrupt loop / input / audio = G8 / IN6 / AU5.)
    __asm
        di
    __endasm;
    for (;;) { }
    return 0;
}

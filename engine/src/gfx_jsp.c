////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

// ZX arch include routed through the platform shim so this file compiles on
// +cpc (where it is the active CPC backend) as well as ZX; byte-identical on
// ZX — see rage1/platform.h.
#include "rage1/platform.h"

#include "rage1/gfx.h"
#include "rage1/screen.h"
#include "rage1/debug.h"

#include "game_data.h"

#ifdef BUILD_FEATURE_GFX_BACKEND_JSP

// Pool storage.  The recompositing JSP model needs no per-sprite drawing
// buffers — the pool is simply an array of sprite descriptors.
static struct jsp_sprite_s _sprite_pool[ GFX_JSP_MAX_SPRITES ];
// Default/background cell: JSP_CELL_BYTES is 8 on ZX (1bpp UDG) and 16 on CPC
// mode 1 (2bpp); sizing by the macro keeps one blank-cell source on both.
static const uint8_t _blank_tile[ JSP_CELL_BYTES ] = { 0 };

#ifdef GFX_JSP_CPC

// CPC: JSP leaves screen mode + palette programming to the caller (CPC has no
// attribute RAM — colour lives in the gate-array palette; see JSP CPC-USAGE
// §5/§6).  We program mode 1 + a 4-pen palette here, via the hand-translated
// CPC hardware-I/O primitives in engine/src/cpc/ (origin cpctelera, credit
// kept — README §5.13).  Pen values are the resolved default until the
// per-game palette (A8) lands.  hw_ink values are gate-array INKR codes
// (the 0x40 INKR command is OR'd in by cpct_setPALColour/cpct_setBorder).
extern void cpct_setVideoMode( uint8_t mode )                __z88dk_fastcall;
extern void cpct_setPALColour( uint8_t pen, uint8_t hw_ink ) __z88dk_callee;
extern void cpct_setBorder( uint8_t hw_ink )                 __z88dk_fastcall;

#define HW_BLACK        0x14
#define HW_WHITE        0x0B    // bright white
#define HW_YELLOW       0x0A    // bright yellow
#define HW_RED          0x0C    // bright red
#define HW_BORDER_BLUE  0x04

void gfx_init( gfx_attr_t bg_attr, uint8_t bg_char ) {
    (void) bg_attr;     // §5.5: attribute layer is ZX-only, inert on CPC
    (void) bg_char;
    cpct_setVideoMode( 1 );             // mode 1: 320x200, 4 pens
    cpct_setPALColour( 0, HW_BLACK );   // pen 0 = background
    cpct_setPALColour( 1, HW_WHITE );   // pen 1 = foreground (2-colour assets)
    cpct_setPALColour( 2, HW_YELLOW );
    cpct_setPALColour( 3, HW_RED );
    cpct_setBorder( HW_BORDER_BLUE );
    // Clear the 16 KB screen RAM (0xC000-0xFFFF) to pen 0.  Setting the video
    // mode via the gate array does NOT clear VRAM, so the firmware boot screen
    // would otherwise show through the new palette (as speckle) in any cell the
    // engine does not repaint.
    {
        uint8_t *vmem = (uint8_t *) 0xC000;
        uint16_t i;
        for ( i = 0; i < 0x4000u; i++ ) vmem[i] = 0x00u;
    }
    jsp_init( (uint8_t *)_blank_tile, 0 );
    jsp_sprite_pool_init( _sprite_pool, GFX_JSP_MAX_SPRITES );
    gfx_invalidate( &full_screen );
    gfx_update();
}

// CPC rectangle clear.  JSP's own jsp_clear_rect() uses an 8-byte blank cell
// and the ZX firmware-font address (0x3D00) for the char glyph — both ZX-sized;
// on CPC mode 1 a cell is JSP_CELL_BYTES (16), so jsp_draw_background_tile would
// read 8 valid bytes + 8 garbage (the yellow speckle).  Until JSP's library
// gains a CPC-aware clear, RAGE1 clears CPC rects here with the proper
// JSP_CELL_BYTES blank tile.  attr/ch are inert on CPC (README §5.5).
void gfx_jsp_cpc_clear_rect( gfx_rect_t *rect ) __z88dk_fastcall {
    uint8_t r, c;
    for ( r = rect->row; r < rect->row + rect->height; r++ )
        for ( c = rect->col; c < rect->col + rect->width; c++ )
            jsp_draw_background_tile( r, c, (uint8_t *)_blank_tile );
}

#else // ZX

void gfx_init( gfx_attr_t bg_attr, uint8_t bg_char ) {
    (void) bg_char;
    gfx_set_border( GFX_BLACK );
    jsp_init( (uint8_t *)_blank_tile, bg_attr );
    jsp_sprite_pool_init( _sprite_pool, GFX_JSP_MAX_SPRITES );
    gfx_invalidate( &full_screen );
    gfx_update();
}

#endif // GFX_JSP_CPC

gfx_sprite_t *gfx_sprite_create( uint8_t rows, uint8_t cols ) {
#ifdef GFX_JSP_CPC
    // RAGE1 callers count sprite width in 8-px source cells (width_px >> 3).  JSP
    // sizes a descriptor in mode-N byte-columns (= GFX_JSP_CELL_BYTECOLS per 8-px
    // cell: 2 on Mode 1, 4 on Mode 0, 1 on Mode 2 / MONO).  So a 16-px sprite is
    // cols=4 on Mode 1, not 2 — convert here so the footprint + masked blit walk
    // the full frame width (the raw 8-px-cell count under-sizes the sprite to half
    // its byte-columns and it never composites).  gfx_sprite_get_width /
    // gfx_jsp_cpc_in_rect divide by the same factor (exact inverse).  Max factor 4
    // (Mode 0) fits uint8_t for any realistic sprite (cols < 64).  ZX: whole block
    // compiled out -> byte-identical.
    cols = (uint8_t)( cols * GFX_JSP_CELL_BYTECOLS );
#endif
    gfx_sprite_t *s = jsp_sprite_alloc( rows, cols );
    DEBUG_ASSERT( s, PANIC_SPRITE_IS_NULL );
    return s;
}

void gfx_sprite_set_color( gfx_sprite_t *s, gfx_attr_t color ) {
    // 0xF8 mask: preserve PAPER and BRIGHT bits, replace INK only
    // (matches SP1's attr_mask = 0xF8 used in sprite.c)
    jsp_sprite_set_color( s, color, 0xF8 );
}

#ifdef GFX_JSP_CPC
// CPC-correct bounding-box clip test (RAGE1-side; JSP is consumed read-only).
//
// JSP's jsp_sprite_in_rect() computes the sprite's grid span as sc + sp->cols
// (cell coords), with sc = xpos/8 the 8-px pixel-cell column.  That is right on
// ZX, where cols counts 8-px cells; but on CPC cols is in *mode-N byte-columns*
// (GFX_JSP_CELL_BYTECOLS per 8-px cell) — so a 16-px Mode-1 sprite has cols=4
// while it only spans 2 pixel-cells.  Feeding that cols straight into sc + cols
// over-counts the sprite's grid width and parks the hero early near the right/
// bottom edge of the clip rect.  Re-derive the span in 8-px-cell units:
// width_cells = cols / GFX_JSP_CELL_BYTECOLS (the inverse of gfx_sprite_create's
// multiply — keyed off the asset ppb so MONO stays correct), height_cells = rows.
// ZX is byte-identical (this block is compiled out; ZX keeps the original
// jsp_sprite_in_rect call).
static uint8_t gfx_jsp_cpc_in_rect( gfx_sprite_t *s, gfx_rect_t *rect,
                                    gfx_xpos_t x, gfx_ypos_t y )
{
    uint8_t sc = (uint8_t)( x >> 3 );           // 8-px-cell column
    uint8_t sr = (uint8_t)( y >> 3 );           // 8-px-cell row
    uint8_t wc = (uint8_t)( s->cols / GFX_JSP_CELL_BYTECOLS );   // width in 8-px cells
    if ( sc < rect->col )                            return 0;
    if ( sr < rect->row )                            return 0;
    if ( sc + wc       > rect->col + rect->width  )  return 0;
    if ( sr + s->rows  > rect->row + rect->height )  return 0;
    return 1;
}
#endif // GFX_JSP_CPC

void gfx_jsp_move_sprite_clipped( gfx_sprite_t *s, gfx_rect_t *clip,
                                   uint8_t *frame, gfx_xpos_t x, gfx_ypos_t y )
{
    if ( frame == NULL ) {
        jsp_sprite_park( s );
        return;
    }
#ifdef GFX_JSP_CPC
    if ( clip && !gfx_jsp_cpc_in_rect( s, clip, x, y ) ) {
#else
    if ( clip && !jsp_sprite_in_rect( s, clip, x, y ) ) {
#endif
        jsp_sprite_park( s );
        return;
    }
    jsp_move_sprite_mask2_frame( s, frame, x, y );
}

#endif // BUILD_FEATURE_GFX_BACKEND_JSP

////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

//
// CPC 'cpctel' gfx backend — REAL mode-1 renderer (Phase R4; was a G7 stub).
//
// Real bodies for the 'cpctel' gfx backend, guarded by
// BUILD_FEATURE_GFX_BACKEND_CPCTEL.  Maps the audited gfx_* HAL onto the
// translated cpctelera primitives in engine/src/cpc/:
//   cpct_video.asm      — cpct_setVideoMode, cpct_setPALColour
//   cpct_gfx_m1.asm     — cpct_getScreenPtr, cpct_drawSprite, cpct_setBorder
//   cpct_strings_m1.asm — cpct_setDrawCharM1, cpct_drawStringM1 (firmware font)
//
// Rendering model: DIRECT WRITE (immediate mode), no back buffer.  Per
// gfx.md §3.4 the engine contract gfx_invalidate + gfx_update is satisfied by
// the immediate-mode option: invalidate/update are no-ops; every gfx_tile_put
// / sprite draw writes straight to video memory at 0xC000.
//
// Two-layer colour model (gfx.md §2.1 / README §5.5): the ZX `attr` byte is
// inert on CPC and (void)-discarded EVERYWHERE except gfx_set_border (border
// ink is a real CPC concept).  Colour comes from the bitmap layer plus the
// per-game pen palette set up in gfx_init.
//
// Mono path (README §5.9): in mono mode BTile/glyph cells are 8 mono UDG
// bytes (byte-identical to ZX).  gfx_tile_register caches the 8 bytes; the
// blit (gfx_tile_put) bit-expands each row to 2 mode-1 bytes through the
// 512-byte mono LUT built once here at gfx_init from the resolved pen pair.
//
// DEFERRED (documented):
//   - Per-game CPC_COLOR_MAP resolution of the mono pen pair (README §5.10)
//     is Phase A5; here the pen pair is a fixed backend default.
//   - Full-colour (>=256 pre-baked 2bpp) BTile flavour: the >=256 pointer
//     branch currently treats the pointee as 8 mono UDG bytes (mono mode,
//     §5.9).  Pre-baked 2bpp BTiles arrive with A5.
//   - Sprite movement / masked sprite / clipping (gfx_cpctel_move_sprite_*)
//     is a minimal park/no-op here; the interrupt-driven sprite loop is G8.
//

#include "rage1/platform.h"

#include "rage1/gfx.h"
#include "rage1/screen.h"
#include "rage1/debug.h"

#include "game_data.h"

#ifdef BUILD_FEATURE_GFX_BACKEND_CPCTEL

// ---------------------------------------------------------------------------
// C-callable ABI of the translated cpctelera primitives (engine/src/cpc/).
// ---------------------------------------------------------------------------
extern void  cpct_setVideoMode( uint8_t mode )                    __z88dk_fastcall;
extern void  cpct_setPALColour( uint8_t pen, uint8_t hw_ink )     __z88dk_callee;
extern void  cpct_setBorder( uint8_t hw_ink )                     __z88dk_fastcall;
extern uint8_t *cpct_getScreenPtr( void *scr, uint8_t x, uint8_t y ) __z88dk_callee;
extern void  cpct_drawSprite( void *src, void *mem, uint8_t w, uint8_t h ) __z88dk_callee;

// ---------------------------------------------------------------------------
// CPC mode-1 geometry / video base.
// ---------------------------------------------------------------------------
#define CPC_VMEM            ((uint8_t *)0xC000)
#define CPC_BYTES_PER_CELL  2u      // mode 1: 8px-wide cell = 2 bytes (4px/byte)

// Resolved mono pen pair (README §5.10 — fixed default until A5 wires
// per-game CPC_COLOR_MAP).  pen 0 = background, pen 1 = foreground.
#define MONO_BG_PEN         0u
#define MONO_FG_PEN         1u

// CPC Gate-Array hardware ink codes — the RAW 6-bit cpctelera HW_* values
// (external/cpctelera/.../src/video/colours.h enum CPCT_HW_Colour).  Our
// cpct_setPALColour / cpct_setBorder primitives OR in the 0x40 INKR command
// themselves, so these must be the raw codes (0x00..0x1F), NOT pre-ORed GA
// bytes.  All entries below are raw codes for consistency (the earlier mix of
// 0x14 raw and 0x4B/0x4A/0x4C/0x44 happened to work only because the GA reads
// just the low 6 bits — corrected to all-raw per the canonical table).
// Palette: pen 0 = black, pen 1 = bright white, pen 2 = bright yellow,
//          pen 3 = bright red.
#define HW_BLACK            0x14    // HW_BLACK
#define HW_WHITE            0x0B    // HW_BRIGHT_WHITE
#define HW_YELLOW           0x0A    // HW_BRIGHT_YELLOW
#define HW_RED              0x0C    // HW_BRIGHT_RED
#define HW_BORDER_BLUE      0x04    // HW_BLUE

// ---------------------------------------------------------------------------
// Mono 1bpp -> mode-1 2bpp lookup table (README §5.9).
//   mono_lut[b] = { hi, lo } : the 8 pixels of mono byte b (bit7 leftmost)
//   become two mode-1 bytes (pixels 0..3 -> hi, pixels 4..7 -> lo).  Each
//   1-pixel uses MONO_FG_PEN, each 0-pixel uses MONO_BG_PEN.
// Built once at gfx_init from the resolved pen pair.
// ---------------------------------------------------------------------------
static uint8_t mono_lut[256][2];

// Pack 4 mode-1 pixels (each pen 0..3) into one byte.  Mode-1 byte layout
// (cpctelera cpctm_px2byteM1 / dc_mode1_ct = {0x00,0xF0,0x0F,0xFF}):
// per pixel, colour BIT0 -> the HIGH-nibble bit, colour BIT1 -> the LOW-nibble
// bit.  i.e. pixel A: bit0->byte bit7, bit1->byte bit3;  B: bit6/bit2;
// C: bit5/bit1;  D: bit4/bit0.  (pen 1 -> 0xF0, pen 2 -> 0x0F — verified
// against the dc_mode1_ct table in engine/src/cpc/cpct_strings_m1.asm.)
static uint8_t pack4_m1( uint8_t a, uint8_t b, uint8_t c, uint8_t d ) {
    uint8_t out = 0;
    if ( a & 1 ) out |= 0x80;   if ( a & 2 ) out |= 0x08;
    if ( b & 1 ) out |= 0x40;   if ( b & 2 ) out |= 0x04;
    if ( c & 1 ) out |= 0x20;   if ( c & 2 ) out |= 0x02;
    if ( d & 1 ) out |= 0x10;   if ( d & 2 ) out |= 0x01;
    return out;
}

static void build_mono_lut( void ) {
    uint16_t v;
    for ( v = 0; v < 256; v++ ) {
        uint8_t b = (uint8_t)v;
        // pixels left-to-right = bits 7..0
        uint8_t p[8];
        uint8_t i;
        for ( i = 0; i < 8; i++ )
            p[i] = ( b & ( 0x80 >> i ) ) ? MONO_FG_PEN : MONO_BG_PEN;
        mono_lut[v][0] = pack4_m1( p[0], p[1], p[2], p[3] );
        mono_lut[v][1] = pack4_m1( p[4], p[5], p[6], p[7] );
    }
}

// ---------------------------------------------------------------------------
// Glyph / tile cache (README §5.8 / §5.9).  256 mono glyph slots; each holds
// the 8 mono UDG bytes registered via gfx_tile_register.  gfx_tile_put with
// tile<256 indexes this cache; tile>=256 is a pointer to 8 mono UDG bytes.
// We keep the mono bytes (not the expanded block) and expand at blit time via
// the LUT (small, and keeps the cache the same size as ZX).
// ---------------------------------------------------------------------------
static uint8_t  glyph_cache[256][8];
static uint8_t  glyph_valid[256];

// ---------------------------------------------------------------------------
// Blit one 8x8 mono cell (8 UDG bytes) to cell (row,col), expanding each row
// to 2 mode-1 bytes via the mono LUT.  Direct write to video memory.
//
// SCREEN-BOUNDS CLAMP (G8a): the mode-1 grid is 40 cols x 25 rows (320x200 px,
// 16 KB at 0xC000..0xFFFF).  A cell whose column >= GFX_SCREEN_COLS or row >=
// GFX_SCREEN_ROWS computes a video address OUTSIDE that 16 KB window
// (cpct_getScreenPtr would wrap or run past the screen and corrupt RAM).  With
// 16-bit sprite/enemy coordinates (G8a) an edge-placed or partially-off-screen
// sprite can produce such out-of-range cells, so we SKIP them here — the single
// chokepoint every BTile / sprite / glyph / clear blit funnels through.  This
// matches the CPC 0x800-per-pixel-line / 0xC050-wrap addressing: clamping at
// the cell-grid boundary keeps every emitted address within [0xC000,0xFFFF].
// ---------------------------------------------------------------------------
static void blit_mono_cell( uint8_t row, uint8_t col, const uint8_t *udg ) {
    uint8_t x_byte;
    uint8_t y0;
    uint8_t r;

    // off-grid cell: skip entirely (would write past the 16 KB screen)
    if ( col >= GFX_SCREEN_COLS || row >= GFX_SCREEN_ROWS )
        return;

    x_byte = (uint8_t)( col * CPC_BYTES_PER_CELL );
    y0     = (uint8_t)( row * 8 );
    for ( r = 0; r < 8; r++ ) {
        uint8_t *dst = cpct_getScreenPtr( CPC_VMEM, x_byte, (uint8_t)( y0 + r ) );
        uint8_t  b   = udg[ r ];
        dst[0] = mono_lut[ b ][0];
        dst[1] = mono_lut[ b ][1];
    }
}

/////////////////////////////////////
// Initialization
/////////////////////////////////////

void gfx_init( gfx_attr_t bg_attr, uint8_t bg_char ) {
    (void) bg_attr;     // §2.1: attr layer is ZX-only, inert on CPC
    (void) bg_char;

    // 1. mode 1 (320x200, 4 colours)
    cpct_setVideoMode( 1 );

    // 2. resolved palette (README §5.10 default until A5)
    cpct_setPALColour( 0, HW_BLACK );
    cpct_setPALColour( 1, HW_WHITE );
    cpct_setPALColour( 2, HW_YELLOW );
    cpct_setPALColour( 3, HW_RED );
    cpct_setBorder( HW_BORDER_BLUE );

    // 3. build the mono 1bpp->2bpp LUT from the resolved pen pair (§5.9)
    build_mono_lut();

    // 4. init glyph cache
    {
        uint16_t i;
        for ( i = 0; i < 256; i++ ) glyph_valid[i] = 0;
    }

    // 5. clear the screen to the background pen (mono LUT of a blank cell)
    gfx_invalidate( &full_screen );
    gfx_update();
    {
        // clear all 16K of video RAM to pen 0 (all-zero pixels)
        uint16_t i;
        for ( i = 0; i < 0x4000u; i++ ) CPC_VMEM[i] = 0x00u;
    }
}

/////////////////////////////////////
// Sprite lifecycle
/////////////////////////////////////

// Minimal sprite descriptor pool (same shape idea as JSP's _sprite_pool).
#define CPC_SPRITE_POOL_SIZE  16
static gfx_sprite_t sprite_pool[ CPC_SPRITE_POOL_SIZE ];
static uint8_t      sprite_pool_used;

gfx_sprite_t *gfx_sprite_create( uint8_t rows, uint8_t cols ) {
    gfx_sprite_t *s;
    if ( sprite_pool_used >= CPC_SPRITE_POOL_SIZE )
        return &sprite_pool[ CPC_SPRITE_POOL_SIZE - 1 ];   // overflow guard
    s = &sprite_pool[ sprite_pool_used++ ];
    s->height = rows;       // cells
    s->width  = cols;       // cells
    s->row = 0; s->col = 0;
    s->prev_row = 0; s->prev_col = 0;
    s->drawn = 0;
    return s;
}

void gfx_sprite_set_color( gfx_sprite_t *s, gfx_attr_t color ) {
    (void) s;
    (void) color;       // §2.1: colour is baked into the sprite bitmap on CPC
}

/////////////////////////////////////
// Direct-write renderer (no back buffer)
/////////////////////////////////////

void gfx_cpctel_invalidate( gfx_rect_t *rect ) {
    (void) rect;        // immediate-mode renderer: nothing to mark dirty
}

void gfx_cpctel_update( void ) {
    // immediate-mode renderer: writes already landed in video memory
}

void gfx_cpctel_set_border( uint8_t color ) {
    // gfx_set_border is the SINGLE attr-consuming entry point on CPC.
    // Map ZX colour 0..7 (black,blue,red,magenta,green,cyan,yellow,white) ->
    // a CPC RAW hardware ink code (cpct_setBorder ORs in 0x40 itself).  Values
    // are the canonical cpctelera HW_* codes (src/video/colours.h).
    static const uint8_t zx2hw[8] = {
        0x14 /*black:   HW_BLACK         */, 0x04 /*blue:    HW_BLUE          */,
        0x0C /*red:     HW_BRIGHT_RED    */, 0x0D /*magenta: HW_BRIGHT_MAGENTA*/,
        0x16 /*green:   HW_GREEN         */, 0x06 /*cyan:    HW_CYAN          */,
        0x0A /*yellow:  HW_BRIGHT_YELLOW */, 0x0B /*white:   HW_BRIGHT_WHITE  */
    };
    cpct_setBorder( zx2hw[ color & 0x07 ] );
}

void gfx_cpctel_sprite_destroy( gfx_sprite_t *s ) {
    (void) s;           // pool is bump-allocated for R4; real free is G8
}

// ---------------------------------------------------------------------------
// SP1-frame -> mono-cell decode (Phase G8).
//
// datagen emits sprite frames in SP1/JSP COLUMN-MAJOR interleaved layout
// (tools/datagen.pl generate_sprite): from the frame pointer, the data is
// laid out column by column; within a column each scanline is a (mask,pixel)
// PAIR (mask first).  For a sprite `h` cells tall, the column stride is
// (h+1)*16 bytes (the +1 is the leading blank row already skipped for column 0
// by datagen's +16 frame offset).  The pixel byte for sprite cell (cr,cc),
// scanline s (0..7) is therefore at:
//     frame[ cc*(h+1)*16 + (cr*8 + s)*2 + 1 ]
// In CPC MONO mode we render the pixel layer only (README §5.9; mask-aware
// compositing is A5/later) — we pull each cell's 8 pixel bytes and blit them
// through the same mono LUT used for BTiles/glyphs.
// ---------------------------------------------------------------------------
static void blit_sprite_frame( uint8_t cell_row, uint8_t cell_col,
                               const uint8_t *frame, uint8_t w, uint8_t h ) {
    uint8_t cc, cr, s;
    uint16_t col_stride = (uint16_t)( h + 1 ) * 16u;
    for ( cc = 0; cc < w; cc++ ) {
        for ( cr = 0; cr < h; cr++ ) {
            uint8_t cell[8];
            uint16_t base = (uint16_t)cc * col_stride;
            for ( s = 0; s < 8; s++ )
                cell[s] = frame[ base + (uint16_t)( ( cr * 8 + s ) * 2 + 1 ) ];
            blit_mono_cell( (uint8_t)( cell_row + cr ), (uint8_t)( cell_col + cc ), cell );
        }
    }
}

// Erase a sprite's w x h cell footprint at (cell_row,cell_col) to background pen.
static void erase_sprite_cells( uint8_t cell_row, uint8_t cell_col,
                                uint8_t w, uint8_t h ) {
    static const uint8_t blank[8] = { 0,0,0,0,0,0,0,0 };
    uint8_t cc, cr;
    for ( cc = 0; cc < w; cc++ )
        for ( cr = 0; cr < h; cr++ )
            blit_mono_cell( (uint8_t)( cell_row + cr ), (uint8_t)( cell_col + cc ), blank );
}

// Move a sprite to pixel position (x,y).  Direct-write renderer: we erase the
// previous cell footprint, then draw the new frame.  Movement is cell-aligned
// on CPC for G8 (functional bar — gfx.md §G8-5): pixel coords are quantised to
// the 8x8 cell grid (col = x>>3, row = y>>3).  Sub-cell-smooth masked shifting
// is a later refinement; cell-granular motion is enough to prove the loop is
// live (the enemy visibly steps across the screen).  A NULL frame (sprite park)
// just erases.
void gfx_cpctel_move_sprite_clipped( gfx_sprite_t *s, gfx_rect_t *clip,
                                     uint8_t *frame, gfx_xpos_t x, gfx_ypos_t y ) {
    uint8_t new_row = (uint8_t)( y >> 3 );
    uint8_t new_col = (uint8_t)( x >> 3 );

    (void) clip;        // CPC clipping refinement is later; cell math stays on-grid

    // erase the previous footprint (if we have drawn before)
    if ( s->drawn )
        erase_sprite_cells( s->prev_row, s->prev_col, s->width, s->height );

    // park (NULL frame): leave it erased and off the live area
    if ( frame == 0 ) {
        s->drawn = 0;
        s->row = new_row;
        s->col = new_col;
        return;
    }

    // draw the new frame at the new cell position
    blit_sprite_frame( new_row, new_col, frame, s->width, s->height );

    // remember where we drew so the next move can erase it
    s->row = new_row;     s->col = new_col;
    s->prev_row = new_row; s->prev_col = new_col;
    s->drawn = 1;
}

/////////////////////////////////////
// Tile drawing (README §5.8 dispatch + §5.9 mono LUT)
/////////////////////////////////////

void gfx_cpctel_tile_register( gfx_tile_id_t idx, uint8_t *graphic ) {
    // graphic is ALWAYS 8 mono UDG bytes (gfx.md §2.3 invariant).
    if ( idx < 256 ) {
        uint8_t i;
        for ( i = 0; i < 8; i++ ) glyph_cache[ idx ][ i ] = graphic[ i ];
        glyph_valid[ idx ] = 1;
    }
}

void gfx_cpctel_tile_put( uint8_t row, uint8_t col, gfx_attr_t attr, gfx_tile_id_t tile ) {
    (void) attr;        // §2.1: attr discarded on CPC
    if ( tile < 256 ) {
        // registered mono glyph slot (§5.8 small-id flavour)
        if ( glyph_valid[ tile ] )
            blit_mono_cell( row, col, glyph_cache[ tile ] );
        else {
            // unregistered glyph: blank cell (background pen)
            static const uint8_t blank[8] = { 0,0,0,0,0,0,0,0 };
            blit_mono_cell( row, col, blank );
        }
    } else {
        // pointer flavour (§5.8): in mono mode this points at 8 mono UDG bytes
        // (README §5.9).  Pre-baked 2bpp full-colour BTiles arrive with A5.
        blit_mono_cell( row, col, (const uint8_t *)(uintptr_t)tile );
    }
}

/////////////////////////////////////
// Rectangle operations
/////////////////////////////////////

void gfx_cpctel_clear_rect( gfx_rect_t *rect, gfx_attr_t attr, uint8_t ch, uint8_t flags ) {
    (void) attr;        // §2.1: attr discarded on CPC
    (void) flags;       // CPC clears to background pen regardless of CLEAR_* bits
    // Fill the rect with glyph `ch` (or background pen if it is a blank).
    static const uint8_t blank[8] = { 0,0,0,0,0,0,0,0 };
    uint8_t r, c;
    for ( r = 0; r < rect->height; r++ ) {
        for ( c = 0; c < rect->width; c++ ) {
            uint8_t gr = (uint8_t)( rect->row + r );
            uint8_t gc = (uint8_t)( rect->col + c );
            if ( ch != ' ' && ch != 0 && glyph_valid[ ch ] )
                blit_mono_cell( gr, gc, glyph_cache[ ch ] );
            else
                blit_mono_cell( gr, gc, blank );
        }
    }
}

/////////////////////////////////////
// Text printing (routed through the mono glyph path — §5.9)
/////////////////////////////////////

void gfx_cpctel_print_set_pos( gfx_print_ctx_t *ctx, uint8_t row, uint8_t col ) {
    // Stash the cursor in the (otherwise-inert-on-CPC) attr/bounds fields.
    // We reuse bounds->row/col as the print cursor.
    if ( ctx->bounds ) {
        ctx->bounds->row = row;
        ctx->bounds->col = col;
    }
}

void gfx_cpctel_print_string( gfx_print_ctx_t *ctx, char *str ) {
    uint8_t row = ctx->bounds ? ctx->bounds->row : 0;
    uint8_t col = ctx->bounds ? ctx->bounds->col : 0;
    while ( *str ) {
        uint8_t ch = (uint8_t)*str++;
        if ( glyph_valid[ ch ] )    // ch is a byte: always a valid 0..255 slot
            blit_mono_cell( row, col, glyph_cache[ ch ] );
        col++;
    }
    if ( ctx->bounds ) ctx->bounds->col = col;
}

/////////////////////////////////////
// Public CPC render helper (test games / future boot path)
/////////////////////////////////////

void gfx_cpctel_draw_sprite_cell( uint8_t row, uint8_t col,
                                  uint8_t *data, uint8_t bw, uint8_t h ) {
    // Pre-baked mode-1 sprite (solid, no mask): hand straight to the
    // translated cpct_drawSprite primitive at the cell's video address.
    uint8_t x_byte = (uint8_t)( col * CPC_BYTES_PER_CELL );
    uint8_t y0     = (uint8_t)( row * 8 );
    uint8_t *dst   = cpct_getScreenPtr( CPC_VMEM, x_byte, y0 );
    cpct_drawSprite( data, dst, bw, h );
}

#endif // BUILD_FEATURE_GFX_BACKEND_CPCTEL

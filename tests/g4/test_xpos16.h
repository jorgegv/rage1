/* Phase G4 compile-cleanly-with-uint16 test header.
 *
 * Mirrors the relevant slice of the gfx HAL contract that the engine talks
 * to, but with `gfx_xpos_t` / `gfx_ypos_t` widened to `uint16_t` — the way
 * the CPC and ZX Next Layer-2 backends (Phase G7+) will define them.
 *
 * The point of this header is NOT to be a real backend; it is to expose
 * the same set of typedefs, macros and prototypes that engine code uses,
 * so that the engine-side patterns (HAL calls with pixel coordinates,
 * compile-time arithmetic against HERO_MOVE_* defines, etc.) can be
 * compiled with `-Wall -Werror -Wconversion` and shown to be type-safe
 * under the wider typedef.
 *
 * The test does NOT link against any z88dk / cpctelera library, and the
 * functions referenced here are stubs in test_xpos16.c.
 */

#ifndef _TEST_XPOS16_H
#define _TEST_XPOS16_H

#include <stdint.h>

/* --- HAL types, wider variant --- */
typedef uint8_t  gfx_attr_t;
typedef uint16_t gfx_xpos_t;   /* widened: CPC 320-pixel range */
typedef uint16_t gfx_ypos_t;   /* widened: future Layer-2 320x256 */

/* Opaque sprite handle and rect — exact shape does not matter for this
 * compile-only test; we just need a type. */
typedef struct gfx_sprite_s { int dummy; } gfx_sprite_t;
typedef struct gfx_rect_s   { uint8_t row, col, width, height; } gfx_rect_t;
typedef struct gfx_print_ctx_s {
    gfx_rect_t *bounds;
    uint8_t     flags;
    uint8_t     row, col;
    uint8_t     reserved;
    gfx_attr_t  attr;
    uint8_t     pad0, pad1;
} gfx_print_ctx_t;

/* --- Constants --- */
#define GFX_CLEAR_TILE        0x01u
#define GFX_CLEAR_COLOUR      0x02u
#define GFX_PSS_INVALIDATE    0x04u
#define GFX_PRINT_CTX_INIT(area, attr) \
    { &(area), GFX_PSS_INVALIDATE, 0, 0, 0, (attr), 0, 0 }

#define GFX_BLACK   0
#define GFX_BLUE    1
#define GFX_WHITE   7
#define GFX_ATTR(ink, paper, bright, flash) \
    ( (gfx_attr_t)( ((flash) << 7) | ((bright) << 6) | ((paper) << 3) | (ink) ) )
#define GFX_DEFAULT_BG_ATTR GFX_ATTR(GFX_BLACK, GFX_WHITE, 0, 0)

/* --- HAL prototypes that consume pixel coordinates ---
 *
 * The argument types use gfx_xpos_t / gfx_ypos_t so the engine source can
 * stay literally the same as on ZX.  All bodies are stubs in
 * test_xpos16.c.
 */
extern void gfx_init( gfx_attr_t bg_attr, uint8_t bg_char );
extern gfx_sprite_t *gfx_sprite_create( uint8_t rows, uint8_t cols );
extern void gfx_sprite_set_color( gfx_sprite_t *s, gfx_attr_t color );
extern void gfx_sprite_destroy( gfx_sprite_t *s );
extern void gfx_set_border( gfx_attr_t color );

/* Pixel-coordinate APIs — these are the load-bearing ones for G4 */
extern void gfx_sprite_move_pixel( gfx_sprite_t *s, gfx_rect_t *clip,
                                   uint8_t *frame, gfx_xpos_t x, gfx_ypos_t y );
extern void gfx_sprite_move_cell( gfx_sprite_t *s, gfx_rect_t *clip,
                                  uint8_t *frame, uint8_t row, uint8_t col );

/* --- Simulated emission from datagen for movement bounds ---
 *
 * The real game_data.h emits these as bare integer literals via #define.
 * On CPC the same #defines will fit gfx_xpos_t == uint16_t; we synthesise
 * them here with the same shape the generator uses today.
 */
#define HERO_MOVE_XMIN    0
#define HERO_MOVE_XMAX    312    /* CPC mode 1: 320 - 8 (sprite width) */
#define HERO_MOVE_YMIN    0
#define HERO_MOVE_YMAX    192    /* placeholder; G4 just needs the type to flow */

/* --- ffp16_t / position_data_s as defined in rage1/types.h ---
 *
 * Per the Risk R3 decision recorded in types.h, these are NOT widened on
 * ZX, and on CPC a *parallel* `position16_t` / `ffp24_t` would be added.
 * For this compile-only test we keep the ZX layout: it must still compile
 * cleanly even when gfx_xpos_t is wider, because the engine call sites
 * pass `position.x.part.integer` (a uint8_t) into APIs that now take
 * gfx_xpos_t (a uint16_t).  Widening narrow -> wide is a value-preserving
 * promotion in C and must produce no -Wconversion warning.
 */
typedef union {
    struct {
        uint8_t fraction;
        uint8_t integer;
    } part;
    uint16_t value;
} ffp16_t;

struct position_data_s {
    ffp16_t x, y;
    uint8_t xmax, ymax;
};

#endif /* _TEST_XPOS16_H */

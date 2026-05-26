/* Phase G4 compile-cleanly-with-uint16 test driver.
 *
 * Exercises the wide-coord HAL signatures from test_xpos16.h using the
 * exact call patterns that engine/src/{hero,enemy,bullet}.c use today on
 * ZX.  The test only needs to *compile cleanly*: no linking, no execution.
 *
 * Build (host gcc / clang, just to verify type-safety):
 *
 *   gcc -Wall -Werror -Wconversion -Wno-unused-variable \
 *       -c tests/g4/test_xpos16.c -o /dev/null
 *
 * If this command exits 0 the typedef widening is engine-source-safe.
 */

#include "test_xpos16.h"

#include <stddef.h>

/* Stub bodies — the test does not link, but we satisfy the prototypes so
 * everything compiles as a single translation unit if needed. */
void gfx_init( gfx_attr_t bg_attr, uint8_t bg_char )            { (void)bg_attr; (void)bg_char; }
gfx_sprite_t *gfx_sprite_create( uint8_t rows, uint8_t cols )   { (void)rows; (void)cols; return NULL; }
void gfx_sprite_set_color( gfx_sprite_t *s, gfx_attr_t color )  { (void)s; (void)color; }
void gfx_sprite_destroy( gfx_sprite_t *s )                      { (void)s; }
void gfx_set_border( gfx_attr_t color )                         { (void)color; }
void gfx_sprite_move_pixel( gfx_sprite_t *s, gfx_rect_t *clip,
                            uint8_t *frame, gfx_xpos_t x, gfx_ypos_t y ) {
    (void)s; (void)clip; (void)frame; (void)x; (void)y;
}
void gfx_sprite_move_cell( gfx_sprite_t *s, gfx_rect_t *clip,
                           uint8_t *frame, uint8_t row, uint8_t col ) {
    (void)s; (void)clip; (void)frame; (void)row; (void)col;
}

/* Fake game-area clip rect, like real engine's game_area */
static gfx_rect_t test_game_area = { 0, 0, 32, 24 };

/* Fake hero-style state — mirrors hero_info_s shape we care about */
struct test_hero_s {
    gfx_sprite_t              *sprite;
    struct position_data_s     position;
};

/* Mimics hero.c:hero_set_position_x */
static void test_hero_set_position_x( struct test_hero_s *h, uint8_t x ) {
    h->position.x.value = (uint16_t)(256 * x);
    h->position.xmax    = (uint8_t)(h->position.x.part.integer + 7);
}

/* Mimics hero.c:hero_draw */
static void test_hero_draw( struct test_hero_s *h, uint8_t *frame ) {
    /* On the wide-coord backend, .x.part.integer (uint8_t) promotes to
     * gfx_xpos_t (uint16_t) for the call.  This must NOT trip -Wconversion. */
    gfx_sprite_move_pixel(
        h->sprite,
        &test_game_area,
        frame,
        h->position.x.part.integer,
        h->position.y.part.integer
    );
}

/* Mimics banked hero.c:hero_can_move_in_direction movement-bound checks.
 * HERO_MOVE_YMIN * 256 evaluates at compile time and must compare cleanly
 * against a uint16_t .value field even when gfx_*pos_t is wider. */
static int test_hero_can_move_up( struct test_hero_s *h ) {
    if ( h->position.y.value <= (uint16_t)(HERO_MOVE_YMIN * 256) )
        return 0;
    return 1;
}

static int test_hero_can_move_right( struct test_hero_s *h ) {
    /* HERO_MOVE_XMAX may be >255 on CPC; the cast to uint16_t below makes
     * the wider compare well-defined.  This mirrors what the per-platform
     * sibling-tree emission will look like. */
    if ( h->position.x.value >= (uint16_t)(HERO_MOVE_XMAX * 256) )
        return 0;
    return 1;
}

/* Mimics bullet.c bound checks (using position.x.part.integer which is
 * uint8_t on ZX but promotes cleanly to gfx_xpos_t). */
static int test_bullet_out_of_bounds( struct position_data_s *pos,
                                      uint8_t bullet_width ) {
    gfx_xpos_t right = (gfx_xpos_t)(pos->x.part.integer + bullet_width);
    if ( right > (gfx_xpos_t)HERO_MOVE_XMAX )
        return 1;
    return 0;
}

/* Top-level "smoke" exerciser — not called, just kept reachable for the
 * compiler to type-check everything. */
int test_xpos16_smoke( void ) {
    struct test_hero_s hero;
    hero.sprite = gfx_sprite_create( 2, 2 );
    test_hero_set_position_x( &hero, 16 );
    test_hero_draw( &hero, (uint8_t *)0 );
    gfx_init( GFX_DEFAULT_BG_ATTR, ' ' );
    gfx_set_border( GFX_BLUE );
    gfx_sprite_destroy( hero.sprite );

    if ( test_hero_can_move_up( &hero ) || test_hero_can_move_right( &hero ) )
        return 1;
    if ( test_bullet_out_of_bounds( &hero.position, 8 ) )
        return 2;

    /* Movement bounds must be representable in the widened typedef. */
    gfx_xpos_t xmin = (gfx_xpos_t)HERO_MOVE_XMIN;
    gfx_xpos_t xmax = (gfx_xpos_t)HERO_MOVE_XMAX;
    gfx_ypos_t ymin = (gfx_ypos_t)HERO_MOVE_YMIN;
    gfx_ypos_t ymax = (gfx_ypos_t)HERO_MOVE_YMAX;
    (void)xmin; (void)xmax; (void)ymin; (void)ymax;

    return 0;
}

/* A non-static `main` so the file is also a complete TU compileable as a
 * stand-alone executable target if needed; default Makefile compiles to
 * /dev/null which only checks the type system. */
int main( void ) {
    return test_xpos16_smoke();
}

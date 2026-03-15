////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _GFX_JSP_H
#define _GFX_JSP_H

#include <jsp.h>

//--- Types ---
typedef struct jsp_sprite_s      gfx_sprite_t;
typedef struct jsp_rect          gfx_rect_t;
typedef struct jsp_print_ctx     gfx_print_ctx_t;

//--- Constants ---
#define GFX_CLEAR_TILE              JSP_RFLAG_TILE
#define GFX_CLEAR_COLOUR            JSP_RFLAG_COLOUR
#define GFX_PSS_INVALIDATE          0x00    // unused in JSP backend
#define GFX_PRINT_CTX_INIT(a,at)    JSP_PRINT_CTX_INIT((a),(at))

//--- Initialization ---
// gfx_init() is a real function defined in gfx_jsp.c
#define gfx_invalidate(rect)                jsp_invalidate_rect(rect)
#define gfx_update()                        jsp_redraw()

//--- Sprite lifecycle ---
// gfx_sprite_create() is a real function defined in gfx_jsp.c
#define gfx_sprite_destroy(s)               jsp_sprite_free(s)
// gfx_sprite_set_color() is a real function defined in gfx_jsp.c
#define gfx_sprite_set_threshold(s,xt,yt)   /* no-op: JSP has no threshold concept */

//--- Sprite movement ---
#define gfx_sprite_move_pixel(s,clip,fr,x,y) \
    gfx_jsp_move_sprite_clipped((s),(clip),(fr),(x),(y))
#define gfx_sprite_move_cell(s,clip,fr,r,c) \
    gfx_jsp_move_sprite_clipped((s),(clip),(fr),(c)*8,(r)*8)

//--- Sprite query ---
#define gfx_sprite_get_row(s)               ((s)->ypos / 8)
#define gfx_sprite_get_col(s)               ((s)->xpos / 8)
#define gfx_sprite_get_width(s)             ((s)->cols)
#define gfx_sprite_get_height(s)            ((s)->rows)

//--- Tile drawing ---
#define gfx_tile_put(r,c,attr,tile)         jsp_tile_put((r),(c),(attr),(tile))
#define gfx_tile_register(idx,gfx)          jsp_tile_register((idx),(gfx))

//--- Rectangle operations ---
#define gfx_clear_rect(rect,attr,ch,flags)  jsp_clear_rect((rect),(attr),(ch),(flags))

//--- Text printing ---
#define gfx_print_set_pos(ctx,r,c)          jsp_print_set_pos((ctx),(r),(c))
#define gfx_print_string(ctx,str)           jsp_print_string((ctx),(str))

// Forward declaration for the clipping wrapper (defined in gfx_jsp.c)
void gfx_jsp_move_sprite_clipped( gfx_sprite_t *s, gfx_rect_t *clip,
                                   uint8_t *frame, uint8_t x, uint8_t y );

#endif // _GFX_JSP_H

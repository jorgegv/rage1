////////////////////////////////////////////////////////////////////////////////
//
// RAGE1 - Retro Adventure Game Engine, release 1
// (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
//
// This code is published under a GNU GPL license version 3 or later.  See
// LICENSE file in the distribution for details.
//
////////////////////////////////////////////////////////////////////////////////

#ifndef _GFX_SP1_H
#define _GFX_SP1_H

#include <games/sp1.h>

//--- Types ---
typedef struct sp1_ss    gfx_sprite_t;
typedef struct sp1_Rect  gfx_rect_t;
typedef struct sp1_pss   gfx_print_ctx_t;

//--- Constants ---
#define GFX_CLEAR_TILE         SP1_RFLAG_TILE
#define GFX_CLEAR_COLOUR       SP1_RFLAG_COLOUR
#define GFX_PSS_INVALIDATE     SP1_PSSFLAG_INVALIDATE
#define GFX_PRINT_CTX_INIT(area, attr) \
    { &(area), GFX_PSS_INVALIDATE, 0, 0, 0, (attr), 0, 0 }

//--- Initialization ---
// gfx_init() is a real function (multi-step), defined in sp1engine.c
#define gfx_invalidate(rect)                   sp1_Invalidate(rect)
#define gfx_update()                           sp1_UpdateNow()

//--- Sprite lifecycle ---
// gfx_sprite_create() is a real function (multi-step), defined in sprite.c
#define gfx_sprite_destroy(s)                  sp1_DeleteSpr(s)
// gfx_sprite_set_color() is a real function (multi-step), defined in sprite.c
#define gfx_sprite_set_threshold(s,xt,yt) \
    do { (s)->xthresh = (xt); (s)->ythresh = (yt); } while(0)

//--- Sprite movement ---
#define gfx_sprite_move_pixel(s,clip,fr,x,y)   sp1_MoveSprPix((s),(clip),(fr),(x),(y))
#define gfx_sprite_move_cell(s,clip,fr,r,c)    sp1_MoveSprAbs((s),(clip),(fr),(r),(c),0,0)

//--- Sprite query ---
#define gfx_sprite_get_row(s)                  ((s)->row)
#define gfx_sprite_get_col(s)                  ((s)->col)
#define gfx_sprite_get_width(s)                ((s)->width)
#define gfx_sprite_get_height(s)               ((s)->height)

//--- Tile drawing ---
#define gfx_tile_put(r,c,attr,tile)            sp1_PrintAtInv((r),(c),(attr),(tile))
#define gfx_tile_register(idx,gfx)             sp1_TileEntry((idx),(gfx))

//--- Rectangle operations ---
#define gfx_clear_rect(rect,attr,ch,flags)     sp1_ClearRectInv((rect),(attr),(ch),(flags))

//--- Text printing ---
#define gfx_print_set_pos(ctx,r,c)             sp1_SetPrintPos((ctx),(r),(c))
#define gfx_print_string(ctx,str)              sp1_PrintString((ctx),(str))

#endif // _GFX_SP1_H

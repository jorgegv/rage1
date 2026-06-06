#!/usr/bin/perl
# Deterministic unit test for RAGE::CPCGfx (CPC mode-1 pixel packing).
# Expected bytes are hand-derived from the documented format (plane bit of
# cell-pixel cp at (7-cp)-q*ppc; MSB-first; mask sets all planes); these are the
# byte sequences JSP's CPC runtime consumes.  Run: perl tests/datagen/cpcgfx_pack.t
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use Test::More tests => 6;

use_ok( 'RAGE::CPCGfx' );

# An 8x8 cell, every pixel foreground (pen 1).
my @fg_rows   = ( ('#' x 8) ) x 8;
# An 8x8 cell, every pixel background (pen 0).
my @bg_rows   = ( ('.' x 8) ) x 8;
# An 8x8 mask, fully opaque (nothing transparent).
my @opaque    = ( ('.' x 8) ) x 8;
# An 8x8 mask, fully transparent.
my @transparent = ( ('#' x 8) ) x 8;

# --- 1. TILE, mode 1, all-foreground 8x8 -> 16 bytes, all 0xF0 ---------------
# Mode 1: ppc=4, 2 byte-columns x 8 lines, column-major. A pen-1 slice sets
# plane-0 bits 7..4 -> 0xF0 for each of the 4 cell-pixels.
{
    my ( $pen, $transp ) = RAGE::CPCGfx::grids_from_ascii( \@fg_rows, undef );
    my $bytes = RAGE::CPCGfx::tile_bytes( $pen, $transp, 1, 1, 1 );
    is_deeply( $bytes, [ (0xF0) x 16 ], 'tile mode1 all-fg = 16 x 0xF0' );
}

# --- 2. TILE bit position: single leftmost fg pixel on row 0 -----------------
# Only (x=0,y=0) is fg. Sub-column 0, line 0: cp0 -> bit (7-0)=0x80; rest 0.
# All other bytes 0. Column-major: byte index 0 = sub0/line0.
{
    my @rows = ( '#.......', ('.' x 8) x 7 );
    # fix: build 8 rows explicitly
    @rows = ( '#.......', '........', '........', '........',
              '........', '........', '........', '........' );
    my ( $pen, $transp ) = RAGE::CPCGfx::grids_from_ascii( \@rows, undef );
    my $bytes = RAGE::CPCGfx::tile_bytes( $pen, $transp, 1, 1, 1 );
    my @want = (0) x 16;
    $want[0] = 0x80;   # sub0, line0
    is_deeply( $bytes, \@want, 'tile mode1 single MSB pixel = 0x80 at byte 0' );
}

# --- 3. SPRITE mask2, all-fg pixels, opaque mask -> (00,F0) x 16 -------------
# Column-major: 2 Mode-1 cols x 8 lines, mask interleaved (mask,graph).
{
    my ( $pen, $transp ) = RAGE::CPCGfx::grids_from_ascii( \@fg_rows, \@opaque );
    my $bytes = RAGE::CPCGfx::sprite_frame_bytes( $pen, $transp, 1, 1, 1, mask => 1 );
    my @want;
    push @want, 0x00, 0xF0 for ( 1 .. 16 );   # 2 cols x 8 lines
    is_deeply( $bytes, \@want, 'sprite mask2 all-fg opaque = (00,F0) x16' );
}

# --- 4. SPRITE mask2, fully transparent -> (FF,00) x 16 ---------------------
{
    my ( $pen, $transp ) = RAGE::CPCGfx::grids_from_ascii( \@bg_rows, \@transparent );
    my $bytes = RAGE::CPCGfx::sprite_frame_bytes( $pen, $transp, 1, 1, 1, mask => 1 );
    my @want;
    push @want, 0xFF, 0x00 for ( 1 .. 16 );
    is_deeply( $bytes, \@want, 'sprite mask2 fully transparent = (FF,00) x16' );
}

# --- 5. SPRITE mask2 extra_top adds 8 transparent pre-rows (FF,00) ----------
{
    my ( $pen, $transp ) = RAGE::CPCGfx::grids_from_ascii( \@fg_rows, \@opaque );
    my $bytes = RAGE::CPCGfx::sprite_frame_bytes( $pen, $transp, 1, 1, 1, mask => 1, extra_top => 1 );
    my @want;
    push @want, 0xFF, 0x00 for ( 1 .. 8 );    # 8 pre-rows
    push @want, 0x00, 0xF0 for ( 1 .. 16 );   # body
    is_deeply( $bytes, \@want, 'sprite mask2 extra_top prepends 8x(FF,00)' );
}

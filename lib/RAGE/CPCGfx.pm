package RAGE::CPCGfx;

################################################################################
##
## RAGE1 - Retro Adventure Game Engine, release 1
## (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
##
## This code is published under a GNU GPL license version 3 or later.  See
## LICENSE file in the distribution for details.
##
################################################################################
##
## RAGE::CPCGfx — Amstrad CPC pixel packing for datagen's CPC asset backend.
##
## The CPC mode-1/mode-0 byte format here is COPIED / ADAPTED from JSP's
## external/jsp/tools/cpcgfx.pl (its cell_bytes / emit_cell + frame/tile
## assembly).  Per Task 5 (README §5.1, reversed): cpcgfx.pl belongs to JSP and
## stays in the submodule untouched; datagen owns this copy and MAY diverge as
## long as the emitted BYTE SEQUENCES stay compatible with JSP's CPC runtime.
## A byte-compat regression test guards that contract (t/cpcgfx_compat).
##
## Mode geometry (mode-parametric, so Mode 0 drops in later):
##   ppc     = pixels per byte           (Mode 1 = 4, Mode 0 = 2)
##   subcols = Mode-N cells per 8px col  (8/ppc)
##   nplanes = colour planes per byte    (8/ppc)
## A cell-pixel cp's plane q bit sits at (7-cp) - q*ppc.  For 2-colour art
## (pen 0/1) only plane 0 is set; a transparent (mask) pixel sets ALL planes so
## the runtime AND keeps the background.
##
################################################################################

use strict;
use warnings;
use utf8;

# ($ppc, $subcols, $nplanes) for a CPC mode (1 or 0).
sub _geom {
    my $mode = shift;
    die "RAGE::CPCGfx: unsupported mode '$mode' (only 1 and 0)\n"
        unless $mode == 1 or $mode == 0;
    my $ppc = ( $mode == 1 ) ? 4 : 2;
    return ( $ppc, 8 / $ppc, 8 / $ppc );
}

# Graphic + mask byte for the $ppc-pixel slice at (col,row,sub,line), built from
# a per-pixel pen grid + transparency grid.  Mirrors cpcgfx.pl::cell_bytes.
#   $pen->[y][x]    = pen index (0..)
#   $transp->[y][x] = 1 if transparent (mask), else 0/undef
sub cell_bytes {
    my ( $pen, $transp, $col, $row, $sub, $line, $ppc, $nplanes ) = @_;
    my $y  = $row * 8 + $line;
    my $xb = $col * 8 + $sub * $ppc;
    my ( $g, $m ) = ( 0, 0 );
    foreach my $cp ( 0 .. $ppc - 1 ) {
        my $x = $xb + $cp;
        if ( $transp->[$y][$x] ) {
            foreach my $q ( 0 .. $nplanes - 1 ) {
                $m |= 1 << ( ( 7 - $cp ) - $q * $ppc );
            }
        } else {
            my $p = $pen->[$y][$x] || 0;
            foreach my $q ( 0 .. $nplanes - 1 ) {
                $g |= 1 << ( ( 7 - $cp ) - $q * $ppc ) if ( $p >> $q ) & 1;
            }
        }
    }
    return ( $g, $m );
}

# Build (\@pen, \@transp) grids from datagen-style ASCII rows.
#   $pixels = arrayref of row strings; a '#'/'1' pixel -> pen 1, else pen 0.
#   $mask   = arrayref of row strings (optional); a '#'/'1' pixel -> transparent.
# Both grids are [y][x].  Width/height taken from the pixel rows.
sub grids_from_ascii {
    my ( $pixels, $mask ) = @_;
    my ( @pen, @transp );
    foreach my $y ( 0 .. $#$pixels ) {
        my @pc = split //, $pixels->[$y];
        my @mc = $mask ? ( split //, $mask->[$y] ) : ();
        foreach my $x ( 0 .. $#pc ) {
            $pen[$y][$x]    = ( $pc[$x] eq '#' or $pc[$x] eq '1' ) ? 1 : 0;
            $transp[$y][$x] = ( @mc and ( $mc[$x] eq '#' or $mc[$x] eq '1' ) ) ? 1 : 0;
        }
    }
    return ( \@pen, \@transp );
}

# Pack one background/foreground TILE: column-major pixel-cell, graph-only, no
# sub-cell padding.  Returns a flat arrayref of bytes ($subcols*8 per cell,
# row-major over cells).  Mirrors cpcgfx.pl is_tile path.
sub tile_bytes {
    my ( $pen, $transp, $wcells, $hcells, $mode ) = @_;
    my ( $ppc, $subcols, $nplanes ) = _geom( $mode );
    my @bytes;
    foreach my $row ( 0 .. $hcells - 1 ) {
        foreach my $col ( 0 .. $wcells - 1 ) {
            foreach my $sub ( 0 .. $subcols - 1 ) {   # byte-columns L->R
                foreach my $line ( 0 .. 7 ) {
                    my ( $g, undef ) = cell_bytes( $pen, $transp, $col, $row, $sub, $line, $ppc, $nplanes );
                    push @bytes, $g;
                }
            }
        }
    }
    return \@bytes;
}

# Pack one SPRITE frame: column-major, optionally masked (MASK2: interleaved
# mask,graph per line) or opaque (LOAD1: graph only).  Optional 8 transparent
# pre-rows (extra_top) before the data and an 8-line blank gap after each column
# (extra_bottom) — the JSP sub-cell-Y layout.  Returns a flat arrayref of bytes.
# Mirrors cpcgfx.pl sprite path.
#   %opt: mask => 1|0, extra_top => 1|0, extra_bottom => 1|0
sub sprite_frame_bytes {
    my ( $pen, $transp, $wcells, $hcells, $mode, %opt ) = @_;
    my ( $ppc, $subcols, $nplanes ) = _geom( $mode );
    my $is_mask = $opt{mask} ? 1 : 0;
    my $bottom  = $opt{extra_bottom} ? 1 : 0;
    my $ncols   = $subcols * $wcells;
    my @bytes;

    my $push_line = sub {
        my ( $g, $m ) = @_;
        if ( $is_mask ) { push @bytes, $m, $g; } else { push @bytes, $g; }
    };
    my $push_blank = sub {
        my $n = shift;
        foreach ( 1 .. $n ) {
            if ( $is_mask ) { push @bytes, 0xff, 0x00; } else { push @bytes, 0x00; }
        }
    };

    $push_blank->( 8 ) if $opt{extra_top};

    foreach my $mc ( 0 .. $ncols - 1 ) {
        my $col = int( $mc / $subcols );
        my $sub = $mc % $subcols;
        foreach my $row ( 0 .. $hcells - 1 ) {
            foreach my $line ( 0 .. 7 ) {
                my ( $g, $m ) = cell_bytes( $pen, $transp, $col, $row, $sub, $line, $ppc, $nplanes );
                $push_line->( $g, $m );
            }
        }
        $push_blank->( 8 * $bottom );
    }
    return \@bytes;
}

1;

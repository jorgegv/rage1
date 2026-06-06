package RAGE::AssetBackend::CPCMode1;

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
## RAGE::AssetBackend::CPCMode1 — Amstrad CPC mode-1 asset-generation backend
## (Task 5).  Produces JSP-CPC mode-1 (2bpp, 16 bytes/cell) sprite frame bytes
## from a sprite's ASCII PIXELS/MASK, using the RAGE::CPCGfx packing core
## (copied/adapted from JSP's cpcgfx.pl).  Byte format kept JSP-compatible.
##
## NOTE: ZX-side correctness is verified now (byte-identical gate); the CPC
## frame layout / stride is verified end-to-end at R9 (build minimal_cpc on
## GFX_BACKEND=jsp + run in Caprice32).
##
################################################################################

use strict;
use warnings;
use utf8;

use RAGE::CPCGfx;

sub new {
    my ( $class, %opt ) = @_;
    return bless { mode => 1, %opt }, $class;
}

# Mode-1 pixel cell = 16 bytes (2 byte-columns x 8 lines).
sub bytes_per_cell { return 16; }

# Collapse datagen's 2-char-per-pixel ASCII row ('..'=off, else=on) to a
# 1-char-per-pixel row ('.'/'#') that RAGE::CPCGfx::grids_from_ascii expects.
sub _collapse {
    my $row = shift;
    $row =~ s/(..)/ $1 eq '..' ? '.' : '#' /ge;
    return $row;
}

# Build the flat sprite data-byte array + per-frame start offsets.  Each frame
# is packed independently (column-major, mask2 interleaved, 8 transparent
# pre-rows + 8-line inter-column gap = the RAGE1/JSP sub-cell-Y layout); the
# frame pointer points PAST the pre-rows (at the body), like cpcgfx.pl's label.
sub sprite_frame_data {
    my ( $self, $sprite ) = @_;
    my $rows   = $sprite->{'rows'};
    my $cols   = $sprite->{'cols'};
    my $frames = $sprite->{'frames'};
    my $mode   = $self->{'mode'};

    my @data;
    my @frame_offsets;
    my $pre_bytes = 8 * 2;   # 8 transparent pre-rows, 2 bytes/line (mask2)

    foreach my $frm ( 0 .. ( $frames - 1 ) ) {
        # this frame's PIXELS/MASK rows (rows*8 lines), collapsed to 1 char/px
        my @pix = map { _collapse( $_ ) }
            @{ $sprite->{'pixels'} }[ ( $frm * $rows * 8 ) .. ( ( $frm + 1 ) * $rows * 8 - 1 ) ];
        my @msk = map { _collapse( $_ ) }
            @{ $sprite->{'mask'} }[ ( $frm * $rows * 8 ) .. ( ( $frm + 1 ) * $rows * 8 - 1 ) ];
        my ( $pen, $transp ) = RAGE::CPCGfx::grids_from_ascii( \@pix, \@msk );
        my $bytes = RAGE::CPCGfx::sprite_frame_bytes(
            $pen, $transp, $cols, $rows, $mode,
            mask => 1, extra_top => 1, extra_bottom => 1 );
        push @frame_offsets, scalar( @data ) + $pre_bytes;   # point past pre-rows
        push @data, @$bytes;
    }
    return ( \@data, \@frame_offsets );
}

1;

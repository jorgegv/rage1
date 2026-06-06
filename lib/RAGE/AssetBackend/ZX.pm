package RAGE::AssetBackend::ZX;

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
## RAGE::AssetBackend::ZX — ZX Spectrum asset-generation backend (SP1/JSP).
##
## The first asset backend (Task 5).  It owns the ZX-specific translation from a
## sprite's compiled per-cell 1bpp bytes into the SP1/JSP column-major frame
## byte layout.  Behaviour is MOVED VERBATIM from datagen's generate_sprite so
## the emitted bytes are byte-identical to the pre-refactor output.
##
## SP1/JSP masked-sprite frame format (per cell column):
##   * a leading blank row : 8 x (mask=0xff, pixel=0x00)
##   * the sprite rows     : 8 x (mask, pixel) per cell
##   * a shared trailing blank row at the very end
## Bytes are emitted mask-then-pixel interleaved (List::MoreUtils zip order).
## Each frame is (rows+1)*cols*16 bytes; frame 0 starts at offset 16 (past the
## leading blank row of column 0).
##
################################################################################

use strict;
use warnings;
use utf8;

sub new {
    my ( $class, %opt ) = @_;
    return bless { %opt }, $class;
}

# Cells per ZX cell row: 8 bytes of 1bpp pixel data.
sub bytes_per_cell { return 8; }

# ZX 1bpp codec: 16-char pixel string (8 px, 2 chars each: '..'=0 else 1) -> byte.
# (Same as datagen's pixels_to_byte; kept here so the backend owns ZX encoding.)
sub _pixels_to_byte {
    my $pixels = shift;
    return -1 if ( length( $pixels ) != 16 );
    return oct( '0b' . join( '', map { ( $_ eq '..' ? '0' : '1' ) } unpack( "(A2)*", $pixels ) ) );
}

# Compile a BTile's ASCII PIXELS into per-cell 1bpp byte arrays (8 bytes/cell),
# row-major per frame.  Reproduces datagen's validate_and_compile_btile loop
# verbatim (byte-identical).  Returns an arrayref of per-cell [8 bytes] arrays.
sub btile_cell_bytes {
    my ( $self, $tile ) = @_;
    my $cols = $tile->{'cols'};
    my @pixel_bytes;
    my $cur_row = 0;
    my $byte_count = 0;
    foreach my $p ( @{ $tile->{'pixels'} } ) {
        my @parts = unpack( "(A16)*", $p );
        my $cur_col = 0;
        foreach my $b ( @parts ) {
            push @{ $pixel_bytes[ $cur_row * $cols + $cur_col++ ] }, _pixels_to_byte( $b );
            if ( not ( ++$byte_count % ( 8 * $cols ) ) ) { $cur_row++; }
        }
    }
    return \@pixel_bytes;
}

# Build the flat sprite data-byte array + per-frame start offsets for the
# sprite_<name>_data[] / sprite_<name>_frames[] emission.  Reads the already
# compiled $sprite->{pixel_bytes} / {mask_bytes} (8 bytes/cell, row-major per
# frame).  Returns ( \@data_bytes, \@frame_offsets ).
sub sprite_frame_data {
    my ( $self, $sprite ) = @_;
    my $rows   = $sprite->{'rows'};
    my $cols   = $sprite->{'cols'};
    my $frames = $sprite->{'frames'};

    my @col_bytes;
    my @mask_bytes;
    foreach my $frm ( 0 .. ( $frames - 1 ) ) {
        foreach my $col ( 0 .. ( $cols - 1 ) ) {
            push @col_bytes,  ( 0 ) x 8;        # leading blank row
            push @mask_bytes, ( 0xff ) x 8;
            foreach my $row ( 0 .. ( $rows - 1 ) ) {
                push @col_bytes,  @{ $sprite->{'pixel_bytes'}[ ( $frm * $rows * $cols ) + $row * $cols + $col ] };
                push @mask_bytes, @{ $sprite->{'mask_bytes'} [ ( $frm * $rows * $cols ) + $row * $cols + $col ] };
            }
        }
    }
    push @col_bytes,  ( 0 ) x 8;                # shared trailing blank row
    push @mask_bytes, ( 0xff ) x 8;

    # interleave mask,pixel (same order as List::MoreUtils zip(@mask,@col))
    my @data;
    foreach my $k ( 0 .. $#mask_bytes ) {
        push @data, $mask_bytes[$k], $col_bytes[$k];
    }

    my @frame_offsets;
    my $frame_stride = 16 * ( $rows + 1 ) * $cols;
    my $ptr = 16;
    foreach ( 0 .. ( $frames - 1 ) ) {
        push @frame_offsets, $ptr;
        $ptr += $frame_stride;
    }

    return ( \@data, \@frame_offsets );
}

1;

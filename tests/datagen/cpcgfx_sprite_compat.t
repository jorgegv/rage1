#!/usr/bin/perl
#
# Byte-compat regression test for RAGE::CPCGfx (Task 5 deliverable).
#
# Proves that datagen's in-house CPC Mode-1 packing (lib/RAGE/CPCGfx.pm, copied
# /adapted from JSP's external/jsp/tools/cpcgfx.pl) emits byte sequences that are
# IDENTICAL to cpcgfx.pl's output for the same reference art.  This turns the
# "datagen's CPC bytes stay JSP-compatible" contract (README §5.1/§5.13b) into a
# verified invariant WITHOUT coupling the code: the two implementations may
# diverge as long as the emitted bytes match.
#
# Method: build one reference 16x16 art with foreground / background / mask
# (transparent) pixels.  Feed it to BOTH packers from the SAME source of truth:
#   - cpcgfx.pl  <- a PNG (foreground=white, background=black, mask=red), the
#                   colours cpcgfx.pl defaults to;
#   - RAGE::CPCGfx <- the matching ASCII pixel/mask grids.
# Then assert the full emitted byte streams are byte-identical, for the sprite
# (mask2, --extra-top-rows --extra-bottom-row) and tile paths.
#
# Skips cleanly if GD or cpcgfx.pl is unavailable.  Run: perl tests/datagen/cpcgfx_sprite_compat.t

use strict;
use warnings;
use FindBin;
use File::Temp qw( tempfile );
use lib "$FindBin::Bin/../../lib";
use Test::More;

my $ROOT    = "$FindBin::Bin/../..";
my $CPCGFX  = "$ROOT/external/jsp/tools/cpcgfx.pl";

# --- preconditions: GD module + cpcgfx.pl (with its ZXGfx lib) present --------
eval { require GD; 1 } or plan skip_all => "GD not installed (needed to render the reference PNG)";
-f $CPCGFX or plan skip_all => "cpcgfx.pl reference not found at $CPCGFX (JSP submodule)";
-f "$ROOT/external/jsp/tools/lib/ZXGfx.pm"
    or plan skip_all => "ZXGfx.pm (cpcgfx.pl dependency) not found in JSP submodule";

use_ok( 'RAGE::CPCGfx' );

# ---------------------------------------------------------------------------
# Reference art: 16x16 (2x2 Mode-1-source cells).  Deterministic, but mixes all
# three states across both cell columns and both 4-px sub-columns so every nibble
# and the mask/graph interleave are exercised:
#   - 2-px outer border  -> TRANSPARENT (mask)
#   - interior           -> FOREGROUND where (x+y) % 3 == 0, else BACKGROUND
# state(): 'T' transparent | 'F' foreground (pen 1) | 'B' background (pen 0)
# ---------------------------------------------------------------------------
my ( $W, $H ) = ( 16, 16 );
sub state {
    my ( $y, $x ) = @_;
    return 'T' if $x < 2 || $x >= $W - 2 || $y < 2 || $y >= $H - 2;
    return ( ( $x + $y ) % 3 == 0 ) ? 'F' : 'B';
}

# ASCII grids for RAGE::CPCGfx::grids_from_ascii ('#' = set):
#   pixels: '#' where foreground;  mask: '#' where transparent.
my ( @pixels, @mask );
for my $y ( 0 .. $H - 1 ) {
    my ( $p, $m ) = ( '', '' );
    for my $x ( 0 .. $W - 1 ) {
        my $s = state( $y, $x );
        $p .= ( $s eq 'F' ) ? '#' : '.';
        $m .= ( $s eq 'T' ) ? '#' : '.';
    }
    push @pixels, $p;
    push @mask,   $m;
}

# Matching PNG for cpcgfx.pl: foreground=white, background=black, mask=red
# (exactly cpcgfx.pl's -f/-b/-m defaults), truecolor so RGB is exact.
my $img = GD::Image->new( $W, $H, 1 );          # 1 = truecolor
my $white = $img->colorAllocate( 255, 255, 255 );   # FFFFFF foreground
my $black = $img->colorAllocate(   0,   0,   0 );   # 000000 background
my $red   = $img->colorAllocate( 255,   0,   0 );   # FF0000 mask
for my $y ( 0 .. $H - 1 ) {
    for my $x ( 0 .. $W - 1 ) {
        my $s = state( $y, $x );
        $img->setPixel( $x, $y, $s eq 'F' ? $white : $s eq 'T' ? $red : $black );
    }
}
my ( $fh, $png ) = tempfile( 'cpcgfx_compat_XXXX', SUFFIX => '.png', UNLINK => 1, TMPDIR => 1 );
binmode $fh;
print $fh $img->png;
close $fh;

# Run cpcgfx.pl with the given gfx-type/flags and return the emitted byte stream
# (every `db $xx[,$yy]` value, in order).
sub cpcgfx_bytes {
    my @flags = @_;
    my @cmd = ( $^X, $CPCGFX,
        '-i', $png, '-x', 0, '-y', 0,
        '--width', $W, '--height', $H,
        '-s', 'compat_sym', '--mode', 1, @flags );
    open( my $out, '-|', @cmd ) or die "cannot run cpcgfx.pl: $!";
    my @bytes;
    while ( my $line = <$out> ) {
        # `db $mm,$gg` (sprite_mask)  or  `db $gg` (tile / sprite_load)
        if ( $line =~ /^\s*db\s+\$([0-9a-fA-F]{2})\s*,\s*\$([0-9a-fA-F]{2})/ ) {
            push @bytes, hex($1), hex($2);
        } elsif ( $line =~ /^\s*db\s+\$([0-9a-fA-F]{2})\s*(?:;|$)/ ) {
            push @bytes, hex($1);
        }
    }
    close $out;
    return \@bytes;
}

my ( $pen, $transp ) = RAGE::CPCGfx::grids_from_ascii( \@pixels, \@mask );
my $wcells = $W / 8;
my $hcells = $H / 8;

# --- SPRITE mask2, the R9 frame format: extra_top + extra_bottom -------------
{
    my $ours = RAGE::CPCGfx::sprite_frame_bytes(
        $pen, $transp, $wcells, $hcells, 1,
        mask => 1, extra_top => 1, extra_bottom => 1 );
    my $ref = cpcgfx_bytes( '-g', 'sprite_mask', '--extra-top-rows', '--extra-bottom-row' );
    is( scalar(@$ours), 208, 'sprite mask2 2x2 frame = 208 bytes (16 pre + 4 cols x 48)' );
    is_deeply( $ours, $ref,
        'RAGE::CPCGfx sprite_frame_bytes == cpcgfx.pl -g sprite_mask --extra-top-rows --extra-bottom-row' );
}

# --- SPRITE load1 (graph-only frame: no mask, blank lines = 0x00) -----------
{
    my $ours = RAGE::CPCGfx::sprite_frame_bytes(
        $pen, $transp, $wcells, $hcells, 1,
        mask => 0, extra_top => 1, extra_bottom => 1 );
    my $ref = cpcgfx_bytes( '-g', 'sprite_load', '--extra-top-rows', '--extra-bottom-row' );
    is( scalar(@$ours), 104, 'sprite load1 2x2 frame = 104 bytes (8 pre + 4 cols x 24)' );
    is_deeply( $ours, $ref,
        'RAGE::CPCGfx sprite_frame_bytes (load1) == cpcgfx.pl -g sprite_load --extra-top-rows --extra-bottom-row' );
}

# --- TILE (graph-only, no mask, no extra rows) ------------------------------
{
    my $ours = RAGE::CPCGfx::tile_bytes( $pen, $transp, $wcells, $hcells, 1 );
    my $ref  = cpcgfx_bytes( '-g', 'tile' );
    is( scalar(@$ours), 64, 'tile 2x2 = 64 bytes (4 cells x 16)' );
    is_deeply( $ours, $ref, 'RAGE::CPCGfx tile_bytes == cpcgfx.pl -g tile' );
}

done_testing();

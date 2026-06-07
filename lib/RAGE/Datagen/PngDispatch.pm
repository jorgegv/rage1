package RAGE::Datagen::PngDispatch;

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
## RAGE::Datagen::PngDispatch — per-platform PNG asset dispatcher for datagen
## (Task 6, Stage 2 extraction).  Moved verbatim from tools/datagen.pl; the only
## edits are the mechanical scaffold bindings needed to run from this package:
##   * the shared PNG-pipeline subs (provided by RAGE::PNGFileUtils, which
##     declares no package of its own and so installs into main::) are called
##     fully-qualified as `main::<sub>`;
##   * the `$game_config` global is read from the RAGE::Datagen::Context object
##     ($ctx) threaded in as the first positional arg, as $ctx->{game_config}.
## These bind to the same subs/state as the in-line version, so emitted bytes
## are byte-identical.
##
################################################################################

use strict;
use warnings;
use utf8;

use Exporter 'import';
our @EXPORT_OK = qw( dispatch_png_asset_handling );

# A3-1: per-platform dispatch seam for PNG-driven BTile / sprite asset
# handling.  Both ZX and CPC route the parse-time PNG work through the shared
# RAGE::PNGFileUtils 1bpp pipeline; the platform-specific per-cell repacking
# (ZX 8-byte cells vs CPC mode-1 16-byte cells) is done later by the
# RAGE::AssetBackend at generation time.
#
# R10: the interim full-colour CPC path (cpct_img2tileset via the cpctelera
# submodule) was retired; only MONO CPC assets are supported here.
#
# Usage:
#   my $png  = dispatch_png_asset_handling($ctx, $platform, 'load_png_file', $path);
#   my $data = dispatch_png_asset_handling($ctx, $platform, 'png_to_pixels_and_attrs',
#                                          $png, $x, $y, $w, $h);
#
# Dispatch keys:
#   /^zx/   — route to existing RAGE::PNGFileUtils:: subs.
#   /^cpc/  — MONO: same route as ZX (shared 1bpp UDG bytes, §5.9).
#             FULL-COLOR: unsupported (die) since R10.
#   default — die: "Unknown platform '<name>'".
sub dispatch_png_asset_handling {
    my ( $ctx, $platform, $fn, @args ) = @_;

    defined( $platform ) or
        die "dispatch_png_asset_handling: platform is undefined\n";
    defined( $fn ) or
        die "dispatch_png_asset_handling: function name is undefined\n";

    if ( $platform =~ /^zx/ ) {
        # ZX branch: thin pass-through to the PNG-utility subs
        # provided by RAGE::PNGFileUtils.  Note the module declares
        # no `package` of its own, so its subs are installed into
        # main::; we therefore resolve by symbolic name in main::.
        # All current call sites use one of:
        #   load_png_file, png_rotate, png_hmirror, png_vmirror,
        #   map_png_colors_to_zx_colors, png_to_pixels_and_attrs,
        #   pick_pixel_data_by_color_from_png
        my $code = main->can( $fn ) or
            die "dispatch_png_asset_handling: no PNG-asset sub '$fn' " .
                "(expected from RAGE::PNGFileUtils)\n";
        return $code->( @args );
    }

    if ( $platform =~ /^cpc/ ) {
        # CPC PNG asset dispatch.  CPC pixel/asset conversion is owned by the
        # in-datagen RAGE::AssetBackend (CPC mode-1) at generation time; the
        # parse-time PNG path here routes CPC mono BTiles through the ZX 1bpp
        # pipeline so their shared UDG bytes are byte-identical to ZX (§5.9),
        # then the asset backend repacks them to mode-1 cells.
        #
        # R10: the interim full-colour CPC path (cpct_img2tileset via the
        # cpctelera submodule) was retired.  No live game uses full-colour CPC
        # PNG assets; full-colour support, if revived, will go through the
        # RAGE::AssetBackend, not an external converter.
        my $color_mode = lc( $ctx->{game_config}->{'color'}{'mode'} // 'full' );
        if ( $color_mode eq 'mono' ) {
            return _cpc_mono_dispatch( $ctx, $fn, @args );
        }
        die "dispatch_png_asset_handling: full-colour CPC PNG assets are not " .
            "supported (the cpctelera converter was retired in R10); use MONO " .
            "mode or the in-datagen CPC asset backend\n";
    }

    die "Unknown platform '$platform' in dispatch_png_asset_handling\n";
}

# CPC MONO PNG asset dispatch — asset-kind-specific (§5.9).
#
# BTiles (PNG_DATA → png_to_pixels_and_attrs):
#   Keep shared 1bpp UDG bytes, byte-identical to the ZX build.  All BTile
#   functions route straight to the ZX RAGE::PNGFileUtils subs; the per-cell
#   mode-1 repack happens later in the RAGE::AssetBackend, not here.
#
# Sprites (PNG_DATA / PNG_MASK → pick_pixel_data_by_color_from_png):
#   R10: previously pre-baked to 2bpp via cpct_img2tileset (cpctelera) — that
#   path is retired.  PNG sprite assets are unsupported on CPC (die); all CPC
#   games use inline PIXELS/MASK sprite data.
#
# The shared entry points (load_png_file, map_png_colors_to_zx_colors) cannot
# know up-front which asset kind they belong to (the function name is the same
# for BTile and sprite).  We resolve this by returning a lightweight CPC PNG
# object from load_png_file that carries the source path; the terminal function
# then decides:
#   - png_to_pixels_and_attrs  → BTile  → run the ZX pipeline lazily on the path
#                                          (load → transforms → colour-map →
#                                          extract), returning ZX 1bpp data.
#   - pick_pixel_data_by_color_from_png → Sprite → die (PNG sprites unsupported).
sub _cpc_mono_dispatch {
    my ( $ctx, $fn, @args ) = @_;

    if ( $fn eq 'load_png_file' ) {
        my $path = $args[0];
        # Defer: carry path + accumulate transforms; ZX load happens lazily
        # in png_to_pixels_and_attrs (BTile) and is irrelevant for sprites.
        return { __cpc_mono => 1, path => $path, transforms => [] };
    }

    if ( $fn eq 'png_rotate' ) {
        my ( $obj, $deg ) = @args;
        push @{ $obj->{'transforms'} }, { op => 'rotate', deg => $deg };
        return $obj;
    }
    if ( $fn eq 'png_hmirror' ) {
        my $obj = $args[0];
        push @{ $obj->{'transforms'} }, { op => 'hmirror' };
        return $obj;
    }
    if ( $fn eq 'png_vmirror' ) {
        my $obj = $args[0];
        push @{ $obj->{'transforms'} }, { op => 'vmirror' };
        return $obj;
    }
    if ( $fn eq 'map_png_colors_to_zx_colors' ) {
        # Deferred to png_to_pixels_and_attrs for BTiles; no-op for sprites.
        return 1;
    }

    # BTile terminal: run the ZX pipeline so the 1bpp bytes are identical to ZX.
    if ( $fn eq 'png_to_pixels_and_attrs' ) {
        my ( $obj, $xpos, $ypos, $width, $height ) = @args;
        my $png = main::load_png_file( $obj->{'path'} )
            or die "_cpc_mono_dispatch: could not load PNG $obj->{'path'}\n";
        # replay the recorded transforms in order (same order as the ZX
        # BTile call site applies them)
        for my $t ( @{ $obj->{'transforms'} } ) {
            if    ( $t->{'op'} eq 'rotate'  ) { $png = main::png_rotate( $png, $t->{'deg'} ); }
            elsif ( $t->{'op'} eq 'hmirror' ) { $png = main::png_hmirror( $png ); }
            elsif ( $t->{'op'} eq 'vmirror' ) { $png = main::png_vmirror( $png ); }
        }
        main::map_png_colors_to_zx_colors( $png );
        return main::png_to_pixels_and_attrs( $png, $xpos, $ypos, $width, $height );
    }

    # Sprite terminal.  R10: mono CPC PNG sprites were previously pre-baked to
    # 2bpp via cpct_img2tileset (cpctelera) — that path is retired.  No live
    # game uses PNG sprite assets on CPC (all CPC games use inline PIXELS/MASK,
    # repacked to mode-1 by the in-datagen RAGE::AssetBackend).
    if ( $fn eq 'pick_pixel_data_by_color_from_png' ) {
        die "_cpc_mono_dispatch: CPC PNG sprite assets are not supported " .
            "(the cpctelera converter was retired in R10); use inline " .
            "PIXELS/MASK sprite data\n";
    }

    die "_cpc_mono_dispatch: unhandled function '$fn'\n";
}

1;

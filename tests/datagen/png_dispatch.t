#!/usr/bin/perl
# Unit test for RAGE::Datagen::PngDispatch (Task 6 Stage 2 extraction) and the
# RAGE::Datagen::Context glob-alias scaffold.
#
# Coverage rationale: the ZX build byte-identity gate exercises only the /^zx/
# branch of dispatch_png_asset_handling (default/crumbs/blobs use PNG assets),
# and NO test game uses PNG assets on CPC, so the /^cpc/ MONO path
# (_cpc_mono_dispatch) and the scaffolded $main::game_config read are otherwise
# untested.  This test covers: platform/fn routing, the CPC mono deferred-object
# transform pipeline, all die paths, and that the Context scaffold makes
# $main::game_config readable from the module AND tracks full reassignment of
# the datagen.pl lexical.
#
# Run: perl tests/datagen/png_dispatch.t
use strict;
use warnings;
# the main:: PNG stubs and the $main::game_config scaffold alias below are read
# only indirectly (via main->can / the module), so silence "used only once".
no warnings 'once';
use FindBin;
use lib "$FindBin::Bin/../../lib";
use Test::More;

use_ok( 'RAGE::Datagen::Context' );
use_ok( 'RAGE::Datagen::PngDispatch' );

# Stub the RAGE::PNGFileUtils subs (which install into main::) so we can verify
# routing and transform replay without GD / real PNG files.  Each records its
# call into @calls and returns a recognizable value.
our @calls;
*main::load_png_file = sub { push @calls, [ 'load_png_file', @_ ]; return { png => $_[0] }; };
*main::png_rotate    = sub { push @calls, [ 'png_rotate',    @_ ]; return $_[0]; };
*main::png_hmirror   = sub { push @calls, [ 'png_hmirror',   @_ ]; return $_[0]; };
*main::png_vmirror   = sub { push @calls, [ 'png_vmirror',   @_ ]; return $_[0]; };
*main::map_png_colors_to_zx_colors = sub { push @calls, [ 'map',      @_ ]; return 1; };
*main::png_to_pixels_and_attrs     = sub { push @calls, [ 'topixels', @_ ]; return { pixels => 'PX' }; };

# convenience: fully-qualified dispatcher
my $dispatch = \&RAGE::Datagen::PngDispatch::dispatch_png_asset_handling;

# --- scaffold: install the $main::game_config alias ------------------------
my $game_config = { color => { mode => 'mono' }, platform => 'cpc464' };
my $ctx = RAGE::Datagen::Context->new( game_config => \$game_config );
isa_ok( $ctx, 'RAGE::Datagen::Context', 'Context->new returns a blessed object' );
$ctx->install_main_aliases;
is( $main::game_config->{'color'}{'mode'}, 'mono',
    'scaffold aliases the datagen lexical into $main::game_config' );

# --- ZX branch: route to the main:: PNG sub by name ------------------------
{
    @calls = ();
    my $r = $dispatch->( 'zx48', 'load_png_file', '/p.png' );
    is_deeply( \@calls, [ [ 'load_png_file', '/p.png' ] ],
        'zx routes load_png_file to the main:: sub with args' );
    is_deeply( $r, { png => '/p.png' }, 'zx returns the main:: sub result' );
}
{
    eval { $dispatch->( 'zx48', 'no_such_sub' ) };
    like( $@, qr/no PNG-asset sub 'no_such_sub'/,
        'zx unknown fn dies' );
}

# --- CPC MONO: load returns a deferred object ------------------------------
my $obj = $dispatch->( 'cpc464', 'load_png_file', '/q.png' );
is( $obj->{'__cpc_mono'}, 1, 'cpc mono load returns a deferred object' );
is( $obj->{'path'}, '/q.png', 'deferred object carries the source path' );
is_deeply( $obj->{'transforms'}, [], 'deferred object starts with no transforms' );

# --- CPC MONO: transforms accumulate in order ------------------------------
$dispatch->( 'cpc464', 'png_rotate',  $obj, 90 );
$dispatch->( 'cpc464', 'png_hmirror', $obj );
$dispatch->( 'cpc464', 'png_vmirror', $obj );
is_deeply( $obj->{'transforms'},
    [ { op => 'rotate', deg => 90 }, { op => 'hmirror' }, { op => 'vmirror' } ],
    'cpc mono accumulates transforms in call order' );

# --- CPC MONO: map_png_colors_to_zx_colors is a deferred no-op -------------
is( $dispatch->( 'cpc464', 'map_png_colors_to_zx_colors', $obj ), 1,
    'cpc mono map_png_colors_to_zx_colors returns 1 (deferred no-op)' );

# --- CPC MONO terminal: replays transforms then runs the ZX pipeline -------
{
    @calls = ();
    my $data = $dispatch->( 'cpc464', 'png_to_pixels_and_attrs', $obj, 0, 0, 16, 16 );
    is( $calls[0][0], 'load_png_file', 'terminal loads the PNG first' );
    is( $calls[0][1], '/q.png',        'terminal loads the recorded path' );
    is( $calls[1][0], 'png_rotate',    'replays rotate first' );
    is( $calls[1][2], 90,              'replays rotate degrees' );
    is( $calls[2][0], 'png_hmirror',   'replays hmirror second' );
    is( $calls[3][0], 'png_vmirror',   'replays vmirror third' );
    is( $calls[4][0], 'map',           'colour-maps after transforms' );
    is( $calls[5][0], 'topixels',      'extracts pixels last' );
    is_deeply( [ @{ $calls[5] }[ 2 .. 5 ] ], [ 0, 0, 16, 16 ],
        'extract receives xpos/ypos/width/height' );
    is_deeply( $data, { pixels => 'PX' }, 'terminal returns the pipeline result' );
}

# --- CPC MONO: PNG sprite assets are unsupported (die) ---------------------
{
    my $sobj = $dispatch->( 'cpc464', 'load_png_file', '/s.png' );
    eval { $dispatch->( 'cpc464', 'pick_pixel_data_by_color_from_png', $sobj ) };
    like( $@, qr/CPC PNG sprite assets are not supported/,
        'cpc mono PNG sprite asset dies' );
}

# --- CPC FULL-COLOUR: unsupported since R10 (die) — read via the scaffold --
# Mutating the config hash through the lexical must be visible to the module.
$game_config->{'color'}{'mode'} = 'full';
{
    eval { $dispatch->( 'cpc464', 'load_png_file', '/x.png' ) };
    like( $@, qr/full-colour CPC PNG assets are not/,
        'cpc full-colour dies; module sees config mutation via the scaffold' );
}

# --- scaffold tracks FULL reassignment of the datagen lexical --------------
# This is the crux of the glob-alias-to-lexical mechanism: reassigning the
# whole $game_config lexical (as datagen.pl's parser does) must be seen through
# $main::game_config in the module.
$game_config = { color => { mode => 'mono' }, platform => 'cpc464' };
{
    my $r = $dispatch->( 'cpc464', 'load_png_file', '/y.png' );
    is( $r->{'__cpc_mono'}, 1,
        'scaffold alias tracks full reassignment of the $game_config lexical' );
}

# --- unknown platform / undef args die -------------------------------------
{
    eval { $dispatch->( 'amiga', 'load_png_file', '/z.png' ) };
    like( $@, qr/Unknown platform 'amiga'/, 'unknown platform dies' );
    eval { $dispatch->( undef, 'load_png_file' ) };
    like( $@, qr/platform is undefined/, 'undef platform dies' );
    eval { $dispatch->( 'zx48', undef ) };
    like( $@, qr/function name is undefined/, 'undef fn dies' );
}

done_testing();

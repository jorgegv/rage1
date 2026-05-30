#!/usr/bin/env perl
##
## cpc_asset_convert.pl — thin wrapper around cpct_img2tileset for RAGE1.
##
## PURPOSE
##   Gives datagen.pl (Phase A5) and the R3 PoC a *fixed invocation surface*
##   for CPC asset conversion, decoupled from cpctelera's CPCT_PATH
##   environment-variable assumptions.  When called, this script locates
##   cpct_img2tileset (or falls back to the vendored one), sets CPCT_PATH, and
##   delegates.
##
## INVOCATION MODES
##
##   Mode 1 — tileset  (default, --mode tileset)
##     Converts a PNG containing a grid of same-size tiles into a .c/.h pair
##     with one array per tile and an optional tileset pointer-array.
##     Corresponds to cpct_img2tileset's native behaviour.
##
##   Mode 2 — sprite-sheet  (--mode spritesheet)
##     Produces a single sprite (no tileset pointer-array), replicating the
##     flag set that cpctelera's IMG2SPRITES Makefile macro uses: -nt (no
##     tileset) and optional interlaced-mask support (-im/-t).
##     Use for individual sprites rather than grid tilesets.
##
## USAGE
##   tools/cpc_asset_convert.pl [OPTIONS] <input.png>
##
##   Options:
##     --mode <tileset|spritesheet>   Invocation mode (default: tileset)
##     --cpc-mode <0|1|2>             CPC graphics mode (default: 1)
##     --tile-w <pixels>              Tile/sprite width in pixels (default: 4)
##     --tile-h <pixels>              Tile/sprite height in pixels (default: 4)
##     --basename <name>              C identifier prefix (default: g_tile)
##     --output <path>                Output path stem (without .c/.h; default:
##                                    same dir/name as input PNG)
##     --palette-fw <n,n,n,...>       Comma-separated firmware palette indices
##                                    (up to 4 for mode 1).  Overrides the
##                                    cpct_img2tileset default.
##     --mask                         Enable interlaced-mask generation (sets
##                                    -im on the underlying call); sets colour
##                                    index 0 as transparent unless --transparent
##                                    overrides it.
##     --transparent <index>          Palette index to use as transparent colour
##                                    (default 0 when --mask is given).
##     --no-tileset                   Suppress tileset pointer-array output.
##     --cpct-path <dir>              Explicit path to cpctelera root
##                                    (default: auto-detect from this script's
##                                    location, falling back to CPCT_PATH env).
##     --help                         Print this help and exit.
##
## OUTPUT CONTRACT (for Phase A5 datagen wiring)
##   Given --output /path/to/stem the script produces:
##     /path/to/stem.c   — C source with pixel-data arrays
##     /path/to/stem.h   — header with extern declarations
##
##   The .c file uses the standard cpct_img2tileset output format:
##     const unsigned char <basename>_NNN[] = { ... };
##     unsigned char * const <basename>_tileset[] = { ... };  // tileset mode only
##
## ENVIRONMENT
##   CPCT_PATH  Overridden by --cpct-path.  If absent and auto-detection fails,
##              the script exits with a diagnostic.
##
## NOTES
##   - cpctelera itself is never compiled by RAGE1 (Option b translation model;
##     see doc/multiplatform-plan/cpc-renderer.md §4.2).  This script only
##     uses cpctelera's *host-side* asset converter tools (Img2CPC + the
##     cpct_img2tileset bash script).
##   - Phase A5 (datagen.pl wiring) is OUT OF SCOPE for R3.  This script's
##     I/O contract is designed to be stable so A5 can call it without changes.
##
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use File::Basename qw(basename dirname);
use File::Spec;
use Cwd qw(abs_path);

## ---------------------------------------------------------------------------
## Defaults
## ---------------------------------------------------------------------------
my $mode         = 'tileset';
my $cpc_mode     = 1;
my $tile_w       = 4;
my $tile_h       = 4;
my $basename     = 'g_tile';
my $output       = '';
my $palette_fw   = '';
my $mask         = 0;
my $transparent  = -1;     # -1 = not set explicitly; will be 0 if --mask
my $no_tileset   = 0;
my $cpct_path    = '';
my $help         = 0;

## ---------------------------------------------------------------------------
## Parse arguments
## ---------------------------------------------------------------------------
GetOptions(
    'mode=s'          => \$mode,
    'cpc-mode=i'      => \$cpc_mode,
    'tile-w=i'        => \$tile_w,
    'tile-h=i'        => \$tile_h,
    'basename=s'      => \$basename,
    'output=s'        => \$output,
    'palette-fw=s'    => \$palette_fw,
    'mask'            => \$mask,
    'transparent=i'   => \$transparent,
    'no-tileset'      => \$no_tileset,
    'cpct-path=s'     => \$cpct_path,
    'help'            => \$help,
) or usage_and_exit(1);

usage_and_exit(0) if $help;

die "ERROR: exactly one input PNG is required\n"     unless @ARGV == 1;
die "ERROR: --mode must be 'tileset' or 'spritesheet'\n"
    unless $mode eq 'tileset' || $mode eq 'spritesheet';
die "ERROR: --cpc-mode must be 0, 1, or 2\n"
    unless $cpc_mode == 0 || $cpc_mode == 1 || $cpc_mode == 2;

my $input_png = $ARGV[0];
die "ERROR: input file '$input_png' does not exist\n" unless -f $input_png;

## ---------------------------------------------------------------------------
## Locate cpct_img2tileset
## ---------------------------------------------------------------------------

# Auto-detect CPCT_PATH from this script's location (tools/ → external/cpctelera)
if (!$cpct_path) {
    my $script_dir = dirname(abs_path($0));
    my $repo_root  = dirname($script_dir);   # tools/ → repo root
    my $candidate  = "$repo_root/external/cpctelera/cpctelera";
    if (-d $candidate && -f "$candidate/tools/scripts/cpct_img2tileset") {
        $cpct_path = $candidate;
    }
}

# Fall back to CPCT_PATH environment variable
$cpct_path ||= $ENV{CPCT_PATH} // '';

if ($cpct_path) {
    # Use the vendored script with explicit CPCT_PATH
    my $vendored = "$cpct_path/tools/scripts/cpct_img2tileset";
    die "ERROR: cpct_img2tileset not found at $vendored\n" unless -x $vendored;
    $ENV{CPCT_PATH} = $cpct_path;
    run_converter($vendored, $input_png);
} else {
    # Fall back to whatever is on PATH (the wrapper installed by
    # install-cpctelera-converters.sh or by the CI image)
    my $on_path = `which cpct_img2tileset 2>/dev/null`;
    chomp $on_path;
    die "ERROR: cpct_img2tileset not found.\n" .
        "       Install it with: tools/install-cpctelera-converters.sh\n" .
        "       or set CPCT_PATH / use --cpct-path\n" unless $on_path;
    run_converter($on_path, $input_png);
}

## ---------------------------------------------------------------------------
## Build and run the cpct_img2tileset command
## ---------------------------------------------------------------------------
sub run_converter {
    my ($converter, $png) = @_;

    # Resolve output stem
    my $stem;
    if ($output) {
        $stem = $output;
    } else {
        my $base = basename($png);
        $base =~ s/\.[^.]+$//;   # strip extension
        $stem = dirname(abs_path($png)) . "/$base";
    }

    my @args = (
        $converter,
        '-m', $cpc_mode,
        '-tw', $tile_w,
        '-th', $tile_h,
        '-bn', $basename,
    );

    # Mode-specific flags
    if ($mode eq 'spritesheet') {
        # Sprite-sheet mode: no tileset array (replicates IMG2SPRITES macro)
        push @args, '-nt';
    }

    if ($no_tileset) {
        push @args, '-nt' unless $mode eq 'spritesheet';  # already added
    }

    # Mask flags
    if ($mask) {
        push @args, '-im';
        if ($transparent >= 0) {
            push @args, '-t', $transparent;
        }
        # -im sets colour index 0 as transparent by default (cpct_img2tileset behaviour)
    } elsif ($transparent >= 0) {
        push @args, '-t', $transparent;
    }

    # Firmware palette override.
    # NOTE: cpct_img2tileset has a known issue where it passes all 16 default
    # palette entries to img2cpc even for mode 1 (max 4) or mode 2 (max 2),
    # causing img2cpc to reject the command.  Work around it by always
    # providing an explicit firmware palette, defaulting to the standard
    # CPC mode-1 / mode-2 values when the caller doesn't supply one.
    my %default_palettes = (
        0 => '1,24,20,6,26,0,2,8,10,12,14,16,18,22,24,16',  # mode 0: 16 colours
        1 => '1,24,20,6',                                     # mode 1: 4 colours (cpct default subset)
        2 => '1,24',                                          # mode 2: 2 colours
    );
    my $eff_palette = $palette_fw || $default_palettes{$cpc_mode};
    my @pf = split /,/, $eff_palette;
    push @args, '-pf', '{', @pf, '}';

    push @args, $png;

    # cpct_img2tileset writes <stem>.c and <stem>.h in the CWD unless we
    # change directory.  The script derives its output filenames from the
    # input filename (stripping extension), ignoring any -o flag.  So we
    # run it from the output directory after symlinking / copying the PNG
    # there if necessary.
    my $out_dir   = dirname($stem);
    my $out_base  = basename($stem);
    my $png_abs   = abs_path($png);

    # Ensure output dir exists
    unless (-d $out_dir) {
        system('mkdir', '-p', $out_dir) == 0
            or die "ERROR: could not create output dir $out_dir\n";
    }

    # cpct_img2tileset derives the output filename from the input filename.
    # If the stem basename differs from the PNG basename, we need to either
    # rename afterwards or use a temp symlink so the output files land with
    # the right name.  Simplest approach: run in the output dir, rename if needed.
    my $png_base_noext = basename($png_abs);
    $png_base_noext =~ s/\.[^.]+$//;

    # Run converter with CWD = out_dir; pass absolute PNG path.
    # The converter writes $png_base_noext.c / .h in CWD.
    my @cmd = @args;
    $cmd[-1] = $png_abs;   # replace last arg with abs path

    print "cpc_asset_convert: running\n  " . join(' ', @cmd) . "\n";
    my $rc = system(@cmd);
    die "ERROR: converter exited with code " . ($rc >> 8) . "\n" if $rc;

    # If stem base != PNG base, rename produced files
    my $produced_c = "$out_dir/$png_base_noext.c";
    my $produced_h = "$out_dir/$png_base_noext.h";
    my $wanted_c   = "$stem.c";
    my $wanted_h   = "$stem.h";

    if ($produced_c ne $wanted_c) {
        rename($produced_c, $wanted_c) or die "ERROR: rename $produced_c -> $wanted_c: $!\n";
    }
    if ($produced_h ne $wanted_h) {
        rename($produced_h, $wanted_h) or die "ERROR: rename $produced_h -> $wanted_h: $!\n";
    }

    print "cpc_asset_convert: generated $wanted_c\n";
    print "cpc_asset_convert: generated $wanted_h\n";
}

## ---------------------------------------------------------------------------
## Help
## ---------------------------------------------------------------------------
sub usage_and_exit {
    my $code = shift;
    print <<'END';
Usage: tools/cpc_asset_convert.pl [OPTIONS] <input.png>

Thin wrapper around cpct_img2tileset for RAGE1 CPC asset conversion.

Options:
  --mode <tileset|spritesheet>   Conversion mode (default: tileset)
  --cpc-mode <0|1|2>             CPC graphics mode (default: 1)
  --tile-w <pixels>              Tile/sprite width in pixels (default: 4)
  --tile-h <pixels>              Tile/sprite height in pixels (default: 4)
  --basename <name>              C identifier prefix (default: g_tile)
  --output <path>                Output path stem, without .c/.h extension
  --palette-fw <n,n,...>         Comma-separated firmware palette indices
  --mask                         Enable interlaced masks (transparent index 0)
  --transparent <index>          Override transparent palette index
  --no-tileset                   Suppress tileset pointer-array in output
  --cpct-path <dir>              Explicit path to cpctelera root
  --help                         This help text

Examples:
  # 16x8-pixel tileset from test.png, mode 1, basename g_spr:
  tools/cpc_asset_convert.pl --mode tileset --cpc-mode 1 \
      --tile-w 16 --tile-h 8 --basename g_spr \
      --output build/generated/cpc/test  test.png

  # Single sprite (no tileset array), with mask, mode 1:
  tools/cpc_asset_convert.pl --mode spritesheet --cpc-mode 1 \
      --tile-w 16 --tile-h 16 --mask --basename hero  hero.png
END
    exit $code;
}

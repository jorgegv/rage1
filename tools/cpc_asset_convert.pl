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
##                                    (up to 4 for mode 1, 2 for mode 2, 16 for
##                                    mode 0).  See PALETTE note below.
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
## PALETTE (IMPORTANT)
##   Because of a cpct_img2tileset bug (it forwards all 16 default firmware
##   entries to Img2CPC even in mode 1/2, which Img2CPC then rejects), this
##   wrapper ALWAYS emits an explicit firmware palette.  When --palette-fw is
##   omitted it falls back to a GENERIC CPC default (mode 1: {1,24,20,6}).
##   That generic default is only a convenience so the tool runs argument-free
##   for the R3 PoC.  REAL GAMES (A5/R4) MUST pass --palette-fw with the game's
##   actual palette — otherwise PNG colours are quantised to the generic set
##   and will be wrong.
##
## OUTPUT LOCATION
##   Img2CPC ignores CWD and writes its .c/.h next to the INPUT PNG.  This
##   wrapper transparently moves them to the --output stem afterwards, so
##   --output may point at any directory (e.g. build/generated/cpc/).  The
##   generated .h's include guard is rewritten to a deterministic,
##   basename-only symbol so output is reproducible across build paths.
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
use File::Copy qw(move);
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

    # Firmware palette.
    # NOTE: cpct_img2tileset has a known bug where it passes all 16 default
    # palette entries to img2cpc even for mode 1 (max 4) or mode 2 (max 2),
    # causing img2cpc to reject the command.  We therefore ALWAYS emit an
    # explicit -pf flag (the workaround), taking the palette from --palette-fw.
    #
    # IMPORTANT FOR REAL GAMES (A5 / R4): the fallback below is a generic
    # CPC firmware default *only* so the tool runs without a palette argument
    # (e.g. for the R3 PoC).  Real game PNGs MUST pass --palette-fw with the
    # game's actual palette, or colours will be mis-quantised to this generic
    # set.  See the file header and --help.
    my %default_palettes = (
        0 => '1,24,20,6,26,0,2,8,10,12,14,16,18,22,24,16',  # mode 0: 16 colours
        1 => '1,24,20,6',                                     # mode 1: 4 colours (cpct generic default)
        2 => '1,24',                                          # mode 2: 2 colours
    );
    my $eff_palette = $palette_fw || $default_palettes{$cpc_mode};
    my @pf = split /,/, $eff_palette;
    push @args, '-pf', '{', @pf, '}';

    my $png_abs = abs_path($png);
    push @args, $png_abs;

    # cpct_img2tileset / Img2CPC IGNORE the working directory and any -o stem:
    # they derive the output filename from the INPUT PNG path, writing
    # <png_dir>/<png_basename_noext>.c and .h right next to the PNG.  We must
    # therefore compute the produced paths from the PNG location, run the
    # converter, then move the results to the requested --output stem (which
    # may live in a completely different directory, e.g. build/generated/cpc/).
    my $png_dir         = dirname($png_abs);
    my $png_base_noext  = basename($png_abs);
    $png_base_noext     =~ s/\.[^.]+$//;
    my $produced_c      = "$png_dir/$png_base_noext.c";
    my $produced_h      = "$png_dir/$png_base_noext.h";

    # Ensure the destination directory exists (the stem may point elsewhere).
    my $out_dir = dirname(File::Spec->rel2abs($stem));
    unless (-d $out_dir) {
        system('mkdir', '-p', $out_dir) == 0
            or die "ERROR: could not create output dir $out_dir\n";
    }

    print "cpc_asset_convert: running\n  " . join(' ', @args) . "\n";
    my $rc = system(@args);
    die "ERROR: converter exited with code " . ($rc >> 8) . "\n" if $rc;

    -f $produced_c or die "ERROR: expected converter output $produced_c not found\n";
    -f $produced_h or die "ERROR: expected converter output $produced_h not found\n";

    my $wanted_c = "$stem.c";
    my $wanted_h = "$stem.h";

    # Move produced files to the requested stem (no-op if already in place).
    # Use File::Copy::move (not rename) so output dirs on a different
    # filesystem than the PNG (e.g. /tmp vs the repo) work.
    if (File::Spec->rel2abs($produced_c) ne File::Spec->rel2abs($wanted_c)) {
        move($produced_c, $wanted_c)
            or die "ERROR: move $produced_c -> $wanted_c: $!\n";
    }
    if (File::Spec->rel2abs($produced_h) ne File::Spec->rel2abs($wanted_h)) {
        move($produced_h, $wanted_h)
            or die "ERROR: move $produced_h -> $wanted_h: $!\n";
    }

    # B4: Img2CPC derives the .h include guard (and the #include in the .c)
    # from the machine-absolute output path, which is non-reproducible across
    # build dirs / CI.  Rewrite both to a deterministic, basename-only guard.
    rewrite_include_guard($wanted_c, $wanted_h, basename($stem));

    print "cpc_asset_convert: generated $wanted_c\n";
    print "cpc_asset_convert: generated $wanted_h\n";
}

## ---------------------------------------------------------------------------
## Rewrite the machine-absolute include guard that Img2CPC bakes into the .h,
## plus the matching #include in the .c, to a deterministic basename-only form.
## ---------------------------------------------------------------------------
sub rewrite_include_guard {
    my ($c_file, $h_file, $stem_base) = @_;

    # Deterministic guard: __CPC_ASSET_<UPPER_BASENAME>_H_
    ( my $sym = uc $stem_base ) =~ s/[^A-Z0-9]/_/g;
    my $guard = "__CPC_ASSET_${sym}_H_";

    # --- header: replace the #ifndef / #define guard pair ---
    open my $hin, '<', $h_file or die "ERROR: open $h_file: $!\n";
    my @hlines = <$hin>;
    close $hin;

    my $replaced = 0;
    for my $line (@hlines) {
        # Img2CPC emits: #ifndef __....._H_  and  #define __....._H_
        if ($line =~ /^(#ifndef|#define)\s+(\S+_H_)\s*$/) {
            $line = "$1 $guard\n";
            $replaced++;
        }
    }
    if ($replaced >= 2) {
        open my $hout, '>', $h_file or die "ERROR: write $h_file: $!\n";
        print {$hout} @hlines;
        close $hout;
    }

    # --- source: the .c includes the .h by its produced basename; make sure
    #     it points at the renamed header (basename of the stem). ---
    open my $cin, '<', $c_file or die "ERROR: open $c_file: $!\n";
    my @clines = <$cin>;
    close $cin;

    my $touched = 0;
    for my $line (@clines) {
        if ($line =~ /^\s*#include\s+"[^"]*\.h"\s*$/) {
            $line = "#include \"$stem_base.h\"\n";
            $touched++;
            last;   # only the first include (the generated header)
        }
    }
    if ($touched) {
        open my $cout, '>', $c_file or die "ERROR: write $c_file: $!\n";
        print {$cout} @clines;
        close $cout;
    }
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
  --output <path>                Output path stem, without .c/.h extension.
                                 May be in ANY directory (the wrapper moves
                                 Img2CPC's output there; output dir need not
                                 match the PNG dir).
  --palette-fw <n,n,...>         Comma-separated firmware palette indices.
  --mask                         Enable interlaced masks (transparent index 0)
  --transparent <index>          Override transparent palette index
  --no-tileset                   Suppress tileset pointer-array in output
  --cpct-path <dir>              Explicit path to cpctelera root
  --help                         This help text

PALETTE (IMPORTANT):
  This wrapper always emits an explicit firmware palette (workaround for a
  cpct_img2tileset mode-1/2 bug).  Without --palette-fw it uses a GENERIC CPC
  default (mode 1: 1,24,20,6).  REAL GAMES (A5/R4) MUST pass --palette-fw with
  the game's actual palette, or PNG colours will be mis-quantised.

Examples:
  # 16x8-pixel tileset, mode 1, into a DIFFERENT output dir than the PNG,
  # with an explicit game palette:
  tools/cpc_asset_convert.pl --mode tileset --cpc-mode 1 \
      --tile-w 16 --tile-h 8 --basename g_spr --palette-fw 1,24,20,6 \
      --output build/generated/cpc/test  game_data/png/test.png

  # Single sprite (no tileset array), with mask, mode 1:
  tools/cpc_asset_convert.pl --mode spritesheet --cpc-mode 1 \
      --tile-w 16 --tile-h 16 --mask --basename hero --palette-fw 1,24,20,6 \
      hero.png
END
    exit $code;
}

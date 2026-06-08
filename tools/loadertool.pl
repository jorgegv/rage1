#!/usr/bin/env perl

################################################################################
##
## RAGE1 - Retro Adventure Game Engine, release 1
## (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
## 
## This code is published under a GNU GPL license version 3 or later.  See
## LICENSE file in the distribution for details.
## 
################################################################################

use strict;
use warnings;
use utf8;
use Data::Dumper;
use Getopt::Long qw( :config bundling no_ignore_case pass_through );
use Getopt::Std;

use FindBin;
use lib "$FindBin::Bin/../lib";

require RAGE::Config;

# T1-10: file-level CLI option for --platform <zx48|zx128|cpc-flat>. Declared
# here so subs (get_zx_target etc.) can read it. Parsed in main below.
# T2-5: extends accepted values to include cpc-flat.
our $opt_platform;

# filenames are relative to the GENERATED dir, normally 'build/generated'

my $basic_loader_name	= 'loader.bas';
my $asm_loader_name	= 'asmloader.asm';
my $game_config_name	= 'build/game_data/game_config/Game.gdata';
my $main_bin_filename	= 'main_CODE.bin';

my $cfg = rage1_get_config();

my $loader_org_48	= 0x5E00;
my $loader_org_128	= 0x8000;

# auxiliary functions

# bank binaries are files under build/generated/ with names bank_N.bin
sub gather_bank_binaries {
    my ( $dir ) = @_;
    my %binaries;

    opendir BINDIR, $dir or
        die "** Error: could not open directory $dir for reading\n";
    foreach my $bin ( grep { /^bank_.*\.bin/ } readdir BINDIR ) {
        $bin =~ m/^bank_(.*)\.bin/;
        $binaries{ $1 } = {
                'name'	=> $bin,
                'size'	=> ( stat( "$dir/$bin" ) )[7],
                'dir'	=> $dir,
        };
    }
    close BINDIR;
    return \%binaries;
}

sub optional_hex_decode {
    my $value = shift;
    if ( $value =~ m/^0x[0-9a-f]+$/i ) {
        return hex( $value );
    }
    if ( $value =~ m/^\$([0-9a-f]+)$/i ) {
        return hex( $1 );
    }
    return $value;
}

# sub binaries are files under build/generated/ with names sub_<name>.bin
sub gather_sub_binaries {
    my ( $dir ) = @_;
    my %binaries;

    opendir BINDIR, $dir or
        die "** Error: could not open directory $dir for reading\n";
    foreach my $bin ( grep { /^sub_.*\.bin$/ } readdir BINDIR ) {
        $bin =~ m/^sub_(.*)\.bin/;
        $binaries{ $1 }{'name'}	= $bin;
        $binaries{ $1 }{'size'}	= ( stat( "$dir/$bin" ) )[7];
        $binaries{ $1 }{'dir'}	= $dir;
    }
    close BINDIR;

    opendir BINDIR, $dir or
        die "** Error: could not open directory $dir for reading\n";
    foreach my $bin ( grep { /^sub_.*\.bin\.zx0$/ } readdir BINDIR ) {
        $bin =~ m/^sub_(.*)\.bin.zx0/;
        $binaries{ $1 }{'compressed_name'}	= $bin;
        $binaries{ $1 }{'compressed_size'}	= ( stat( "$dir/$bin" ) )[7];
        $binaries{ $1 }{'dir'} 			= $dir;
    }
    close BINDIR;

    my $order = 0;
    open GAME_CONFIG, $game_config_name or
        die "** Error: could not open $game_config_name for reading\n";
    while ( my $line = <GAME_CONFIG> ) {
        chomp( $line );
        $line =~ s/^\s*//g;         # remove leading blanks
        $line =~ s/\/\/.*$//g;      # remove comments (//...)
        $line =~ s/\s*$//g;         # remove trailing blanks
        next if $line eq '';                # ignore blank lines
        if ( $line =~ /^SINGLE_USE_BLOB\s+(\w.*)$/ ) {
            # ARG1=val1 ARG2=va2 ARG3=val3...
            my $args = $1;
            my $item = {
                map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                split( /\s+/, $args )
            };
            my $org_address = $item->{'org_address'} || $item->{'load_address'};
            my $run_address = $item->{'run_address'} || $org_address;
            $binaries{ $item->{'name'} }{'load_address'} = optional_hex_decode( $item->{'load_address'} );
            $binaries{ $item->{'name'} }{'org_address'} = optional_hex_decode( $org_address );
            $binaries{ $item->{'name'} }{'run_address'} = optional_hex_decode( $run_address );
            $binaries{ $item->{'name'} }{'order'} = $order;
            $binaries{ $item->{'name'} }{'compress'} = $item->{'compress'} || 0;
            $order++;
        }
    }

    return \%binaries;
}

# do some sanity checks on the SUB binaries
sub sanity_check_sub_binaries {
    my $bins = shift;

    # check that SUBs do not overlap when loading
    my $errors;
    foreach my $sub_name ( keys %$bins ) {
        my $sub = $bins->{ $sub_name };
        foreach my $another_sub_name ( keys %$bins ) {
            next if $sub_name eq $another_sub_name;
            my $another_sub = $bins->{ $another_sub_name };
            if ( ( $sub->{'load_address'} >= $another_sub->{'load_address'} ) and 
                ( $sub->{'load_address'} <= $another_sub->{'load_address'} + ( $another_sub->{'compress'} ? $another_sub->{'compressed_size'} : $another_sub->{'size'} ) ) ) {
                warn "SINGLE_USE_BLOB: SUB '$sub_name' LOAD_ADDRESS overlaps with SUB '$another_sub_name'\n";
                $errors++;
            }
        }
    }

    # check that compressed SUBs do not decompress over another uncompressed SUBs before those others have been run
    # it only matters if the compressed one is run before the other
    foreach my $sub_name ( keys %$bins ) {
        my $sub = $bins->{ $sub_name };
        next if not $sub->{'compress'};		# ignore uncompressed SUBs
        foreach my $another_sub_name ( keys %$bins ) {
            next if $sub_name eq $another_sub_name;
            my $another_sub = $bins->{ $another_sub_name };
            next if $another_sub->{'compress'};		# ignore compressed SUBs
            if ( ( $sub->{'org_address'} >= $another_sub->{'org_address'} ) and 
                ( $sub->{'org_address'} <= ( $another_sub->{'org_address'} + $another_sub->{'size'} ) ) and
                ( $sub->{'order'} < $another_sub->{'order'} ) ) {
                warn "SINGLE_USE_BLOB: SUB '$sub_name' ORG_ADDRESS overlaps with SUB '$another_sub_name' when decompressing\n";
                $errors++;
            }
        }
    }

    # return
    return ( $errors ? undef : 1 );
}

sub get_zx_target {
    # T1-10: --platform CLI override beats the game's declared default.
    # T2-5: cpc-flat is a valid platform token; return it as-is.
    if ( defined( $opt_platform ) ) {
        my $p = lc( $opt_platform );
        return '48'      if $p eq 'zx48';
        return '128'     if $p eq 'zx128';
        return 'cpc-flat' if $p eq 'cpc-flat';
        return 'cpc-banked' if $p eq 'cpc-banked';
        # Any other value would have died at option-parse time.
    }
    open GAME_CONFIG, $game_config_name or
        die "** Error: could not open $game_config_name for reading\n";
    while ( my $line = <GAME_CONFIG> ) {
        chomp( $line );
        $line =~ s/^\s*//g;         # remove leading blanks
        $line =~ s/\/\/.*$//g;      # remove comments (//...)
        $line =~ s/\s*$//g;         # remove trailing blanks
        next if $line eq '';                # ignore blank lines
        # T2-5: cpc464 maps to cpc-flat loader template.
        if ( $line =~ /^PLATFORM\s+cpc464$/ ) {
            return 'cpc-flat';
        }
        # T3-6: cpc6128 maps to the cpc-banked loader template.
        if ( $line =~ /^PLATFORM\s+cpc6128$/ ) {
            return 'cpc-banked';
        }
        # A1 follow-up: accept the new PLATFORM directive (zx48|zx128) and
        # map it back to the legacy 48|128 internal token. Mirrors the
        # Makefile.common resolution and datagen.pl's PLATFORM parser.
        if ( $line =~ /^PLATFORM\s+zx(48|128)$/ ) {
            return $1;
        }
        # ZX_TARGET is a permanent silent alias for PLATFORM (README §5.6).
        if ( $line =~ /^ZX_TARGET\s+(\w+)$/ ) {
            # ARG1=val1 ARG2=va2 ARG3=val3...
            return $1;
        }
    }
    return '48'; # default
}

sub get_gfx_backend {
    open GAME_CONFIG, $game_config_name or
        die "** Error: could not open $game_config_name for reading\n";
    while ( my $line = <GAME_CONFIG> ) {
        chomp( $line );
        $line =~ s/^\s*//g;
        $line =~ s/\/\/.*$//g;
        $line =~ s/\s*$//g;
        next if $line eq '';
        # Accept both the new GFX_BACKEND keyword and the legacy
        # SPRITE_ENGINE alias (silent, indefinite — per
        # doc/multiplatform-plan/gfx.md §5.6 / README §5.6).
        if ( $line =~ /^(?:GFX_BACKEND|SPRITE_ENGINE)\s+(\w+)$/i ) {
            return lc($1);
        }
    }
    return 'sp1'; # default
}

# get the size of the main.bin file
sub get_main_bin_size {
    my @stat_results = stat( $main_bin_filename );
    return $stat_results[7];
}

###############################################################################
##
## T1-11: template-driven loader generator.
##
## The platform-specific scaffolding lives in
## engine/loader-<platform>/asmloader.asm.in (main file) plus a small set of
## per-snippet templates next to it:
##
##   asmloader.bank-load.snippet.asm.in           (one per bank, 128k only)
##   asmloader.sub-load.snippet.asm.in            (one per SUB)
##   asmloader.sub-run-direct.snippet.asm.in      (uncompressed, no-swap SUB)
##   asmloader.sub-run-swap.snippet.asm.in        (swap-in before run)
##   asmloader.sub-run-unswap.snippet.asm.in      (swap-out after run)
##   asmloader.sub-run-decompress.snippet.asm.in  (decompress + run)
##   asmloader.memswap.snippet.asm.in             (memswap helper routine)
##   asmloader.dzx0.snippet.asm.in                (dzx0_standard helper)
##
## This Perl tool carries NO platform-specific inline loader text — it only
## (a) reads the relevant snippet, (b) substitutes per-iteration @@FOO@@
## placeholders, (c) concatenates per-iteration outputs and substitutes them
## into the main template's placeholders, (d) writes asmloader.asm.
##
## Adding a new platform (Phase T2 CPC bring-up) becomes 'drop new templates
## into engine/loader-<platform>/', no edits to this file.
##
###############################################################################

# Per-platform template directory (relative to repo root). Symlinks under
# engine/ to the legacy loader{48,128} names are accepted (T1-4) but the
# canonical lookup is engine/loader-<platform>/.
# T2-5: cpc-flat added; template lives in engine/loader-cpc-flat/.
my %loader_template_dir = (
    '48'      => 'engine/loader-zx48',
    '128'     => 'engine/loader-zx128',
    'cpc-flat' => 'engine/loader-cpc-flat',
    # T3-6/B7 step 9: cpc-banked (CPC 6128) bank-streaming cold-boot loader.
    'cpc-banked' => 'engine/loader-cpc-banked',
);

sub _slurp {
    my ( $path ) = @_;
    open my $fh, '<', $path
        or die "** Error: could not open template '$path' for reading: $!\n";
    local $/;
    my $contents = <$fh>;
    close $fh;
    return $contents;
}

sub _template_path {
    my ( $zx_target, $stem ) = @_;
    my $dir = $loader_template_dir{ $zx_target }
        or die "** Error: no loader template directory for ZX target '$zx_target'\n";
    return "$dir/$stem";
}

sub _load_template {
    my ( $zx_target ) = @_;
    return _slurp( _template_path( $zx_target, 'asmloader.asm.in' ) );
}

# Apply hash of @@KEY@@ -> value substitutions to a template string.
sub _apply_substitutions {
    my ( $tmpl, $subst ) = @_;
    # iterate by length-desc to avoid prefix collisions if any future
    # placeholder name is a prefix of another.
    for my $key ( sort { length($b) <=> length($a) } keys %$subst ) {
        my $val = $subst->{ $key };
        $tmpl =~ s/\@\@\Q$key\E\@\@/$val/g;
    }
    return $tmpl;
}

# Build the BANK_LOAD_BLOCK placeholder content by repeatedly substituting
# the per-bank snippet template. Per the original tool, every block written
# ends with '\n\n' (snippet's trailing newline + the explicit blank-line
# separator emitted between every block in the legacy output).
sub _build_bank_load_block {
    my ( $zx_target, $bank_bins ) = @_;
    return '' unless ( $zx_target eq '128' or $zx_target eq 'cpc-banked' );
    my $snippet = _slurp( _template_path( $zx_target, 'asmloader.bank-load.snippet.asm.in' ) );
    my $out = '';
    foreach my $bank ( sort keys %$bank_bins ) {
        my %tokens = (
            BANK      => $bank,
            BANK_SIZE => $bank_bins->{ $bank }{'size'},
        );
        # cpc-banked: per-bank firmware file load (BANK<n>.BIN) + Gate-Array
        # Config select.  The bank number maps 1:1 to the GA RAM Config
        # (DC1: Config N -> RAM N; the GA value is 0xC0 | (bank & 7)),
        # mirroring the engine's 00bswitch.c CPC arm.  ($bank is a string
        # hash key; the +0 just keeps it in unambiguous numeric context.)
        if ( $zx_target eq 'cpc-banked' ) {
            my $file = sprintf( 'BANK%s.BIN', $bank );
            $tokens{ 'BANK_FILE' }       = $file;
            $tokens{ 'BANK_FILE_LEN' }   = length( $file );
            $tokens{ 'BANK_CONFIG_HEX' } = sprintf( 'C%X', ( $bank + 0 ) & 0x07 );
        }
        $out .= _apply_substitutions( $snippet, \%tokens );
        $out .= "\n";
    }
    return $out;
}

# Build the SUB_LOAD_BLOCK placeholder content. Same '\n\n' end convention.
sub _build_sub_load_block {
    my ( $zx_target, $sub_bins ) = @_;
    my $snippet = _slurp( _template_path( $zx_target, 'asmloader.sub-load.snippet.asm.in' ) );
    my $out = '';
    foreach my $sub ( sort {
            $sub_bins->{ $a }{'order'} <=> $sub_bins->{ $b }{'order'}
        } keys %$sub_bins ) {
        my $sub_size = ( $sub_bins->{ $sub }{'compress'} ?
            $sub_bins->{ $sub }{'compressed_size'} :
            $sub_bins->{ $sub }{'size'}
        );
        $out .= _apply_substitutions( $snippet, {
            SUB_NAME      => $sub,
            SUB_SIZE      => $sub_size,
            SUB_LOAD_ADDR => sprintf( '0x%04x', $sub_bins->{ $sub }{'load_address'} ),
        } );
        $out .= "\n";
    }
    return $out;
}

# Build the SUB_RUN_BLOCK placeholder content from the per-case snippets,
# and tell the caller whether memswap / decompress helper routines need to
# be emitted afterwards. The original tool emitted, for each SUB:
#   - one literal label "    ;; Run SUB '$sub' with ints disabled\n"
#     (single '\n' — pushed as a plain string, not a heredoc)
#   - one or more heredoc-style blocks, each ending with '\n\n'
# The reconstruction below preserves both conventions verbatim.
sub _build_sub_run_block {
    my ( $zx_target, $sub_bins ) = @_;
    my $snip_direct     = _slurp( _template_path( $zx_target, 'asmloader.sub-run-direct.snippet.asm.in'     ) );
    my $snip_swap       = _slurp( _template_path( $zx_target, 'asmloader.sub-run-swap.snippet.asm.in'       ) );
    my $snip_unswap     = _slurp( _template_path( $zx_target, 'asmloader.sub-run-unswap.snippet.asm.in'     ) );
    my $snip_decompress = _slurp( _template_path( $zx_target, 'asmloader.sub-run-decompress.snippet.asm.in' ) );
    my $out = '';
    my $some_subs_are_compressed = 0;
    my $some_subs_are_swapped    = 0;
    foreach my $sub ( sort {
            $sub_bins->{ $a }{'order'} <=> $sub_bins->{ $b }{'order'}
        } keys %$sub_bins ) {
        my $tokens = {
            SUB_NAME      => $sub,
            SUB_SIZE      => $sub_bins->{ $sub }{'size'},
            SUB_LOAD_ADDR => sprintf( '0x%04x', $sub_bins->{ $sub }{'load_address'} ),
            SUB_ORG_ADDR  => sprintf( '0x%04x', $sub_bins->{ $sub }{'org_address'}  ),
            SUB_RUN_ADDR  => sprintf( '0x%04x', $sub_bins->{ $sub }{'run_address'}  ),
        };

        # Label line — single '\n' to match the legacy format.
        $out .= "    ;; Run SUB '$sub' with ints disabled\n";

        if ( $sub_bins->{ $sub }{'compress'} ) {
            $some_subs_are_compressed++;
            $out .= _apply_substitutions( $snip_decompress, $tokens );
            $out .= "\n";
        } else {
            my $load_addr = $tokens->{'SUB_LOAD_ADDR'};
            my $org_addr  = $tokens->{'SUB_ORG_ADDR'};
            if ( $load_addr ne $org_addr ) {
                $some_subs_are_swapped++;
                $out .= _apply_substitutions( $snip_swap, $tokens );
                $out .= "\n";
            }
            $out .= _apply_substitutions( $snip_direct, $tokens );
            $out .= "\n";
            if ( $load_addr ne $org_addr ) {
                $out .= _apply_substitutions( $snip_unswap, $tokens );
                $out .= "\n";
            }
        }
    }
    return ( $out, $some_subs_are_swapped, $some_subs_are_compressed );
}

sub _memswap_function_block {
    my ( $zx_target ) = @_;
    return _slurp( _template_path( $zx_target, 'asmloader.memswap.snippet.asm.in' ) ) . "\n";
}

sub _decompress_function_block {
    my ( $zx_target ) = @_;
    return _slurp( _template_path( $zx_target, 'asmloader.dzx0.snippet.asm.in' ) ) . "\n";
}

sub generate_assembler_loader {
    my ( $bank_bins, $sub_bins, $outdir ) = @_;
    my $asm_loader = $outdir . '/' . $asm_loader_name;

    my $zx_target  = get_zx_target;

    # T2-5: cpc-flat loader: no banking, no SUBs.  The CRT loads at
    # CRT_ORG_CODE=0x1200; the loader stub just does jp to that address.
    # The cpc-flat template only uses @@LOADER_ORG@@ and @@MAIN_CODE_START@@
    # (no @@MAIN_SIZE@@), so we deliberately do NOT call get_main_bin_size
    # here — it would read the not-yet-existent build/main.bin and is unused.
    if ( $zx_target eq 'cpc-flat' ) {
        my $loader_org = '0x0100';   # small stub in low RAM, well below code
        my $main_code_start = '0x1200';   # CRT_ORG_CODE from zpragma-cpc-flat.inc

        my $tmpl = _apply_substitutions( _load_template( $zx_target ), {
            LOADER_ORG       => $loader_org,
            MAIN_CODE_START  => $main_code_start,
        } );

        if ( $tmpl =~ /\@\@(\w+)\@\@/ ) {
            die "** Error: loadertool.pl: template $loader_template_dir{$zx_target}/asmloader.asm.in references an unknown placeholder '\@\@$1\@\@'\n";
        }

        open my $asm, '>', $asm_loader
            or die "\n** Error: could not open $asm_loader for writing\n";
        print $asm $tmpl;
        close $asm;
        return;
    }

    # B7 step 9 (T3-6): cpc-banked loader.  Like cpc-flat (no @@MAIN_SIZE@@:
    # the resident engine is loaded by AMSDOS, not by this loader) but WITH
    # the per-bank firmware streaming block.  No SUBs at this phase (the B7
    # smoke game has none; SUBs on cpc-banked are Phase B8 — so the cpc-banked
    # template carries no @@SUB_*@@ placeholders).
    #
    # LOADER_ORG / MAIN_CODE_START are literals here for now; DC6 lifts them
    # into YAML when the cpc-banked banking build integration lands (step-9
    # increment 2 — Makefile-cpc-banked + asmloader cold-boot entry).
    if ( $zx_target eq 'cpc-banked' ) {
        my $loader_org      = '0x0100';   # standalone LOADER.BIN, low-RAM gap
        my $main_code_start = '0x1200';   # engine entry/ORG (CRT_ORG_CODE, Shape A)
        # Model 2 (design note §8.5): the loader is a SEPARATE LOADER.BIN that
        # also firmware-loads the headerless engine image (GAME.BIN) -> engine
        # ORG, in addition to the bank files.
        my $main_file       = 'GAME.BIN';

        my $bank_load_block = _build_bank_load_block( $zx_target, $bank_bins );

        my $tmpl = _apply_substitutions( _load_template( $zx_target ), {
            LOADER_ORG       => $loader_org,
            MAIN_CODE_START  => $main_code_start,
            MAIN_FILE        => $main_file,
            MAIN_FILE_LEN    => length( $main_file ),
            BANK_LOAD_BLOCK  => $bank_load_block,
        } );

        if ( $tmpl =~ /\@\@(\w+)\@\@/ ) {
            die "** Error: loadertool.pl: template $loader_template_dir{$zx_target}/asmloader.asm.in references an unknown placeholder '\@\@$1\@\@'\n";
        }

        open my $asm, '>', $asm_loader
            or die "\n** Error: could not open $asm_loader for writing\n";
        print $asm $tmpl;
        close $asm;
        return;
    }

    my $loader_org = sprintf( '0x%04x',
        ( $zx_target eq '48' ? $loader_org_48 : $loader_org_128 ) );

    # main code start address
    my $main_code_start;
    if ( $zx_target eq '128' ) {
        # 128K interrupt config is the same for both sprite engines
        my $int_key = 'interrupts_128';
        $main_code_start = sprintf( '0x%04x',
            ( $cfg->{ $int_key }{'base_code_address'} =~ /^0x/ ?
                hex( $cfg->{ $int_key }{'base_code_address'} ) :
                $cfg->{ $int_key }{'base_code_address'}
            )
        );
    } else {
        $main_code_start = '0x5f00';
    }
    my $main_size = get_main_bin_size;

    # build dynamic blocks (each block ends '\n\n' so substituted output
    # matches the legacy code's "push heredoc / printf %s\n" idiom).
    my $bank_load_block = _build_bank_load_block( $zx_target, $bank_bins );
    my $sub_load_block  = _build_sub_load_block( $zx_target, $sub_bins );
    my ( $sub_run_block, $some_subs_are_swapped, $some_subs_are_compressed )
        = _build_sub_run_block( $zx_target, $sub_bins );
    my $memswap_function_block    = $some_subs_are_swapped    ? _memswap_function_block( $zx_target )    : '';
    my $decompress_function_block = $some_subs_are_compressed ? _decompress_function_block( $zx_target ) : '';

    # load the main template and substitute placeholders
    my $tmpl = _apply_substitutions( _load_template( $zx_target ), {
        LOADER_ORG           => $loader_org,
        MAIN_CODE_START      => $main_code_start,
        MAIN_SIZE            => $main_size,
        BANK_LOAD_BLOCK      => $bank_load_block,
        SUB_LOAD_BLOCK       => $sub_load_block,
        SUB_RUN_BLOCK        => $sub_run_block,
        MEMSWAP_FUNCTION     => $memswap_function_block,
        DECOMPRESS_FUNCTION  => $decompress_function_block,
    } );

    # sanity: refuse to emit a loader that still contains placeholders
    if ( $tmpl =~ /\@\@(\w+)\@\@/ ) {
        die "** Error: loadertool.pl: template $loader_template_dir{$zx_target}/asmloader.asm.in references an unknown placeholder '\@\@$1\@\@'\n";
    }

    open my $asm, '>', $asm_loader
        or die "\n** Error: could not open $asm_loader for writing\n";
    print $asm $tmpl;
    close $asm;
}

##
## Main
##

# parse command options
# -i and -o: input bin dir and output file
# -s: add instructions to load an initial SCREEN$ (optional)
# T1-10: --platform <zx48|zx128> (canonical CLI override). When absent,
# the platform is resolved from the PLATFORM/ZX_TARGET directive in the
# game's .gdata (the A1 follow-up flow, see get_zx_target). CPC values
# are rejected with 'not yet implemented' (Phase T2 brings them up).
# ($opt_platform declared file-level near top so subs can read it.)
GetOptions( 'platform=s' => \$opt_platform ) or
    die "usage: $0 -i <dataset_bin_dir> -o <output_dir> [-s] [--platform <zx48|zx128|cpc-flat|cpc-banked>]\n";

if ( defined( $opt_platform ) ) {
    my $p = lc( $opt_platform );
    # T2-5: cpc-flat supported.  T3-6/B7 step 9: cpc-banked supported.
    if ( $p ne 'zx48' and $p ne 'zx128' and $p ne 'cpc-flat' and $p ne 'cpc-banked' ) {
        if ( $p =~ /^cpc/ ) {
            die "** Error: loadertool.pl --platform $opt_platform: accepted CPC platforms are 'cpc-flat' | 'cpc-banked'.\n";
        }
        die "** Error: loadertool.pl --platform $opt_platform: accepted values are zx48 | zx128 | cpc-flat | cpc-banked.\n";
    }
}

our( $opt_i, $opt_o, $opt_s );
getopts("i:o:s");
( defined( $opt_i ) and defined( $opt_o ) ) or
    die "usage: $0 -i <dataset_bin_dir> -o <output_dir> [-s] [--platform <zx48|zx128|cpc-flat|cpc-banked>]\n";

my $loading_screen = $opt_s;

# if $lowmem_output_dir is not specified, use same as $output_dir
my ( $input_dir, $output_dir ) = ( $opt_i, $opt_o );

my $bank_bins = gather_bank_binaries( $input_dir );
my $sub_bins = gather_sub_binaries( $input_dir );

sanity_check_sub_binaries( $sub_bins ) or
    die "** Error: some SUB consistency checks failed\n";

generate_assembler_loader( $bank_bins, $sub_bins, $output_dir );

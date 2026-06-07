package RAGE::Datagen::ColorTokens;

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
## RAGE::Datagen::ColorTokens — platform-neutral colour-token resolution for
## datagen.  Extracted verbatim from tools/datagen.pl (Task 6, Stage 2 leaf
## module): a pure string->string transform, no shared datagen state, so the
## emitted bytes are byte-identical to the in-line version.
##
################################################################################

use strict;
use warnings;
use utf8;

use Exporter 'import';
our @EXPORT_OK = qw( resolve_color_tokens );

######################################
#
# Platform-neutral colour tokens accepted in shared `.gdata` for the
# global mono-mode directives `GAMEAREA_ATTR` (inside the COLOR
# directive) and `DEFAULT_BG_ATTR`. Per README §5.10, the FG_/BG_
# prefix picks the role, the colour name indexes the table, and
# `BRIGHT` / `FLASH` are modifiers. Compound spellings like
# `BRIGHT_BLUE` are accepted (the inner BRIGHT_ unfolds to a separate
# BRIGHT modifier).
#
# OQ-A9: the CPC firmware-colour column on the right of the
# canonical table at README §5.10 lines 556-573 must be verified
# (cross-checked against actual cpctelera firmware-colour numbers and
# nominal RGB matches) before Phase A5's CPC bring-up uses these
# resolutions to drive the mono-mode pen palette and the blit-time
# LUT. Until then, A1-7 is ZX-side only: the resolver below only
# emits ZX `INK_*` / `PAPER_*` / `BRIGHT` / `FLASH` tokens (byte-
# identical to the legacy spelling) and the CPC column lives only in
# this comment.
#
# CPC firmware-colour mapping (FOR REFERENCE — NOT YET CONSUMED):
#   BLACK        → 0    BLUE         → 1    RED          → 3
#   MAGENTA      → 4    GREEN        → 9    CYAN         → 10
#   YELLOW       → 12   WHITE        → 13
#   BRIGHT BLACK → 0    BRIGHT BLUE  → 2    BRIGHT RED   → 6
#   BRIGHT MAGENTA → 8  BRIGHT GREEN → 18   BRIGHT CYAN  → 20
#   BRIGHT YELLOW → 24  BRIGHT WHITE → 26

# canonical colour name set used by FG_/BG_ tokens (the lone names
# also valid inside BRIGHT_<COLOR> compounds)
my %_canonical_colors = map { ( $_ => 1 ) }
    qw( BLACK BLUE RED MAGENTA GREEN CYAN YELLOW WHITE );

# resolve a single token to its ZX text-form (returns the same string
# unchanged for unknown tokens, so existing INK_*/PAPER_*/BRIGHT/FLASH
# spellings pass through byte-identically).
sub _resolve_color_token {
    my $tok = shift;
    $tok =~ s/^\s+|\s+$//g;
    return $tok if $tok eq '';

    # FG_<COLOR> or FG_BRIGHT_<COLOR>
    if ( $tok =~ /^FG_(.+)$/ ) {
        my $rest = $1;
        if ( $rest =~ /^BRIGHT_(.+)$/ and exists $_canonical_colors{ $1 } ) {
            return "INK_$1 | BRIGHT";
        }
        if ( exists $_canonical_colors{ $rest } ) {
            return "INK_$rest";
        }
        return $tok;  # not a recognized colour name — leave to C compiler
    }
    # BG_<COLOR> or BG_BRIGHT_<COLOR>
    if ( $tok =~ /^BG_(.+)$/ ) {
        my $rest = $1;
        if ( $rest =~ /^BRIGHT_(.+)$/ and exists $_canonical_colors{ $1 } ) {
            return "PAPER_$1 | BRIGHT";
        }
        if ( exists $_canonical_colors{ $rest } ) {
            return "PAPER_$rest";
        }
        return $tok;
    }
    # BRIGHT, FLASH, INK_*, PAPER_*, raw numeric expressions, etc.
    return $tok;
}

# resolve a full pipe-separated expression like "FG_WHITE | BG_BLACK | BRIGHT"
sub resolve_color_tokens {
    my $expr = shift;
    return $expr if not defined $expr;
    my @parts = split /\|/, $expr;
    @parts = map { _resolve_color_token( $_ ) } @parts;
    return join( ' | ', @parts );
}

1;

package RAGE::Datagen::Context;

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
## RAGE::Datagen::Context — shared-state holder for the datagen modularization
## (Task 6, Stage 2).
##
## datagen.pl keeps its ~30 file-scoped globals (model arrays, name->index
## hashes, $game_config, the emit accumulators).  As subs are peeled off into
## RAGE::Datagen::* modules, those modules need to reach that still-in-datagen.pl
## state.  This object holds REFERENCES to the existing datagen.pl lexicals, so
## reads/writes through it act on the very same storage (no copy, byte-neutral).
##
## install_main_aliases() is a TEMPORARY extraction scaffold: it installs each
## held ref into the `main::` symbol table, so an extracted sub can reach a
## global by its fully-qualified name (e.g. `$main::game_config`) WITHOUT every
## call site having to thread a $ctx parameter through — keeping each extraction
## a mechanical, byte-preserving code move.  Aliasing a ref to a lexical (rather
## than the lexical's name) is valid Perl: `*main::game_config = \$game_config`
## makes `$main::game_config` and the lexical share one container, so later
## reassignment of the lexical is seen through the alias too.
##
## The context starts minimal and grows one entry per extraction step (only the
## state a step's module actually touches is added).  Once every state-touching
## sub has moved and takes $ctx explicitly, the glob-alias scaffold is removed.
##
################################################################################

use strict;
use warnings;
use utf8;

# build the context from name => ref pairs (refs to datagen.pl's lexicals).
sub new {
    my ( $class, %refs ) = @_;
    return bless { %refs }, $class;
}

# TEMPORARY scaffold: alias each held ref into main:: under the same name, so
# extracted RAGE::Datagen::* subs can reach datagen.pl globals by fully-
# qualified `main::` name during the incremental extraction.
#
# Each context key MUST be the exact datagen.pl global name (e.g. 'game_config'
# for $game_config) — that is what extracted modules reference as $main::<name>.
# Glob assignment of a scalar/array/hash ref sets only that type-specific slot
# of *main::<name>, so it does NOT clobber a same-named sub (the CODE slot is
# untouched) — e.g. aliasing a var 'foo' leaves any main::foo() intact.
sub install_main_aliases {
    my $self = shift;
    no strict 'refs';
    for my $name ( keys %$self ) {
        *{ "main::$name" } = $self->{ $name };
    }
    return $self;
}

1;

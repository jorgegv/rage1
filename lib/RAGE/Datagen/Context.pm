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
## (Task 6, Stage 2 / Phase 1).
##
## datagen.pl's ~41 file-scoped shared globals (model arrays, name->index
## hashes, $game_config, the emit accumulators) now live HERE, inside the $ctx
## object, as the canonical storage.  datagen.pl's own code reads/writes them as
## $ctx->{field}.
##
## install_main_aliases() is the (now-shrinking) TRANSITIONAL bridge: it aliases
## each $ctx field into the `main::` symbol table under the same name, so the 13
## RAGE::Datagen::* modules — not yet $ctx-threaded — can keep reaching the
## globals by fully-qualified name (e.g. `$main::game_config`, `@main::all_btiles`)
## with no code change.  Aggregate fields (arrays/hashes) are aliased to their
## container ref, scalar fields are aliased to the element (`\$self->{name}`) so
## that a module's reassignment of `$main::game_config` propagates back into the
## $ctx field (and vice-versa).  Phase 2 will thread $ctx into the modules and
## delete this aliasing entirely.
##
################################################################################

use strict;
use warnings;
use utf8;

# the 41 shared fields, grouped by storage type. Used both to seed the typed
# defaults in new() and to know each field's type in install_main_aliases().
my @ARRAY_FIELDS = qw(
    all_btiles all_screens all_sprites all_items all_rules all_crumb_types
    game_events_rule_table check_custom_functions action_custom_functions
    all_codeset_functions c_game_data_lines h_game_data_lines
    h_build_features_lines c_banked_data_128_lines c_tracker_cpc_lines
    codeset_valid_banks valid_game_functions valid_trackers
);

my @HASH_FIELDS = qw(
    conditional_build_features dataset_dependency btile_name_to_index
    sprite_name_to_index screen_name_to_index item_name_to_index
    crumb_type_name_to_index check_custom_function_id action_custom_function_id
    codeset_functions_by_codeset
);

my @SCALAR_FIELDS = qw(
    game_config c_dataset_lines syntax max_flow_var_id hero cfg build_dir
    asm_dataset_lines c_codeset_lines asm_codeset_lines dataset_base_address
    codeset_base_address forced_build_target
);

# build the context: every field gets its typed default (array->[], hash->{},
# scalar->undef), then any %initial pairs the caller passed are overlaid (so
# datagen.pl can seed the few non-empty initial values).
sub new {
    my ( $class, %initial ) = @_;
    my $self = {};
    $self->{ $_ } = []    for @ARRAY_FIELDS;
    $self->{ $_ } = {}    for @HASH_FIELDS;
    $self->{ $_ } = undef for @SCALAR_FIELDS;
    $self->{ $_ } = $initial{ $_ } for keys %initial;
    return bless $self, $class;
}

# TRANSITIONAL bridge: alias each field into main:: under the same name, so the
# not-yet-threaded RAGE::Datagen::* modules can reach the globals by fully-
# qualified `main::` name.  Aggregate fields alias to the container ref;
# scalar fields alias to the element (\$self->{name}) so module reassignments
# of $main::<name> propagate to the $ctx field and vice-versa.
sub install_main_aliases {
    my $self = shift;
    no strict 'refs';
    for my $name ( @ARRAY_FIELDS, @HASH_FIELDS ) {
        *{ "main::$name" } = $self->{ $name };
    }
    for my $name ( @SCALAR_FIELDS ) {
        *{ "main::$name" } = \$self->{ $name };
    }
    return $self;
}

1;

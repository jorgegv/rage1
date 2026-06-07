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
## (Task 6, Stage 2 / Phase 2).
##
## datagen.pl's ~41 file-scoped shared globals (model arrays, name->index
## hashes, $game_config, the emit accumulators) now live HERE, inside the $ctx
## object, as the canonical storage.  datagen.pl's own code reads/writes them as
## $ctx->{field}; the RAGE::Datagen::* modules take $ctx as their first
## positional arg and reach the same fields as $ctx->{field} (Phase 2: the
## transitional main:: aliasing bridge has been removed — $ctx is now threaded
## explicitly through every module sub).
##
################################################################################

use strict;
use warnings;
use utf8;

# the 41 shared fields, grouped by storage type. Used to seed the typed
# defaults in new().
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

1;

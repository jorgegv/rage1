package RAGE::Datagen::FlowRules;

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
## RAGE::Datagen::FlowRules — flow-rule validation/compilation, deduplication
## and C emission for datagen (Task 6, Stage 2 extraction).  Moved verbatim from
## tools/datagen.pl; the shared globals live in the RAGE::Datagen::Context
## object ($ctx), threaded in as the first positional arg of each sub and
## reached as $ctx->{all_rules}, $ctx->{all_screens}, $ctx->{game_events_rule_table},
## $ctx->{screen_name_to_index}, $ctx->{dataset_dependency},
## $ctx->{check_custom_function_id}, $ctx->{check_custom_functions},
## $ctx->{action_custom_function_id}, $ctx->{action_custom_functions},
## $ctx->{max_flow_var_id}, $ctx->{game_config}, $ctx->{syntax} and the per-dataset
## C emit accumulator $ctx->{c_dataset_lines}.  add_build_feature is imported
## from RAGE::Datagen::BuildFeatures; Compare comes from Data::Compare (the rule
## deduplication primitive).  The $check_data_output_format /
## $action_data_output_format struct-initializer tables, used only by the
## emitters here, are module-private lexicals (moved verbatim).  Behaviour (and
## emitted bytes — including rule dedup ordering) is unchanged.
##
## Exported: find_existing_rule_index, validate_and_compile_rule (parse-time),
## generate_flow_rules, generate_game_events_rule_table (emit-time).
## generate_rule_checks and generate_rule_actions are internal helpers.
##
################################################################################

use strict;
use warnings;
use utf8;

use Data::Compare;
use RAGE::Datagen::BuildFeatures qw( add_build_feature );

use Exporter 'import';
our @EXPORT_OK = qw(
    find_existing_rule_index validate_and_compile_rule
    generate_flow_rules generate_game_events_rule_table
);

sub find_existing_rule_index {
    my $ctx = shift;
    my $rule = shift;
    foreach my $i ( 0 .. ( scalar( @{ $ctx->{all_rules} } ) - 1 ) ) {
        return $i if Compare( $rule, $ctx->{all_rules}[ $i ] );
    }
    return undef;
}

sub validate_and_compile_rule {
    my $ctx = shift;
    my $rule = shift;

    # validate rule
    defined( $rule->{'screen'} ) or
        die "Rule has no SCREEN\n";
    my $screen = $rule->{'screen'};
    if ( $screen ne '__EVENTS__' ) {
        exists( $ctx->{screen_name_to_index}{ $screen } ) or
            die "Screen '$screen' is not defined\n";
    }

    # WHEN clause is optional when the rule is assigned to __EVENTS__
    if ( $rule->{'screen'} ne '__EVENTS__' ) {
        defined( $rule->{'when'} ) or
            die "Rule has no WHEN clause\n";
        my $when = $rule->{'when'};
        grep { $when eq $_ } @{ $ctx->{syntax}->{'valid_whens'} } or
            die "WHEN must be one of ".join( ", ", map { uc } @{ $ctx->{syntax}->{'valid_whens'} } )."\n";
    }

    # we explictly allow rules with no checks, which are run always
#    defined( $rule->{'check'} ) and scalar( @{ $rule->{'check'} } ) or
#        die "At least one CHECK clause must be specified\n";

    defined( $rule->{'do'} ) and scalar( @{ $rule->{'do'} } ) or
        die "At least one DO clause must be specified\n";

    # do any special filtering of values

    # check filtering
    foreach my $chk ( @{ $rule->{'check'} } ) {
        $chk =~ m/^(\w+)\s*(.*)$/;
        my ( $check, $check_data ) = ( $1, $2 );

        # hotzone filtering
        if ( $check =~ /^HERO_OVER_HOTZONE$/ ) {
            $check_data = $ctx->{all_screens}[ $ctx->{screen_name_to_index}{ $rule->{'screen'} } ]{'hotzone_name_to_index'}{ $check_data };
        }

        # check custom function filtering
        if ( $check =~ /^CALL_CUSTOM_FUNCTION/ ) {
            my $vars = {
                map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                split( /\s+/, $check_data )
            };
            defined( $vars->{'name'} ) or
                die "CALL_CUSTOM_FUNCTION: NAME parameter is mandatory\n";
            my $index;
            if ( defined( $ctx->{check_custom_function_id}{ $vars->{'name'} } ) ) {
                $index = $ctx->{check_custom_function_id}{ $vars->{'name'} };
            } else {
                $index = scalar( @{ $ctx->{check_custom_functions} } );
                $ctx->{check_custom_function_id}{ $vars->{'name'} } = $index;
                push @{ $ctx->{check_custom_functions} }, {
                    index		=> $index,
                    function		=> $vars->{'name'},
                    uses_param		=> ( defined( $vars->{'param'} ) ? 1 : 0 ),
                };
            }
            $check_data = sprintf( "{ .function_id = %d, .param = %s }", $index, $vars->{'param'} || 0 );
        }

        # flow_vars specifics
        if ( $check =~ /^FLOW_VAR/ ) {
            my $vars = {
                map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                split( /\s+/, $check_data )
            };
            if ( not defined( $ctx->{max_flow_var_id} ) or ( $vars->{'var_id'} > $ctx->{max_flow_var_id} ) ) {
                $ctx->{max_flow_var_id} = $vars->{'var_id'};
            }
            $check_data = sprintf( "{ .var_id = %s, .value = %s }",
                $vars->{'var_id'}, $vars->{'value'} );
            add_build_feature( $ctx, 'FLOW_VARS' );
        }

        # game_time specifics
        if ( $check =~ /^GAME_TIME_/ ) {
            add_build_feature( $ctx, 'GAME_TIME' );
        }

        # regenerate the check with filtered data
        $chk = sprintf( "%s\t%s", $check, $check_data );
    }

    # action filtering
    foreach my $do ( @{ $rule->{'do'} } ) {
        $do =~ m/^(\w+)\s*(.*)$/;
        my ( $action, $action_data ) = ( $1, $2 );

        # hotzone filtering
        if ( $action =~ /^(ENABLE|DISABLE)_HOTZONE$/ ) {
            $action_data = $ctx->{all_screens}[ $ctx->{screen_name_to_index}{ $rule->{'screen'} } ]{'hotzone_name_to_index'}{ $action_data };
        }

        # warp_to_screen filtering
        if ( $action =~ /^WARP_TO_SCREEN$/ ) {
            my $vars = {
                map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                split( /\s+/, $action_data )
            };
            my @flag_list;
            if ( not defined( $vars->{'dest_hero_x'} ) ) {
                push @flag_list, 'ACTION_WARP_TO_SCREEN_KEEP_HERO_X';
            }
            if ( not defined( $vars->{'dest_hero_y'} ) ) {
                push @flag_list, 'ACTION_WARP_TO_SCREEN_KEEP_HERO_Y';
            }
            my $flags = ( scalar( @flag_list ) ? join( " | ", @flag_list ) : 0 );
            $action_data = sprintf( "{ .num_screen = %d, .hero_x = %d, .hero_y = %d, .flags = %s }",
                $ctx->{screen_name_to_index}{ $vars->{'dest_screen'} },
                ( $vars->{'dest_hero_x'} || 0 ), ( $vars->{'dest_hero_y'} || 0 ),
                $flags,
            );
        }

        # btile filtering
        if ( $action =~ /^(ENABLE|DISABLE)_BTILE$/ ) {
            $action_data = $ctx->{all_screens}[ $ctx->{screen_name_to_index}{ $rule->{'screen'} } ]{'btile_name_to_index'}{ $action_data };
        }

        # enemy filtering
        if ( $action =~ /^(ENABLE|DISABLE)_ENEMY$/ ) {
            $action_data = $ctx->{all_screens}[ $ctx->{screen_name_to_index}{ $rule->{'screen'} } ]{'enemy_name_to_index'}{ $action_data };
        }

        # set/reset screen flag filtering
        if ( $action =~ /^(SET|RESET)_SCREEN_FLAG$/ ) {
            my $vars = {
                map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                split( /\s+/, $action_data )
            };
            $action_data = sprintf( "{ .num_screen = %d, .flag = %s }",
                $ctx->{screen_name_to_index}{ $vars->{'screen'} },
                ( $vars->{'flag'} || 0 ),
            );
        }

        # custom action function filtering
        if ( $action =~ /^CALL_CUSTOM_FUNCTION/ ) {
            my $vars = {
                map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                split( /\s+/, $action_data )
            };
            defined( $vars->{'name'} ) or
                die "CALL_CUSTOM_FUNCTION: NAME parameter is mandatory\n";
            my $index;
            if ( defined( $ctx->{action_custom_function_id}{ $vars->{'name'} } ) ) {
                $index = $ctx->{action_custom_function_id}{ $vars->{'name'} };
            } else {
                $index = scalar( @{ $ctx->{action_custom_functions} } );
                $ctx->{action_custom_function_id}{ $vars->{'name'} } = $index;
                push @{ $ctx->{action_custom_functions} }, {
                    index		=> $index,
                    function		=> $vars->{'name'},
                    uses_param		=> ( defined( $vars->{'param'} ) ? 1 : 0 ),
                };
            }
            $action_data = sprintf( "{ .function_id = %d, .param = %s }", $index, $vars->{'param'} || 0 );
        }

        # flow_vars specifics
        if ( $action =~ /^FLOW_VAR/ ) {
            my $vars = {
                map { my ($k,$v) = split( /=/, $_ ); lc($k), $v }
                split( /\s+/, $action_data )
            };
            if ( not defined( $ctx->{max_flow_var_id} ) or ( $vars->{'var_id'} > $ctx->{max_flow_var_id} ) ) {
                $ctx->{max_flow_var_id} = $vars->{'var_id'};
            }
            $action_data = sprintf( "{ .var_id = %s, .value = %s }",
                $vars->{'var_id'}, $vars->{'value'} || 0 );
            add_build_feature( $ctx, 'FLOW_VARS' );
        }

        # tracker_select_song specific
        if ( $action =~ /^TRACKER_SELECT_SONG/ ) {
            # $action_data may contain the song name - convert into the song
            # index into the songs table
            if ( defined( $ctx->{game_config}->{'tracker'}{'song_index'}{ $action_data } ) ) {
                $action_data = $ctx->{game_config}->{'tracker'}{'song_index'}{ $action_data };
            }
        }

        # regenerate the value with the filtered data
        $do = sprintf( "%s\t%s", $action, $action_data );
    }

    # generate conditional build features for this rule: checks and actions
    foreach my $chk ( @{ $rule->{'check'} } ) {
        my ( $check, $check_data ) = split( /\s+/, $chk );
        my $id = sprintf( 'FLOW_RULE_CHECK_%s', uc( $check ) );
        add_build_feature( $ctx, $id );
    }
    foreach my $do ( @{ $rule->{'do'} } ) {
        $do =~ m/^(\w+)\s*(.*)$/;
        my ( $action, $action_data ) = ( $1, $2 );
        my $id = sprintf( 'FLOW_RULE_ACTION_%s', uc( $action ) );
        add_build_feature( $ctx, $id );
    }

    1;
}

# struct initializer formats depending on the check and action names
my $check_data_output_format = {
    GAME_FLAG_IS_SET		=> ".data.flag_state.flag = %s",
    GAME_FLAG_IS_RESET		=> ".data.flag_state.flag = %s",
    LOOP_FLAG_IS_SET		=> ".data.flag_state.flag = %s",
    LOOP_FLAG_IS_RESET		=> ".data.flag_state.flag = %s",
    USER_FLAG_IS_SET		=> ".data.flag_state.flag = %s",
    USER_FLAG_IS_RESET		=> ".data.flag_state.flag = %s",
    LIVES_EQUAL			=> ".data.lives.count = %d",
    LIVES_MORE_THAN		=> ".data.lives.count = %d",
    LIVES_LESS_THAN		=> ".data.lives.count = %d",
    ENEMIES_ALIVE_EQUAL		=> ".data.enemies.count = %d",
    ENEMIES_ALIVE_MORE_THAN	=> ".data.enemies.count = %d",
    ENEMIES_ALIVE_LESS_THAN	=> ".data.enemies.count = %d",
    ENEMIES_KILLED_EQUAL	=> ".data.enemies.count = %d",
    ENEMIES_KILLED_MORE_THAN	=> ".data.enemies.count = %d",
    ENEMIES_KILLED_LESS_THAN	=> ".data.enemies.count = %d",
    CALL_CUSTOM_FUNCTION	=> ".data.custom = %s",
    ITEM_IS_OWNED		=> ".data.item.item_id = %s",
    HERO_OVER_HOTZONE		=> ".data.hotzone.num_hotzone = %s",
    SCREEN_FLAG_IS_SET		=> ".data.flag_state.flag = %s",
    SCREEN_FLAG_IS_RESET	=> ".data.flag_state.flag = %s",
    FLOW_VAR_EQUAL		=> ".data.flow_var = %s",
    FLOW_VAR_MORE_THAN		=> ".data.flow_var = %s",
    FLOW_VAR_LESS_THAN		=> ".data.flow_var = %s",
    GAME_TIME_EQUAL		=> ".data.game_time.seconds = %s",
    GAME_TIME_MORE_THAN		=> ".data.game_time.seconds = %s",
    GAME_TIME_LESS_THAN		=> ".data.game_time.seconds = %s",
    GAME_EVENT_HAPPENED		=> ".data.game_event.event = %s",
    ITEM_IS_NOT_OWNED		=> ".data.item.item_id = %s",
};

my $action_data_output_format = {
    SET_USER_FLAG		=> ".data.user_flag.flag = %s",
    RESET_USER_FLAG		=> ".data.user_flag.flag = %s",
    INC_LIVES			=> ".data.lives.count = %s",
    PLAY_SOUND			=> ".data.play_sound.sound_id = %s",
    CALL_CUSTOM_FUNCTION	=> ".data.custom = %s",
    END_OF_GAME			=> ".data.unused = %d",
    WARP_TO_SCREEN		=> ".data.warp_to_screen = %s",
    ENABLE_HOTZONE		=> ".data.hotzone.num_hotzone = %d",
    DISABLE_HOTZONE		=> ".data.hotzone.num_hotzone = %d",
    ENABLE_BTILE		=> ".data.btile.num_btile = %d",
    DISABLE_BTILE		=> ".data.btile.num_btile = %d",
    ADD_TO_INVENTORY		=> ".data.item.item_id = %s",
    REMOVE_FROM_INVENTORY	=> ".data.item.item_id = %s",
    SET_SCREEN_FLAG		=> ".data.screen_flag = %s",
    RESET_SCREEN_FLAG		=> ".data.screen_flag = %s",
    FLOW_VAR_STORE		=> ".data.flow_var = %s",
    FLOW_VAR_INC		=> ".data.flow_var = %s",
    FLOW_VAR_ADD		=> ".data.flow_var = %s",
    FLOW_VAR_DEC		=> ".data.flow_var = %s",
    FLOW_VAR_SUB		=> ".data.flow_var = %s",
    TRACKER_SELECT_SONG		=> ".data.tracker_song.num_song = %s",
    TRACKER_MUSIC_STOP		=> ".data.unused = %d",
    TRACKER_MUSIC_START		=> ".data.unused = %d",
    TRACKER_PLAY_FX		=> ".data.tracker_fx.num_effect = %d",
    HERO_ENABLE_WEAPON		=> ".data.unused = %d",
    HERO_DISABLE_WEAPON		=> ".data.unused = %d",
    ENABLE_ENEMY		=> ".data.enemy.num_enemy = %d",
    DISABLE_ENEMY		=> ".data.enemy.num_enemy = %d",
};

sub generate_rule_checks {
    my ( $ctx, $rule, $index ) = @_;
    my $num_checks = scalar( @{ $rule->{'check'} } );

    return if ( not scalar( @{ $rule->{'check'} } ) );

    my $output = sprintf( "struct flow_rule_check_s flow_rule_checks_%05d[%d] = {\n",
        $index, $num_checks );
    foreach my $ch ( @{ $rule->{'check'} } ) {
        $ch =~ m/^(\w+)\s*(.*)$/;
        my ( $check, $check_data ) = ( $1, $2 );
        $output .= sprintf( "\t{ .type = RULE_CHECK_%s, %s },\n",
            $check,
            sprintf( $check_data_output_format->{ $check }, $check_data || 0 )
        );
    }
    $output .= "};\n\n";
    return $output;
}

sub generate_rule_actions {
    my ( $ctx, $rule, $index ) = @_;
    my $num_actions = scalar( @{ $rule->{'do'} } );
    my $output = sprintf( "struct flow_rule_action_s flow_rule_actions_%05d[%d] = {\n",
        $index, $num_actions );
    foreach my $ac ( @{ $rule->{'do'} } ) {
        $ac =~ m/^(\w+)\s*(.*)$/;
        my ( $action, $action_data ) = ( $1, $2 );
        $output .= sprintf( "\t{ .type = RULE_ACTION_%s, %s },\n",
            $action,
            sprintf( $action_data_output_format->{ $action }, $action_data || 0 )
        );
    }
    $output .= "};\n\n";
    return $output;
}

sub generate_flow_rules {
    my $ctx = shift;
    my $dataset = shift;

    # generate the list of dataset rules, return immediately if empty
    my @dataset_rules = map { $ctx->{all_rules}[ $_ ] } @{ $ctx->{dataset_dependency}{ $dataset }{'rules'} };
    return if not scalar( @dataset_rules );

    # file header comments
    push @{ $ctx->{c_dataset_lines}->{ $dataset } }, <<FLOW_DATA_C_1

///////////////////////////////////////////////////////////
//
// Flow data
//
///////////////////////////////////////////////////////////

FLOW_DATA_C_1
;

    # output check and action tables for each rule
    push @{ $ctx->{c_dataset_lines}->{ $dataset } }, sprintf( "// check tables for all dataset rules\n" );
    foreach my $i ( 0 .. scalar( @dataset_rules )-1 ) {
        push @{ $ctx->{c_dataset_lines}->{ $dataset } }, generate_rule_checks( $ctx, $dataset_rules[ $i ], $i );
    }
    push @{ $ctx->{c_dataset_lines}->{ $dataset } }, sprintf( "// action tables for all dataset rules\n" );
    foreach my $i ( 0 .. scalar( @dataset_rules )-1 ) {
        push @{ $ctx->{c_dataset_lines}->{ $dataset } }, generate_rule_actions( $ctx, $dataset_rules[ $i ], $i );
    }

    # output dataset rule table
    if ( scalar( @dataset_rules ) ) {
        push @{ $ctx->{c_dataset_lines}->{ $dataset } }, sprintf(  "// Dataset %s rule table\n\n#define FLOW_NUM_RULES\t%d\n",
            $dataset, scalar( @dataset_rules ) );
        push @{ $ctx->{c_dataset_lines}->{ $dataset } }, "struct flow_rule_s all_flow_rules[ FLOW_NUM_RULES ] = {\n";
        foreach my $i ( 0 .. scalar( @dataset_rules )-1 ) {
            push @{ $ctx->{c_dataset_lines}->{ $dataset } }, "\t{";
            push @{ $ctx->{c_dataset_lines}->{ $dataset } }, sprintf( " .num_checks = %d, .checks = %s,",
                scalar( @{ $dataset_rules[ $i ]{'check'} } ),
                ( scalar( @{ $dataset_rules[ $i ]{'check'} } ) ? sprintf( "&flow_rule_checks_%05d[0]", $i ) : 'NULL' )
            );
            push @{ $ctx->{c_dataset_lines}->{ $dataset } }, sprintf( " .num_actions = %d, .actions = &flow_rule_actions_%05d[0],",
                scalar( @{ $dataset_rules[ $i ]{'do'} } ), $i );
            push @{ $ctx->{c_dataset_lines}->{ $dataset } }, " },\n";
        }
        push @{ $ctx->{c_dataset_lines}->{ $dataset } }, "\n};\n\n";
    }
}

# generates the game_events_rule_table
sub generate_game_events_rule_table {
    my $ctx = shift;
    # rule checks and actions have been already generated in the home dataset
    # together with the other datasets. We just output the rule pointers here,
    # as it is already done when generating the rules for each screen

    my $rule_global_to_dataset_index = $ctx->{dataset_dependency}{ 'home' }{'rule_global_to_dataset_index'};

    # flow rules
    push @{ $ctx->{c_dataset_lines}->{ 'home' } }, sprintf( "// Game Events rule table\n" );
    my $num_rules = scalar( @{ $ctx->{game_events_rule_table} } );
    if ( $num_rules ) {
        push @{ $ctx->{c_dataset_lines}->{ 'home' } }, sprintf( "struct flow_rule_s *game_events_rule_table_rules[ %d ] = {\n\t",
            $num_rules );
        push @{ $ctx->{c_dataset_lines}->{ 'home' } }, join( ",\n\t",
            map {
                sprintf( "&all_flow_rules[ %d ]", $rule_global_to_dataset_index->{ $_ } )
            } @{ $ctx->{game_events_rule_table} }
        );
        push @{ $ctx->{c_dataset_lines}->{ 'home' } }, "\n};\n";
        push @{ $ctx->{c_dataset_lines}->{ 'home' } },
            "struct flow_rule_table_s game_events_rule_table = {\n",
            "\t.num_rules = $num_rules,\n",
            "\t.rules = &game_events_rule_table_rules[0]\n",
            "};\n\n";

    } else {
        push @{ $ctx->{c_dataset_lines}->{ 'home' } }, sprintf( "// Game Events rule table has no rules defined\n" );
        push @{ $ctx->{c_dataset_lines}->{ 'home' } },
            "struct flow_rule_table_s game_events_rule_table = { 0, NULL };\n\n";
    }
}

1;

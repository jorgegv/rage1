#!/usr/bin/perl

################################################################################
##
## RAGE1 - Retro Adventure Game Engine, release 1
## (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
## 
## This code is published under a GNU GPL license version 3 or later.  See
## LICENSE file in the distribution for details.
## 
################################################################################

use warnings;
use strict;
use utf8;

use Data::Dumper;
use Getopt::Std;
use Data::Compare;

my $c_file = 'flow_data.c';
my $h_file = 'flow_data.h';
my $output_fh;

# internal state variables

# all rules (CHECK-DO pairs)
# this table will contain unique rules
my @all_rules;

# data which contains rules for each screen and section (enter_screen,
# exit_screen, game_loop, etc.) as indexes into the main @all _rules table
#
# e.g. $screen_rules->{'Screen01'}{enter_screen} = [ 0, 2, 7 ]
my $screen_rules;

# dump file for internal state
my $dump_file = 'internal_state.dmp';

# this variable must be named like this.  Internal state dumping/loading
# depends on its name!
my $all_state;

sub load_internal_state {
    open my $fh, "<", $dump_file or
        die "Could not open $dump_file for reading\n";
    local $/ = undef;
    my $dump = <$fh>;
    close $fh;
    eval $dump;
}

######################################################
## Configuration syntax definitions and lists
######################################################

my $syntax = {
    valid_whens => [ 'enter_screen', 'exit_screen', 'game_loop' ],
};

##########################################
## Input data parsing and state machine
##########################################

sub read_input_data {
    # possible states: NONE, RULE
    # initial state
    my $state = 'NONE';
    my $cur_rule = undef;

    # read and process input
    my $num_line = 0;
    while (my $line = <>) {

        $num_line++;

        # cleanup the line
        chomp $line;
        $line =~ s/^\s*//g;		# remove leading blanks
        $line =~ s/\s*$//g;		# remove trailing blanks
        $line =~ s/\/\/.*$//g;		# remove comments (//...)
        next if $line eq '';		# ignore blank lines

        # process the line
        if ( $state eq 'NONE' ) {
            if ( $line =~ /^BEGIN_RULE$/ ) {
                $state = 'RULE';
                next;
            }
            die "Syntax error:line $num_line: '$line' not recognized (global section)\n";

        } elsif ( $state eq 'RULE' ) {

            if ( $line =~ /^SCREEN\s+(\w+)$/ ) {
                $cur_rule->{'screen'} = $1;
                next;
            }
            if ( $line =~ /^WHEN\s+(\w+)$/ ) {
                $cur_rule->{'when'} = lc( $1 );
                next;
            }
            if ( $line =~ /^CHECK\s+(.+)$/ ) {
                push @{$cur_rule->{'check'}}, $1;
                next;
            }
            if ( $line =~ /^DO\s+(.+)$/ ) {
                push @{$cur_rule->{'do'}}, $1;
                next;
            }
            if ( $line =~ /^END_RULE$/ ) {
                # validate rule before deduplicating it
                validate_rule( $cur_rule );

                # we must delete WHEN and SCREEN for deduplicating rules,
                # bt we must keep them for properly storing the rule
                my $when = $cur_rule->{'when'};
                delete $cur_rule->{'when'};
                my $screen = $cur_rule->{'screen'};
                delete $cur_rule->{'screen'};

                # find an identical rule if it exists
                my $found = find_existing_rule_index( $cur_rule );
                my $index;
                # use it if found, otherwise add the new one to the global rule list
                if ( defined( $found ) ) {
                    $index = $found;
                } else {
                    $index = scalar( @all_rules );
                    push @all_rules, $cur_rule;
                }

                # add the rule index to the proper screen rule table
                push @{ $screen_rules->{ $screen }{ $when } }, $index;

                # clean up for next rule
                $cur_rule = undef;
                $state = 'NONE';
                next;
            }
            die "Syntax error:line $num_line: '$line' not recognized (RULE section)\n";

        } else {
            die "Unknown state '$state'\n";
        }
    }
}

sub find_existing_rule_index {
    my $rule = shift;
    foreach my $i ( 0 .. ( scalar( @all_rules ) - 1 ) ) {
        return $i if Compare( $rule, $all_rules[ $i ] );
    }
    return undef;
}


sub validate_rule {
    my $rule = shift;

    defined( $rule->{'screen'} ) or
        die "Rule has no SCREEN\n";
    my $screen = $rule->{'screen'};
    exists( $all_state->{'screen_name_to_index'}{ $screen } ) or
        die "Screen '$screen' is not defined\n";

    defined( $rule->{'when'} ) or
        die "Rule has no WHEN clause\n";
    my $when = $rule->{'when'};
    grep { $when eq $_ } @{ $syntax->{'valid_whens'} } or
        die "WHEN must be one of ".join( ", ", map { uc } @{ $syntax->{'valid_whens'} } )."\n";

    defined( $rule->{'check'} ) and scalar( @{ $rule->{'check'} } ) or
        die "At least one CHECK clause must be specified\n";

    defined( $rule->{'do'} ) and scalar( @{ $rule->{'do'} } ) or
        die "At least one DO clause must be specified\n";

    1;
}

# struct initializer formats depending on the check and action names
my $check_data_output_format = {
    GAME_FLAG_IS_SET		=> ".check_data.flag_state.flag = %s",
    GAME_FLAG_IS_RESET		=> ".check_data.flag_state.flag = %s",
    LOOP_FLAG_IS_SET		=> ".check_data.flag_state.flag = %s",
    LOOP_FLAG_IS_RESET		=> ".check_data.flag_state.flag = %s",
    USER_FLAG_IS_SET		=> ".check_data.flag_state.flag = %s",
    USER_FLAG_IS_RESET		=> ".check_data.flag_state.flag = %s",
    LIVES_EQUAL			=> ".check_data.lives.count = %d",
    LIVES_MORE_THAN		=> ".check_data.lives.count = %d",
    LIVES_LESS_THAN		=> ".check_data.lives.count = %d",
    ENEMIES_ALIVE_EQUAL		=> ".check_data.enemies.count = %d",
    ENEMIES_ALIVE_MORE_THAN	=> ".check_data.enemies.count = %d",
    ENEMIES_ALIVE_LESS_THAN	=> ".check_data.enemies.count = %d",
    ENEMIES_KILLED_EQUAL	=> ".check_data.enemies.count = %d",
    ENEMIES_KILLED_MORE_THAN	=> ".check_data.enemies.count = %d",
    ENEMIES_KILLED_LESS_THAN	=> ".check_data.enemies.count = %d",
    CALL_CUSTOM_FUNCTION	=> ".check_data.custom.function = %s",
    ITEM_IS_OWNED		=> ".check_data.item.item_id = %s",
};

my $action_data_output_format = {
    SET_USER_FLAG		=> ".action_data.user_flag.flag = %s",
    RESET_USER_FLAG		=> ".action_data.user_flag.flag = %s",
    INC_LIVES			=> ".action_data.lives.count = %s",
    PLAY_SOUND			=> ".action_data.play_sound.sound_id = %s",
    CALL_CUSTOM_FUNCTION	=> ".action_data.custom.function = %s",
};

sub output_rule {
    my $rule = shift;
    my ( $check, $check_data ) = split( /\s+/, $rule->{'check'}[0] );
    my ( $action, $action_data ) = split( /\s+/, $rule->{'do'}[0] );
    return sprintf( "\t{\n\t.check = RULE_CHECK_%s,\n\t%s,\n\t.action = RULE_ACTION_%s,\n\t%s\n\t}",
            $check,
            sprintf( $check_data_output_format->{ $check }, $check_data ),
            $action,
            sprintf( $action_data_output_format->{ $action }, $action_data )
    );
}

#############################
## General Output Functions
#############################

sub output_h_file {
    # output .h file
    open( $output_fh, ">", $h_file ) or
        die "Could not open $h_file for writing\n";

    print $output_fh <<FLOW_DATA_H_1
#ifndef _FLOW_DATA_H
#define _FLOW_DATA_H

#include "flow.h"

// FLOWGEN initialization function, called from main game initialization
void init_flowgen(void);

// global rule table
extern struct flow_rule_s flow_all_rules[];

FLOW_DATA_H_1
;

    print $output_fh "\n#endif // _FLOW_DATA_H\n";

    close $output_fh;
}

sub output_c_file {
    # output .c file
    open( $output_fh, ">", $c_file ) or
        die "Could not open $c_file for writing\n";

    # file header comments
    print $output_fh <<FLOW_DATA_C_1
///////////////////////////////////////////////////////////
//
// Flow data - automatically generated with flowgen.pl
//
///////////////////////////////////////////////////////////

#include "flow.h"
#include "flow_data.h"
#include "game_state.h"
#include "map.h"

FLOW_DATA_C_1
;

    # output global rule table
    printf $output_fh "// global rule table\n\n#define FLOW_NUM_RULES\t%d\n",
        scalar( @all_rules );
    print $output_fh "struct flow_rule_s flow_all_rules[ FLOW_NUM_RULES ] = {\n";
    print $output_fh join( ",\n", map { output_rule( $_ ) } @all_rules );
    print $output_fh "\n};\n\n";

    # output rule tables for each screen
    print $output_fh "// rule tables for each screen\n";
    foreach my $screen (sort keys %$screen_rules ) {
        printf $output_fh "\n// rules for screen '%s'\n", $screen;
        foreach my $table ( @{ $syntax->{'valid_whens'} } ) {
            if ( defined( $screen_rules->{ $screen } ) and defined( $screen_rules->{ $screen }{ $table } ) ) {
                my $num_rules = scalar( @{ $screen_rules->{ $screen }{ $table } } );
                if ( $num_rules ) {
                    printf $output_fh "\n// screen '%s', table '%s' (%d rules)\n",
                        $screen, $table, $num_rules;
                    printf $output_fh "struct flow_rule_s *screen_%s_%s_rules[ %d ] = {\n\t",
                        $screen, $table, $num_rules;
                    print $output_fh join( ",\n\t",
                        map { 
                            sprintf "&flow_all_rules[ %d ]", $_
                        } @{ $screen_rules->{ $screen }{ $table } }
                    );
                    print $output_fh "\n};\n";
                }
            }
        }
    }

    # output initialization code to set the table pointers for each screen
    # that has rules in any table
    print $output_fh <<FLOW_DATA_C_2

void init_flowgen(void) {
FLOW_DATA_C_2
;
    foreach my $screen (sort keys %$screen_rules ) {
        foreach my $table ( @{ $syntax->{'valid_whens'} } ) {
            if ( defined( $screen_rules->{ $screen } ) and defined( $screen_rules->{ $screen }{ $table } ) ) {
                my $num_rules = scalar( @{ $screen_rules->{ $screen }{ $table } } );
                if ( $num_rules ) {
                    printf $output_fh "\t// screen '%s', table '%s' (%d rules)\n",
                        $screen, $table, $num_rules;
                    printf $output_fh "\tmap[ %d ].flow_data.rule_tables.%s.num_rules = %d;\n",
                        $all_state->{'screen_name_to_index'}{ $screen },
                        $table,
                        $num_rules;
                    printf $output_fh "\tmap[ %d ].flow_data.rule_tables.%s.rules = &screen_%s_%s_rules[0];\n",
                        $all_state->{'screen_name_to_index'}{ $screen },
                        $table,
                        $screen,
                        $table;
                }
            }
        }
    }


    print $output_fh <<FLOW_DATA_C_3
}

FLOW_DATA_C_3
;

    close $output_fh;

}

# this function is called from main
sub output_generated_data {
    output_c_file;
    output_h_file;
}

# creates a dump of internal data so that other tools (e.g.  FLOWGEN) can
# load it and use the parsed data. Use "-c" option to dump the internal data
sub dump_internal_data {
    open DUMP, ">$dump_file" or
        die "Could not open $dump_file for writing\n";

    $all_state->{'flowgen'}{'all_rules'} = \@all_rules;
    $all_state->{'flowgen'}{'screen_rules'} = $screen_rules;

    print DUMP Data::Dumper->Dump( [ $all_state ], [ 'all_state' ] );
    close DUMP;
}

#########################
## Main loop
#########################

our ( $opt_d, $opt_c );
getopts("d:c");
if ( defined( $opt_d ) ) {
    $c_file = "$opt_d/$c_file";
    $h_file = "$opt_d/$h_file";
    $dump_file = "$opt_d/$dump_file";
}

# load internal state from previous tools
load_internal_state;

# read, validate and compile input
read_input_data;

# run consistency checks
#run_consistency_checks;

# generate output
output_generated_data;

# dump internal data if required to do so
dump_internal_data
    if ( $opt_c );

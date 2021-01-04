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

// FLOWGEN initialization function, called from main game initialization
void init_flowgen(void);

FLOW_DATA_H_1
;

    print $output_fh "\n#endif // _FLOW_DATA_H\n";

    close $output_fh;
}

sub output_c_file {
    # output .c file
    open( $output_fh, ">", $c_file ) or
        die "Could not open $c_file for writing\n";

    print $output_fh <<FLOW_DATA_C_1
///////////////////////////////////////////////////////////
//
// Flow data - automatically generated with flowgen.pl
//
///////////////////////////////////////////////////////////

FLOW_DATA_C_1
;

    print $output_fh <<FLOW_DATA_C_2
void init_flowgen(void) {
FLOW_DATA_C_2
;

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

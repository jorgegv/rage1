#!/usr/bin/env perl

# This script checks that all functions living under banked_code directories
# have been successfully defined: correct ID, correct function type
# definition, correct function call macro and inclusion in the function
# index for that bank (00main.asm)

# We assume that for defining a new banked function, the origin point is to
# assign a new ID in memory.h.  We then check the next steps that should
# have been done after that.  We use the ID list as the source of truth for
# the function definitions.

use strict;
use warnings;
use utf8;

use FindBin qw( $Bin );
use lib "$Bin/../lib";

require RAGE::Config;

use Data::Dumper;

my $cfg = rage1_get_config();

my $memory_h	= $cfg->{'build'}{'banked_functions'}{'c_macros_filename'};
my $main_asm	= $cfg->{'build'}{'banked_functions'}{'asm_table_filename'};

sub get_file_lines {
    my $f = shift;
    open F, $f or
        die "Could not open $f for reading\n";
    my @lines = <F>;
    chomp( @lines );
    return @lines;
}

print "Checking banked code definitions...\n";

##
## first, load files in memory
##

my @memory_h_lines = get_file_lines( $memory_h );
my @main_asm_lines = get_file_lines( $main_asm );

##
## build data tables
##

# build table of functions and IDs
my %function_id = map {
    if ( /^\s*#define\s+(BANKED_FUNCTION_\w+)\s+(\d+)$/ ) {
        ( $1, $2 );
    } else {
        ();
    }
} @memory_h_lines;

# build table of call macros
my %function_info = map {
    if ( /^\s*#define\s+(\w+)\((.*)\)\s+\(\s+(memory_call_banked_function\w*)\s*\(\s+(BANKED_FUNCTION_\w+).*$/ ) {
        my ( $call_macro, $args, $function_call, $function_id ) = ( $1, $2, $3, $4 );
        ( $function_id, { 'call_macro' => $call_macro, 'args' => $args, 'function_call' => $function_call, 'asm_function' => '_' . $call_macro } );
    } else {
        ();
    }
} @memory_h_lines;

# build table of asm extern declarations
my %asm_extern = map {
    if ( /^\s*extern\s+(\w+)$/ ) {
        ( $1, 1 );
    } else {
        ();
    }
} @main_asm_lines;

# build table of asm function declaration and indexes
my $counter = 0;
my %asm_function_table = map {
    if ( /^\s+dw\s+(\w+)\s*;+\s*index\s+(\d+).*$/ ) {
        my ( $function, $comment_index ) = ( $1, $2 );
        ( $1, { 'index' => $counter++, 'comment_index' => $comment_index } );
    } else {
        ();
    }
} @main_asm_lines;

#print Dumper( \%function_id );
#print Dumper( \%function_info );
#print Dumper( \%asm_extern );
#print Dumper( \%asm_function_table );

my @functions = sort { $function_id{ $a } <=> $function_id{ $b } } grep { $_ ne 'BANKED_FUNCTION_MAX_ID' } keys %function_id;

##
## then, run consistency checks and report failures
##

my $errors = 0;

# ensure all data structs have info about the same number of functions
my %sizes;
my $num_functions = scalar( @functions );
my $num_info = scalar( keys %function_info );
my $num_extern = scalar( keys %asm_extern );
my $num_asm_table = scalar( keys %asm_function_table );

$sizes{ $num_functions }++;
$sizes{ $num_info }++;
$sizes{ $num_extern }++;
$sizes{ $num_asm_table }++;

if ( scalar( keys %sizes ) != 1 ) {
    warn sprintf( "** All tables should have the same number of elements (%d)\n", $num_functions );
    warn sprintf( "**   IDs: %d elements\n", $num_functions );
    warn sprintf( "**   Call Macros: %d elements\n", $num_info );
    warn sprintf( "**   Externs: %d elements\n", $num_extern );
    warn sprintf( "**   ASM Table: %d elements\n", $num_asm_table );
    $errors++;
}

# ensure BANKED_FUNCTION_MAX_ID is defined correctly
if ( $function_id{ 'BANKED_FUNCTION_MAX_ID' } != $num_functions - 1 ) {
    warn sprintf( "** BANKED_FUNCTION_MAX_ID is %d but should be %d\n",
        $function_id{ 'BANKED_FUNCTION_MAX_ID' }, $num_functions - 1 );
    $errors++;
}

# run checks
foreach my $fun ( @functions ) {

    # ensure that all function IDs have a matching function call macro
    if ( not defined( $function_info{ $fun } ) ) {
        warn "** C Macro: function $fun with ID=$function_id{$fun} has no matching function call macro\n";
        $errors++;
        next;
    }

    my $f = $function_info{ $fun };

    # ensure that all functions are declared as extern in asm file
    if ( not defined( $asm_extern{ $f->{'asm_function'} } ) ) {
        warn "** ASM Table: function $fun with ID=$function_id{$fun} is not declared as extern\n";
        $errors++;
    }

    # ensure that all functions exist in the function table in asm file
    if ( not defined( $asm_function_table{ $f->{'asm_function'} } ) ) {
        warn "** ASM Table: function $fun with ID=$function_id{$fun} is not included in function table\n";
        $errors++;
        next;
    }

    # ensure that function order in asm file function table matches C ID definition
    if ( $function_id{ $fun } != $asm_function_table{ $f->{'asm_function'} }{'index'} ) {
        warn sprintf( "** ASM Table: function $fun with ID=$function_id{$fun} is incorrectly located at position %d\n",
            $asm_function_table{ $f->{'asm_function'} }{'index'} );
        $errors++;
    }

    # ensure that function order in asm file function table and the ID in the comment match
    if ( $function_id{ $fun } != $asm_function_table{ $f->{'asm_function'} }{'comment_index'} ) {
        warn sprintf( "** ASM Table: function $fun with ID=$function_id{$fun} has incorrect index %d in comment\n",
            $asm_function_table{ $f->{'asm_function'} }{'comment_index'} );
        $errors++;
    }
}

if ( $errors ) {
    die "Some errors were found in banked code definitions\n";
} else {
    print "No errors were found\n";
}


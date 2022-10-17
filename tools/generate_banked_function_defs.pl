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

use FindBin qw( $Bin );
use lib "$Bin/../lib";

require RAGE::Config;
require RAGE::BuildFeatures;

use Data::Dumper;

# get all configs
my $cfg = rage1_get_config();
my %features = ( map { $_ => 1 } rage1_build_features_get_all() );

# file names
my $asm_table = $cfg->{'build'}{'banked_functions'}{'asm_table_filename'};
my $c_macros = $cfg->{'build'}{'banked_functions'}{'c_macros_filename'};

# map of signature args to C typecasts
my %typecast = (
    'a8'	=> 'uint8_t',
    'a16'	=> 'uint16_t',
);

# filter out the functions that need to be generated
my @functions = grep { 
    not defined( $_->{'build_dependency'} ) or
        $features{ $_->{'build_dependency'} } 
    } @{ $cfg->{'banked_functions'} };

#print Dumper( $cfg );
#print Dumper( \%features );

##
## generate ASM file with banked functions table
##
open ASM, ">$asm_table" or
    die "Could not open $asm_table for writing\n";

my $function_index = 0;
print ASM <<ASM1
        section	code_compiler
        org	0xC000
ASM1
;

printf ASM join( '', map { sprintf( "extern  _%s\n", $_->{'name'} ) } @functions );

print ASM <<ASM2
;;
;; 0xC000: banked functions table
;;
public	_all_banked_functions
_all_banked_functions:
ASM2
;

my $index = 0;
foreach my $f ( @functions ) {
    $f->{'index'} = $index++;
    printf ASM "        dw      _%-50s ;; index %d\n", $f->{'name'}, $f->{'index'};
}
my $max_index = $index - 1;

##
## Generate C header file with macro definitions for banked functions
##
open CDEF, ">$c_macros" or
    die "Could not open $c_macros for writing\n";

printf CDEF "#include <stdint.h>\n\n// banked function IDs\n";
print CDEF join( '', map {
        sprintf( "#define %-50s %d\n", 'BANKED_FUNCTION_' . uc( $_->{'name'} ), $_->{'index'} )
    } @functions );

printf CDEF "\n#define %-50s %d\n", 'BANKED_FUNCTION_MAX_ID', $max_index;

printf CDEF "\n// banked function call macros (128K versions)\n";
foreach my $f ( @functions ) {
    if ( defined( $f->{'signature'} ) ) {
        # parse the signature and get the number of params
        my $count = 0;
        my @params = map {
            my $sig = $_;
            $sig =~ /a(\d+)/;
            { 'sig' => $sig, 'index' => $count++ }
        } ( $f->{'signature'} =~ m/(a\d+)/g );

        # params in a,b,c,d... format
        my $params_1 = join( ',', map { chr( 97 + $_->{'index'} ) } @params );
        # params in (a),(b),(c),(d),... format
        my $params_2 = join( ',', map { sprintf( '(%s)(%s)', $typecast{ $_->{'sig'} }, chr( 97 + $_->{'index'} ) ) } @params );
        # macro definition
        my $macro = sprintf( '%s(%s)', $f->{'name'}, $params_1 );

        printf CDEF "#define %-50s ( memory_call_banked_function_%s( BANKED_FUNCTION_%s, %s ) )\n",
            $macro, $f->{'signature'}, uc( $f->{'name'} ), $params_2;
    } else {
        # macro definition
        my $macro = sprintf( '%s()', $f->{'name'} );
        printf CDEF "#define %-50s ( memory_call_banked_function( BANKED_FUNCTION_%s ) )\n",
            $macro, uc( $f->{'name'} );
    }
}

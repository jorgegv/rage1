#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use File::Copy;

my @c_symbols = qw(
	PLY_AKG_INIT
	PLY_AKG_STOP
	PLY_AKG_PLAY
	PLY_AKG_INITSOUNDEFFECTS
	PLY_AKG_PLAYSOUNDEFFECT
);

my @output;

my $input = $ARGV[0];
defined( $input ) or
	die "usage: $0 <pasmo_asm_file>\n";

open SRC, $input or
	die "Could not open $input for reading...\n";

push @output, "section code_compiler\n\n";

my @all_symbols;
while ( my $line = <SRC> ) {
	chomp $line;
	$line =~ s/\r//g;
	$line =~ s/db /defb /g;
	$line =~ s/dw /defw /g;
	$line =~ s/\$\+/+/g;
	if ( $line =~ /^(\w+)$/ ) {
		push @output, "\n$1:\n";
		push @all_symbols, $1;
		next;
	}
	$line =~ s/^\s+/\t/g;
	if ( $line =~ /^(.+)\s+equ\s+(.*)$/ ) {
		push @output, "defc $1 = $2\n";
		next;
	}
	if ( $line =~ /^(\w+)\s+(.*)$/ ) {
		push @output, "$1:\n\t$2\n";
		push @all_symbols, $1;
		next;
	}
	push @output, "$line\n";
}

#print join( "\n", map { "public $_" } sort @all_symbols ), "\n";

# print C symbols
push @output, "\n;;\n;; exported C symbols\n;;\n\n";
push @output, join( "\n", map { 
	sprintf( "defc _%s = %s\npublic _%s\n", lc( $_ ), $_, lc( $_ ) )
	} sort @c_symbols ), "\n";
close SRC;

# output to temporary file
my $output = "/tmp/perltmp.$$";
open DST, ">$output" or
	die "Could not open $output for writing...\n";
print DST @output;
close DST;

# move temporary to original
move $output, $input or
	die "Could not rename $output to $input\n";

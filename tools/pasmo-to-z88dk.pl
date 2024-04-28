#!/usr/bin/perl

use strict;
use warnings;
use utf8;

my @output;

my $input = $ARGV[0];
defined( $input ) or
	die "usage: $0 <pasmo_asm_file>\n";

open SRC, $input or
	die "Could not open $input for reading...\n";

my @all_symbols;
while ( my $line = <SRC> ) {
	chomp $line;

	# remove DOS-style line feeds
	$line =~ s/\r//g;

	# DB -> DEFB
	$line =~ s/db /defb /gi;

	# DW -> DEFW
	$line =~ s/dw /defw /gi;

	# all leading blanks -> 1 tab
	$line =~ s/^\s+/\t/g;

	# add : to all labels which are alone on a single line
	if ( $line =~ /^(\w+)$/ ) {
		push @output, "\n$1:\n";
		push @all_symbols, $1;		# save the symbol
		next;
	}

	# replace $+N with ASMPC defs
	if ( $line =~ /^(\w+)\s+equ\s+\$([\+\-]\d+)/i ) {
		push @output, "defc $1 = ASMPC $2\n";
		push @all_symbols, $1;
		next;
	}

	# replace EQU defs with DEFC
	if ( $line =~ /^(.+)\s+equ\s+(.*)$/i ) {
		push @output, "defc $1 = $2\n";
		push @all_symbols, $1;
		next;
	}

	# add : to all labels with instructions on the same line
	if ( $line =~ /^(\w+)\s+(.*)$/ ) {
		push @output, "$1:\n\t$2\n";
		push @all_symbols, $1;
		next;
	}

	# save processed line
	push @output, "$line\n";
}
close SRC;

print join( "", @output ), "\n";

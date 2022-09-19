#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use File::Copy;

my @publics = qw(
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
	$line =~ s/\$\+//g;
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
close SRC;

#print join( "\n", map { "public $_" } sort @all_symbols ), "\n";

push @output, "\n;;\n;; exported C symbols\n;;\n\n";
push @output, join( "\n", map { 
	"public $_\n"
	} sort @publics ), "\n";


# output to temporary file
my $output = "/tmp/perltmp.$$";
open DST, ">$output" or
	die "Could not open $output for writing...\n";
print DST @output;
close DST;

# move temporary to original
move $output, $input or
	die "Could not rename $output to $input\n";

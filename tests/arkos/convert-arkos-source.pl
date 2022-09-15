#!/usr/bin/perl

use strict;
use warnings;
use utf8;

my @c_symbols = qw(
	PLY_AKG_INIT
	PLY_AKG_STOP
	PLY_AKG_PLAY
	PLY_AKG_INITSOUNDEFFECTS
	PLY_AKG_PLAYSOUNDEFFECT
);

print "section code_compiler\n\n";

my @all_symbols;
while ( my $line = <> ) {
	chomp $line;
	$line =~ s/\r//g;
	$line =~ s/db /defb /g;
	$line =~ s/dw /defw /g;
	$line =~ s/\$\+/+/g;
	if ( $line =~ /^(\w+)$/ ) {
		print "\n$1:\n";
		push @all_symbols, $1;
		next;
	}
	$line =~ s/^\s+/\t/g;
	if ( $line =~ /^(.+)\s+equ\s+(.*)$/ ) {
		print "defc $1 = $2\n";
		next;
	}
	if ( $line =~ /^(\w+)\s+(.*)$/ ) {
		print "$1:\n\t$2\n";
		push @all_symbols, $1;
		next;
	}
	print "$line\n";
}

#print join( "\n", map { "public $_" } sort @all_symbols ), "\n";

# print C symbols
print "\n;;\n;; exported C symbols\n;;\n\n";
print join( "\n", map { 
	sprintf( "defc _%s = %s\npublic _%s\n", lc( $_ ), $_, lc( $_ ) )
	} sort @c_symbols ), "\n";

#!/bin/bash
if [ $# != 1 ]; then
	echo "usage: memmap.sh <file.map>"
	exit 1
fi

MAP="$1"

grep "addr," "$MAP" \
	| perl -ne 'm/^(\w+)\s+=\s\$(\w+)\s*;\s*addr,[\s\w]*,[\s\w]*,[\s\w]*,([\s\w]*),.*/;printf "%-5s %-20s %s\n", $2, $3, $1;' \
	| sort

cut -f1 -d\; "$MAP" \
	| perl -e 'while(<>){($a,$b) = split(/\s*=\s*/); chomp $b; push @l,[$b,$a];};print join("\n", map { sprintf "%s %s",@$_ } sort { $a->[0] cmp $b->[0] } @l );print "\n"' \
	| grep -E '__(code|data|bss)_compiler_(head|size)| CODE ' \
	| sort -k 2 -d \
	| perl -pe 's/^\$(\w+)\s+(.+)/$1   \[@{[sprintf "%6d",hex("0x".$1)]}\] $2/g'

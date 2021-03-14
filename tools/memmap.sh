#/bin/bash

if [ $# != 1 ]; then
	echo "usage: memmap.sh <file.map>"
	exit 1
fi

cut -f1 -d\; < "$1" \
	| perl -e 'while(<>){($a,$b) = split(/\s*=\s*/); chomp $b; push @l,[$b,$a];};print join("\n", map { sprintf "%s %s",@$_ } sort { $a->[0] cmp $b->[0] } @l );print "\n"' \
	| grep -E '__(code|data|bss)_compiler_(head|size)' \
	| sort -k 2 -d \
	| perl -pe 's/^\$(\w+)\s+(.+)/\$$1 \[@{[sprintf "%5d",hex("0x".$1)]}\] $2/g'

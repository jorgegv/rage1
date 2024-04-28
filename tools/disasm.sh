#!/bin/bash

# create .c.lis.linked files
for i in engine/src/*.c.lis; do
	../zxtools/bin/lis2addr.pl -m main.map -l "$i" > "$i.linked"
done

# get the sort order
FILES=$( for i in engine/src/*.c.lis.linked; do
	printf "%s: %d\n" "$i" "0x$( grep -Pi '^\s+\d+\s+[0-9A-F]+\s+[0-9A-F]+\s+' $i |grep -viP 'DEF[BWS]'|head -1|awk '{print $2}')" 2>/dev/null
done | sort -n -k2 | cut -f1 -d: )

cat $FILES | grep -viP '\s+\d+\s+GLOBAL' | grep -viP '\s+\d+\s+EXTERN' | grep -viP 'DEF[BWSC] ' | grep -viP '\s+\d+\s+SECTION' | grep -viP '\s+\d+\s+;.*' | grep -viP '\s+\d+\s+$' |grep -vE '^\s+$'

#!/bin/bash

if [ $# != 2 ]; then
	echo "usage: $0 <map_file> <mmap_inc_file>"
	exit 1
fi

MAP_FILE="$1"
MMAP_INC="$2"

SECTIONS=$( grep '; addr,' "$MAP_FILE" | cut -f2 -d\; | awk 'BEGIN{ FS = "," }; {print $5}' | sort | uniq )

for section in $SECTIONS; do
	if ! grep -qi "section $section" "$MMAP_INC" ; then
		echo "** Section '$section' is not present in $MMAP_INC"
	fi
done

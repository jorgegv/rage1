#!/bin/bash
if [ $# != 1 ]; then
	echo "usage: memmap.sh <file.map>"
	exit 1
fi

grep "addr," "$1" |perl -ne 'm/^(\w+)\s+=\s\$(\w+)\s*;\s*addr,[\s\w]*,[\s\w]*,[\s\w]*,([\s\w]*),.*/;printf "%-5s %-20s %s\n", $2, $3, $1;'|sort

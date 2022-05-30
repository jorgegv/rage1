#!/bin/bash
# a simple map file sorter, removes some cruft
# a simple script to help you check if everything seems in place or not
if [ $# -ne 1 ]; then
	echo "usage: $0 <map_file>"
	exit 1
fi

grep "; addr," "$1" | grep -vP '_\d{5}'| sort -k 3 | less

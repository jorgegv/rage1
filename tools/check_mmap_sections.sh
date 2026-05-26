#!/bin/bash

# B3-3: accept an explicit --mmap <file> argument so the script can
# validate per-platform mmap.inc variants (e.g. mmap-cpc-flat.inc,
# mmap-cpc-banked.inc). The legacy positional form
# `check_mmap_sections.sh <map_file> <mmap_inc_file>` is still
# accepted as a silent permanent alias. The default mmap is the
# canonical ZX 128 file `mmap.inc` so existing call sites that omit
# --mmap keep working byte-identically.

set -e

usage() {
    cat <<EOF >&2
usage: $0 [--mmap <mmap_inc_file>] <map_file>
       $0 <map_file> <mmap_inc_file>   # legacy positional form
EOF
    exit 1
}

MMAP_INC="mmap.inc"
MAP_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --mmap)
            shift
            [ $# -gt 0 ] || usage
            MMAP_INC="$1"
            shift
            ;;
        --mmap=*)
            MMAP_INC="${1#--mmap=}"
            shift
            ;;
        -h|--help)
            usage
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "** unknown option: $1" >&2
            usage
            ;;
        *)
            break
            ;;
    esac
done

# Remaining positional args
if [ $# -eq 1 ]; then
    MAP_FILE="$1"
elif [ $# -eq 2 ]; then
    # legacy: <map_file> <mmap_inc_file>
    MAP_FILE="$1"
    MMAP_INC="$2"
else
    usage
fi

if [ ! -f "$MAP_FILE" ]; then
    echo "** map file not found: $MAP_FILE" >&2
    exit 1
fi
if [ ! -f "$MMAP_INC" ]; then
    echo "** mmap include file not found: $MMAP_INC" >&2
    exit 1
fi

SECTIONS=$( grep '; addr,' "$MAP_FILE" | cut -f2 -d\; | awk 'BEGIN{ FS = "," }; {print $5}' | sort | uniq )

for section in $SECTIONS; do
    if ! grep -qi "section $section" "$MMAP_INC" ; then
        echo "** Section '$section' is not present in $MMAP_INC"
    fi
done

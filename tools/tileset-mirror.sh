#!/bin/bash
# Mirrors a PNG file and its associated TILEDEF file

if [ $# != 2 ]; then
	echo "usage: $0 <-h|-v> <png_tile_set>"
	exit 1
fi

MIRROR="$1"
TILESET="$2"

BASEDIR="$( dirname "$( realpath "$0" )" )"
TILEDEF_MIRROR="$BASEDIR/tiledef-mirror.pl"

TILESET_WIDTH=$(( $( pngtopam "$TILESET" | pamfile | grep -oP '\d+ by \d+' | awk '{print $1}' ) / 8 ))
TILESET_HEIGHT=$(( $( pngtopam "$TILESET" | pamfile | grep -oP '\d+ by \d+' | awk '{print $3}' ) / 8 ))

TILEDEF_BASE="$( basename "$TILESET" .png)"
TILEDEF="${TILEDEF_BASE}.tiledef"

if [ "$MIRROR" == "-h" ]; then
	MIRRORED="$( basename "$TILESET" .png )_mh.png"
	pngtopam "$TILESET" | pamflip -lr | pamtopng > "$MIRRORED"
	if [ -f "$TILEDEF" ]; then
		$TILEDEF_MIRROR -h -W "$TILESET_WIDTH" -H "$TILESET_HEIGHT" "$TILEDEF" > "${TILEDEF_BASE}_mh.tiledef"
	fi
elif [ "$MIRROR" == "-v" ]; then
	MIRRORED="$( basename "$TILESET" .png )_mv.png"
	pngtopam "$TILESET" | pamflip -tb | pamtopng > "$MIRRORED"
	if [ -f "$TILEDEF" ]; then
		$TILEDEF_MIRROR -v -W "$TILESET_WIDTH" -H "$TILESET_HEIGHT" "$TILEDEF" > "${TILEDEF_BASE}_mv.tiledef"
	fi
else
	echo "  -h or -v is mandatory"
	exit 1
fi

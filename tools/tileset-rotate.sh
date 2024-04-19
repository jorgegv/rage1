#!/bin/bash
# Rotates a PNG file and its associated TILEDEF file

if [ $# != 2 ]; then
	echo "usage: $0 <-r|-l> <png_tile_set>"
	exit 1
fi

ROTATE="$1"
TILESET="$2"

BASEDIR="$( dirname "$( realpath "$0" )" )"
TILEDEF_ROTATE="$BASEDIR/tiledef-rotate.pl"

TILESET_WIDTH=$(( $( perl -MGD::Image -e "print GD::Image->newFromPng('$TILESET')->width;" ) / 8 ))
TILESET_HEIGHT=$(( $( perl -MGD::Image -e "print GD::Image->newFromPng('$TILESET')->height;" ) / 8 ))

TILEDEF_BASE="$( basename "$TILESET" .png)"
TILEDEF="${TILEDEF_BASE}.tiledef"

if [ "$ROTATE" == "-r" ]; then
	ROTATED="$( basename "$TILESET" .png )_rr.png"
	perl -MGD::Image -e "print GD::Image->newFromPng('$TILESET',1)->copyRotate270->png;" > "$ROTATED"
	if [ -f "$TILEDEF" ]; then
		$TILEDEF_ROTATE -r -W "$TILESET_WIDTH" -H "$TILESET_HEIGHT" "$TILEDEF" > "${TILEDEF_BASE}_rr.tiledef"
	fi
elif [ "$ROTATE" == "-l" ]; then
	ROTATED="$( basename "$TILESET" .png )_rl.png"
	perl -MGD::Image -e "print GD::Image->newFromPng('$TILESET',1)->copyRotate90->png;" > "$ROTATED"
	if [ -f "$TILEDEF" ]; then
		$TILEDEF_ROTATE -l -W "$TILESET_WIDTH" -H "$TILESET_HEIGHT" "$TILEDEF" > "${TILEDEF_BASE}_rl.tiledef"
	fi
else
	echo "  -r or -l is mandatory"
	exit 1
fi

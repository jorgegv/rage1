#!/bin/bash

LANG=C

GAME_DATA_DIR=build/game_data
GAME_SRC_DIR=build/game_src
GENERATED_DIR=build/generated

OUTPUT_ASM="$GENERATED_DIR/asm_sub_info.asm"

function sub_sp1buf_configured {
	grep -q -Pi '^\s*SINGLE_USE_BLOB\s+TYPE=SP1' "$GAME_DATA_DIR"/game_config/*.gdata
}

function sub_dsbuf_configured {
	grep -q -Pi '^\s*SINGLE_USE_BLOB\s+TYPE=DS' "$GAME_DATA_DIR"/game_config/*.gdata
}

function get_ds_org_address {
	grep -Pi '^\s*SINGLE_USE_BLOB\s+TYPE=DS' "$GAME_DATA_DIR"/game_config/*.gdata | \
		grep -o -Pi 'DS_ORG_ADDRESS=.+' | cut -f2 -d=
}

num_subs=0

cat <<EOF1 >"$OUTPUT_ASM"
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SUB (Single Use Blob) loading and execution information
;; See doc/SINGLE-USE-BLOB.md
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; This file has been automatically generated. Do not edit!
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	;; we have our own section in the memory map :-)
	SECTION	rage1_subs_loader

	;; exported symbols
	PUBLIC	_sub_info
	PUBLIC	_num_subs

_sub_info:
EOF1

if ( sub_sp1buf_configured ) then
	num_subs=$(( num_subs + 1 ))
	cat <<EOF_SP1BUF >>"$OUTPUT_ASM"
	;; SP1BUF SUB
	db	1		;; type=1, needs_swap=0
	dw	$( stat "$GAME_SRC_DIR/sub_sp1buf/sub.bin" | grep Size | awk '{print $2}' )
	dw	0xd1ed		;; runs from SP1 buffer address
	dw	0x0000		;; unused (needs_swap=0)

EOF_SP1BUF
fi

if ( sub_dsbuf_configured ) then
	num_subs=$(( num_subs + 1 ))
	run_address=$( get_ds_org_address )
	if [ -z "$run_address" ]; then
		run_address="0x0000"
		type_swap=0	# type=0, needs_swap=0
		type_comment="type=0, needs_swap=0"
	else
		type_swap=4	# type=0, needs_swap=1
		type_comment="type=0, needs_swap=1"
	fi
	cat <<EOF_DSBUF >>"$OUTPUT_ASM"
	;; DSBUF SUB
	db	$type_swap		;; $type_comment
	dw	$( stat "$GAME_SRC_DIR/sub_dsbuf/sub.bin" | grep Size | awk '{print $2}' )
	dw	0x5b00		;; runs from DS buffer address...
	dw	$run_address		;; ...or from this one if needs_swap=1

EOF_DSBUF
fi

cat <<EOF2 >>"$OUTPUT_ASM"
_num_subs:
	db	$num_subs

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; End of file
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; This file has been automatically generated. Do not edit!
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
EOF2


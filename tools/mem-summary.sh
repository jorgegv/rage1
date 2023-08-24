#!/bin/bash

MAIN_MAP=main.map
BANKED_MAP=engine/banked_code/banked_code.map

function map_data {
	grep -E '^__.*(_tail|_head)' "$1" |sort|uniq|sort -k3|sed 's/= \$/= /g'
}

function hex2dec {
	read -r n && printf "%d" "0x$n"
}

# main.map
MAIN_DATA_START=$( map_data $MAIN_MAP | grep -E '^__data_compiler_head' | awk '{print $3}' | hex2dec )
MAIN_DATA_END=$( map_data $MAIN_MAP | grep -E '^__data_stdlib_tail' | awk '{print $3}' | hex2dec )
MAIN_BSS_START=$( map_data $MAIN_MAP | grep -E '^__bss_compiler_head' | awk '{print $3}' | hex2dec )
MAIN_BSS_END=$( map_data $MAIN_MAP | grep -E '^__bss_stdlib_tail' | awk '{print $3}' | hex2dec)
MAIN_CODE_START=$( map_data $MAIN_MAP | grep -E '^__code_compiler_head' | awk '{print $3}' | hex2dec )
MAIN_CODE_END=$( map_data $MAIN_MAP | grep -E '^__code_user_tail' | awk '{print $3}' | hex2dec )
SP1_START=$( echo D1ED | hex2dec )
SP1_END=$( echo FFFF | hex2dec )
STARTUP_START=$( echo 8184 | hex2dec )
STARTUP_END=$MAIN_DATA_START
INT_START=$( echo 8000 | hex2dec )
INT_END=$( echo 8183 | hex2dec )

echo "Banks 5,0 (LOWMEM):"
#echo "-----------------------------------"
printf "  %-7s  %6s  %6s  %6s\n" SECTION START END SIZE
#echo "-----------------------------------"

printf "  %-7s  0x%04X  0x%04X  %6d\n" intstk $INT_START $INT_END $(( INT_END - INT_START + 1 ))
printf "  %-7s  0x%04X  0x%04X  %6d\n" startup $STARTUP_START $STARTUP_END $(( STARTUP_END - STARTUP_START + 1 ))
printf "  %-7s  0x%04X  0x%04X  %6d\n" data $MAIN_DATA_START $MAIN_DATA_END $(( MAIN_DATA_END - MAIN_DATA_START ))
printf "  %-7s  0x%04X  0x%04X  %6d\n" bss $MAIN_BSS_START $MAIN_BSS_END $(( MAIN_BSS_END - MAIN_BSS_START ))
printf "  %-7s  0x%04X  0x%04X  %6d\n" code $MAIN_CODE_START $MAIN_CODE_END $(( MAIN_CODE_END - MAIN_CODE_START ))
printf "  %-7s  0x%04X  0x%04X  %6d\n" sp1data $SP1_START $SP1_END $(( SP1_END - SP1_START + 1 ))
#echo "-----------------------------------"
printf "  TOTAL                    %6d\n" $(( MAIN_DATA_END - MAIN_DATA_START + MAIN_BSS_END - MAIN_BSS_START + MAIN_CODE_END - MAIN_CODE_START + SP1_END - SP1_START + 1 + INT_END - INT_START + STARTUP_END - STARTUP_START ))
echo

# banked.map
BANKED_DATA_START=$( map_data $BANKED_MAP | grep -E '^__data_compiler_head' | awk '{print $3}' | hex2dec )
BANKED_DATA_END=$( map_data $BANKED_MAP | grep -E '^__data_compiler_tail' | awk '{print $3}' | hex2dec )
BANKED_BSS_START=$( map_data $BANKED_MAP | grep -E '^__bss_compiler_head' | awk '{print $3}' | hex2dec )
BANKED_BSS_END=$( map_data $BANKED_MAP | grep -E '^__bss_compiler_tail' | awk '{print $3}' | hex2dec)
BANKED_CODE_START=$( map_data $BANKED_MAP | grep -E '^__code_compiler_head' | awk '{print $3}' | hex2dec )
BANKED_CODE_END=$( map_data $BANKED_MAP | grep -E '^__code_compiler_tail' | awk '{print $3}' | hex2dec )

echo "Bank 4 (RAGE1 BANKED CODE):"
#echo "-----------------------------------"
printf "  %-7s  %6s  %6s  %6s\n" SECTION START END SIZE
#echo "-----------------------------------"

printf "  %-7s  0x%04X  0x%04X  %6d\n" code $BANKED_CODE_START $BANKED_CODE_END $(( BANKED_CODE_END - BANKED_CODE_START ))
printf "  %-7s  0x%04X  0x%04X  %6d\n" data $BANKED_DATA_START $BANKED_DATA_END $(( BANKED_DATA_END - BANKED_DATA_START ))
printf "  %-7s  0x%04X  0x%04X  %6d\n" bss $BANKED_BSS_START $BANKED_BSS_END $(( BANKED_BSS_END - BANKED_BSS_START ))
#echo "-----------------------------------"
printf "  TOTAL                    %6d\n" $(( BANKED_DATA_END - BANKED_DATA_START + BANKED_BSS_END - BANKED_BSS_START + BANKED_CODE_END - BANKED_CODE_START ))
echo

# codesets
for codeset_map in build/generated/codesets/codeset_*.map; do
	CODESET_NUM=$( basename $codeset_map | grep -Po 'codeset_\d+' | cut -f2 -d_ )
	CODESET_DATA_START=$( map_data $codeset_map | grep -E '^__data_compiler_head' | awk '{print $3}' | hex2dec )
	CODESET_DATA_END=$( map_data $codeset_map | grep -E '^__data_compiler_tail' | awk '{print $3}' | hex2dec )
	CODESET_BSS_START=$( map_data $codeset_map | grep -E '^__bss_compiler_head' | awk '{print $3}' | hex2dec )
	CODESET_BSS_END=$( map_data $codeset_map | grep -E '^__bss_compiler_tail' | awk '{print $3}' | hex2dec)
	CODESET_CODE_START=$( map_data $codeset_map | grep -E '^__code_compiler_head' | awk '{print $3}' | hex2dec )
	CODESET_CODE_END=$( map_data $codeset_map | grep -E '^__code_compiler_tail' | awk '{print $3}' | hex2dec )

	echo "CODESET $CODESET_NUM (USER CODE):"
#	echo "-----------------------------------"
	printf "  %-7s  %6s  %6s  %6s\n" SECTION START END SIZE
#	echo "-----------------------------------"

	printf "  %-7s  0x%04X  0x%04X  %6d\n" code $CODESET_CODE_START $CODESET_CODE_END $(( CODESET_CODE_END - CODESET_CODE_START ))
	printf "  %-7s  0x%04X  0x%04X  %6d\n" bss $CODESET_BSS_START $CODESET_BSS_END $(( CODESET_BSS_END - CODESET_BSS_START ))
	printf "  %-7s  0x%04X  0x%04X  %6d\n" data $CODESET_DATA_START $CODESET_DATA_END $(( CODESET_DATA_END - CODESET_DATA_START ))
#	echo "-----------------------------------"
	printf "  TOTAL                    %6d\n" $(( CODESET_DATA_END - CODESET_DATA_START + CODESET_BSS_END - CODESET_BSS_START + CODESET_CODE_END - CODESET_CODE_START ))
	echo
done

# datasets
for dataset in $( grep ';; dataset' build/generated/lowmem/dataset_info.asm | awk '{print $3}' ); do
	bank=$( grep -A 1 ";; dataset $dataset" build/generated/lowmem/dataset_info.asm | tail -1 | awk '{print $2}' )
	size=$( grep -A 2 ";; dataset $dataset" build/generated/lowmem/dataset_info.asm | tail -1 | awk '{print $2}' )
	printf "DATASET %d (Bank %d): %d bytes\n" $dataset $bank $size
done

echo

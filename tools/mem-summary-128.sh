#!/bin/bash

MAIN_MAP=main.map
BANKED_MAP=engine/banked_code/banked_code.map

# ansi color sequences
RED='\e[41m\e[37;1m'
GREEN='\e[42m\e[37;1m'
BLUE='\e[44m\e[37;1m'
RESET='\e[0m'


function map_data {
	grep -E '^__' "$1" |sort|uniq|sort -k3|sed 's/= \$/= /g'
}

function hex2dec {
	read -r n && printf "%d" "0x$n"
}

echo
echo -e "${GREEN}    MEMORY AND BANK USAGE REPORT     ${RESET}"
echo

DATASET_MAX_SIZE=$( grep BUILD_MAX_DATASET_SIZE build/generated/game_data.h | awk '{print $3'} )

# main.map
MAIN_DATA_START=$( map_data $MAIN_MAP | grep -E '^__data_compiler_head' | awk '{print $3}' | hex2dec )
MAIN_DATA_END=$( map_data $MAIN_MAP | grep -E '^__data_stdlib_tail' | awk '{print $3}' | hex2dec )
MAIN_BSS_START=$( map_data $MAIN_MAP | grep -E '^__bss_compiler_head' | awk '{print $3}' | hex2dec )
MAIN_BSS_END=$( map_data $MAIN_MAP | grep -E '^__bss_stdlib_tail' | awk '{print $3}' | hex2dec)
MAIN_CODE_START=$( map_data $MAIN_MAP | grep -E '^__code_compiler_head' | awk '{print $3}' | hex2dec )
MAIN_CODE_END=$( map_data $MAIN_MAP | grep -E '^__code_user_tail' | awk '{print $3}' | hex2dec )
SP1_START=$( echo D1ED | hex2dec )
SP1_END=$( echo FFFF | hex2dec )
STARTUP_START=$( map_data $MAIN_MAP | grep -E '^__Start' | awk '{print $3}' | hex2dec )
STARTUP_END=$MAIN_DATA_START
INT_START=$( grep iv_table_addr etc/rage1-config.yml | awk '{print $2}' | sed 's/^0x//g' | hex2dec )
INT_END=$( echo "$(( $( grep base_code_address etc/rage1-config.yml | awk '{print $2}' | sed 's/^0x//g' ) - 1 ))" | hex2dec )

echo "BANKS 5,2,0 [Screen + RAGE1 Heap + Lowmem]"
echo
printf "  %-12s  %-5s  %-5s  %5s\n" SECTION START END SIZE

printf "  %-12s  \$%04x  \$%04x  %5d\n" screen 16384 22575 6912
printf "  %-12s  \$%04x  \$%04x  %5d\n" databuf 22576 $(( 22576 + DATASET_MAX_SIZE - 1 )) $DATASET_MAX_SIZE
printf "  %-12s  \$%04x  \$%04x  %5d\n" heap $(( 22576 + DATASET_MAX_SIZE )) 32767 $(( 32768 - 22576 - DATASET_MAX_SIZE ))
printf "  %-12s  \$%04x  \$%04x  %5d\n" intstk $INT_START $INT_END $(( INT_END - INT_START + 1 ))
printf "  %-12s  \$%04x  \$%04x  %5d\n" startup $STARTUP_START $STARTUP_END $(( STARTUP_END - STARTUP_START + 1 ))
printf "  %-12s  \$%04x  \$%04x  %5d\n" data $MAIN_DATA_START $MAIN_DATA_END $(( MAIN_DATA_END - MAIN_DATA_START ))
printf "  %-12s  \$%04x  \$%04x  %5d\n" bss $MAIN_BSS_START $MAIN_BSS_END $(( MAIN_BSS_END - MAIN_BSS_START ))
printf "  %-12s  \$%04x  \$%04x  %5d\n" code $MAIN_CODE_START $MAIN_CODE_END $(( MAIN_CODE_END - MAIN_CODE_START ))
printf "  %-12s  \$%04x  \$%04x  %5d\n" sp1data $SP1_START $SP1_END $(( SP1_END - SP1_START + 1 ))
echo

TOTAL=$(( MAIN_DATA_END - MAIN_DATA_START + MAIN_BSS_END - MAIN_BSS_START + MAIN_CODE_END - MAIN_CODE_START + SP1_END - SP1_START + 1 + INT_END - INT_START + STARTUP_END - STARTUP_START ))
printf "$GREEN  TOTAL                      %6d  $RESET\n" $TOTAL
printf "$RED  FREE                       %6d  $RESET\n" $(( 32768 - TOTAL ))
echo

# banked.map
BANKED_DATA_START=$( map_data $BANKED_MAP | grep -E '^__data_compiler_head' | awk '{print $3}' | hex2dec )
BANKED_DATA_END=$( map_data $BANKED_MAP | grep -E '^__data_compiler_tail' | awk '{print $3}' | hex2dec )
BANKED_BSS_START=$( map_data $BANKED_MAP | grep -E '^__bss_compiler_head' | awk '{print $3}' | hex2dec )
BANKED_BSS_END=$( map_data $BANKED_MAP | grep -E '^__bss_compiler_tail' | awk '{print $3}' | hex2dec)
BANKED_CODE_START=$( map_data $BANKED_MAP | grep -E '^__code_compiler_head' | awk '{print $3}' | hex2dec )
BANKED_CODE_END=$( map_data $BANKED_MAP | grep -E '^__code_compiler_tail' | awk '{print $3}' | hex2dec )

echo "BANK 4 [RAGE1 banked code + Tracker data]"
echo
printf "  %-12s  %-5s  %-5s  %5s\n" SECTION START END SIZE

printf "  %-12s  \$%04x  \$%04x  %5d\n" code $BANKED_CODE_START $BANKED_CODE_END $(( BANKED_CODE_END - BANKED_CODE_START ))
printf "  %-12s  \$%04x  \$%04x  %5d\n" data $BANKED_DATA_START $BANKED_DATA_END $(( BANKED_DATA_END - BANKED_DATA_START ))
printf "  %-12s  \$%04x  \$%04x  %5d\n" bss $BANKED_BSS_START $BANKED_BSS_END $(( BANKED_BSS_END - BANKED_BSS_START ))
echo
TOTAL=$(( BANKED_DATA_END - BANKED_DATA_START + BANKED_BSS_END - BANKED_BSS_START + BANKED_CODE_END - BANKED_CODE_START ))
printf "$GREEN  TOTAL                      %6d  $RESET\n" $TOTAL
printf "$RED  FREE                       %6d  $RESET\n" $(( 16384 - TOTAL ))
echo

# banks
BANKS=$( grep -E '^\w' build/generated/bank_bins.cfg | awk '{print $2}' | sort | uniq )

# codeset/dataset banks
for bank_num in $BANKS; do
	echo "BANK $bank_num [codeset/dataset]"
	echo

	BANK_TOTAL=0

	codeset_num=$( grep -P "^codeset $bank_num" build/generated/bank_bins.cfg | awk '{print $4}' )
	if [ -n "$codeset_num" ]; then
		codeset_map=build/generated/codesets/codeset_$codeset_num.map
		CODESET_DATA_START=$( map_data $codeset_map | grep -E '^__data_compiler_head' | awk '{print $3}' | hex2dec )
		CODESET_DATA_END=$( map_data $codeset_map | grep -E '^__data_compiler_tail' | awk '{print $3}' | hex2dec )
		CODESET_BSS_START=$( map_data $codeset_map | grep -E '^__bss_compiler_head' | awk '{print $3}' | hex2dec )
		CODESET_BSS_END=$( map_data $codeset_map | grep -E '^__bss_compiler_tail' | awk '{print $3}' | hex2dec)
		CODESET_CODE_START=$( map_data $codeset_map | grep -E '^__code_compiler_head' | awk '{print $3}' | hex2dec )
		CODESET_CODE_END=$( map_data $codeset_map | grep -E '^__code_compiler_tail' | awk '{print $3}' | hex2dec )

		echo "  CODESET:"
		echo
		printf "    %-10s  %-5s  %-5s  %5s\n" SECTION START END SIZE
		printf "    %-10s  \$%04x  \$%04x  %5d\n" code $CODESET_CODE_START $CODESET_CODE_END $(( CODESET_CODE_END - CODESET_CODE_START ))
		printf "    %-10s  \$%04x  \$%04x  %5d\n" bss $CODESET_BSS_START $CODESET_BSS_END $(( CODESET_BSS_END - CODESET_BSS_START ))
		printf "    %-10s  \$%04x  \$%04x  %5d\n" data $CODESET_DATA_START $CODESET_DATA_END $(( CODESET_DATA_END - CODESET_DATA_START ))
		TOTAL_CODESET=$(( CODESET_DATA_END - CODESET_DATA_START + CODESET_BSS_END - CODESET_BSS_START + CODESET_CODE_END - CODESET_CODE_START ))
		BANK_TOTAL=$(( BANK_TOTAL + TOTAL_CODESET ))
		echo
	fi

	if ( grep -qE "^dataset $bank_num" build/generated/bank_bins.cfg ) then
		echo "  DATASETS:"
		echo
		echo "    SECTION            SIZE   CSIZE"
		for dataset in $( grep -P "^dataset $bank_num" build/generated/bank_bins.cfg | cut -f4- -d' ' ); do
			comp_size=$( stat "build/generated/datasets/dataset_$dataset.zx0" -t|awk '{print $2}' )
			uncomp_size=$( stat "build/generated/datasets/dataset_$dataset.bin.save" -t|awk '{print $2}' )
			printf "    %-10s       %6d  %6d\n" "dataset_$dataset" $uncomp_size $comp_size
			BANK_TOTAL=$(( BANK_TOTAL + comp_size ))
		done

		echo
		echo "  Max. allowed dataset size: $DATASET_MAX_SIZE"
		echo
	fi

	printf "$GREEN  TOTAL                      %6d  $RESET\n" $BANK_TOTAL
	printf "$RED  FREE                       %6d  $RESET\n" $(( 16384 - BANK_TOTAL ))
	echo
done
exit

# datasets
for bank_num in $( grep -E '^dataset' build/generated/bank_bins.cfg | awk '{print $2}' ); do
	echo "BANK $bank_num [datasets]"
	echo "  SECTION              SIZE   CSIZE"
	BANK_TOTAL=0
	for dataset in $( grep -P "^dataset $bank_num" build/generated/bank_bins.cfg | cut -f4- -d' ' ); do
		comp_size=$( stat "build/generated/datasets/dataset_$dataset.zx0" -t|awk '{print $2}' )
		uncomp_size=$( stat "build/generated/datasets/dataset_$dataset.bin.save" -t|awk '{print $2}' )
		printf "  %-12s       %6d  %6d\n" "dataset_$dataset" $uncomp_size $comp_size
		BANK_TOTAL=$(( BANK_TOTAL + comp_size ))
	done

	echo

	echo
	printf "$GREEN  TOTAL                      %6d  $RESET\n" $BANK_TOTAL
	printf "$RED  FREE                       %6d  $RESET\n" $(( 16384 - BANK_TOTAL ))
	echo
done

echo

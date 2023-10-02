#!/bin/bash

MAIN_MAP=main.map

# ansi color sequences
RED='\e[41m\e[37;1m'
GREEN='\e[42m\e[37;1m'
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
INT_START=$( echo D000 | hex2dec )
INT_END=$( echo D1D3 | hex2dec )

echo "Banks 5,2,0 [Screen + RAGE1 Heap + Lowmem]"
printf "  %-12s  %-5s  %-5s  %5s\n" SECTION START END SIZE

printf "  %-12s  \$%04x  \$%04x  %5d\n" startup $STARTUP_START $STARTUP_END $(( STARTUP_END - STARTUP_START + 1 ))
printf "  %-12s  \$%04x  \$%04x  %5d\n" data $MAIN_DATA_START $MAIN_DATA_END $(( MAIN_DATA_END - MAIN_DATA_START ))
printf "  %-12s  \$%04x  \$%04x  %5d\n" bss $MAIN_BSS_START $MAIN_BSS_END $(( MAIN_BSS_END - MAIN_BSS_START ))
printf "  %-12s  \$%04x  \$%04x  %5d\n" code $MAIN_CODE_START $MAIN_CODE_END $(( MAIN_CODE_END - MAIN_CODE_START ))
printf "  %-12s  \$%04x  \$%04x  %5d\n" intstk $INT_START $INT_END $(( INT_END - INT_START + 1 ))
printf "  %-12s  \$%04x  \$%04x  %5d\n" sp1data $SP1_START $SP1_END $(( SP1_END - SP1_START + 1 ))
echo

TOTAL=$(( MAIN_DATA_END - MAIN_DATA_START + MAIN_BSS_END - MAIN_BSS_START + MAIN_CODE_END - MAIN_CODE_START + SP1_END - SP1_START + 1 + INT_END - INT_START + STARTUP_END - STARTUP_START ))
printf "$GREEN  TOTAL                      %6d  $RESET\n" $TOTAL
# 41216 = 64k - $5F00 (__Start)
printf "$RED  FREE                       %6d  $RESET\n" $(( 65536 - STARTUP_START - TOTAL ))
echo

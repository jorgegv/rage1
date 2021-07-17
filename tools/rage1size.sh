#!/bin/bash

echo "RAGE1 memory usage:"

TOTAL_CODE=0
TOTAL_DATA=0
TOTAL_BSS=0

printf "%-20s  %5s  %5s  %5s\n" "Object file" "CODE" "DATA" "BSS"
echo "-------------------------------------------"
for ofile in engine/src/*.o; do
	CODE_SIZE=$( z88dk-z80nm "$ofile" | grep "Section code_compiler:" | awk '{print $3}' )
	DATA_SIZE=$( z88dk-z80nm "$ofile" | grep "Section data_compiler:" | awk '{print $3}' )
	BSS_SIZE=$(  z88dk-z80nm "$ofile" | grep "Section bss_compiler:"  | awk '{print $3}' )

	TOTAL_CODE=$(( TOTAL_CODE + CODE_SIZE ))
	TOTAL_DATA=$(( TOTAL_DATA + DATA_SIZE ))
	TOTAL_BSS=$((  TOTAL_BSS  + BSS_SIZE ))

	printf "%-20s  %5d  %5d  %5d\n" "$( basename "$ofile" )" "$CODE_SIZE" "$DATA_SIZE" "$BSS_SIZE"
done
echo "-------------------------------------------"
printf "%-20s  %5d  %5d  %5d\n" "TOTAL" $TOTAL_CODE $TOTAL_DATA $TOTAL_BSS

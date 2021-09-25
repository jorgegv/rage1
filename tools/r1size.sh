#!/bin/bash

################################################################################
##
## RAGE1 - Retro Adventure Game Engine, release 1
## (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
## 
## This code is published under a GNU GPL license version 3 or later.  See
## LICENSE file in the distribution for details.
## 
################################################################################

echo "RAGE1 memory usage:"

TOTAL_CODE=0
TOTAL_DATA=0
TOTAL_BSS=0

printf "%-20s  %5s  %5s  %5s\n" "Object file" "CODE" "DATA" "BSS"
echo "-------------------------------------------"
for ofile in engine/src/*.o engine/lowmem/*.o build/generated/*.o build/game_src/*.o build/generated/lowmem/*.o; do
	CODE_SIZE=$( z88dk-z80nm "$ofile" | grep -P "Section code_.* \d+ bytes" | awk '{print $3}' | perl -ne 'BEGIN{$s=0;} $s+=$_; END{print $s;}' )
	DATA_SIZE=$( z88dk-z80nm "$ofile" | grep -P "Section data_.* \d+ bytes" | awk '{print $3}' | perl -ne 'BEGIN{$s=0;} $s+=$_; END{print $s;}' )
	BSS_SIZE=$(  z88dk-z80nm "$ofile" | grep -P "Section bss_.* \d+ bytes"  | awk '{print $3}' | perl -ne 'BEGIN{$s=0;} $s+=$_; END{print $s;}' )

	TOTAL_CODE=$(( TOTAL_CODE + CODE_SIZE ))
	TOTAL_DATA=$(( TOTAL_DATA + DATA_SIZE ))
	TOTAL_BSS=$((  TOTAL_BSS  + BSS_SIZE ))

	printf "%-20s  %5d  %5d  %5d\n" "$( basename "$ofile" )" "$CODE_SIZE" "$DATA_SIZE" "$BSS_SIZE"
done
echo "-------------------------------------------"
printf "%-20s  %5d  %5d  %5d\n" "TOTAL" $TOTAL_CODE $TOTAL_DATA $TOTAL_BSS

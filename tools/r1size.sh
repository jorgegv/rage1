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

TOTAL_CODE=0
TOTAL_DATA=0
TOTAL_BSS=0

echo "---------------------------------------------------------------------"
printf "%-40s  %5s  %5s  %5s\n" "OBJECT FILE" "CODE" "DATA" "BSS"
echo "---------------------------------------------------------------------"
FILES=$( ls engine/src/*.o engine/lowmem/*.o engine/banked_code/common/*.o build/generated/*.o build/game_src/*.o build/generated/lowmem/*.o 2>/dev/null )
for ofile in $FILES; do
	CODE_SIZE=$( z88dk-z80nm "$ofile" | grep -P "Section code_.* \d+ bytes" | awk '{print $3}' | perl -ne 'BEGIN{$s=0;} $s+=$_; END{print $s;}' )
	DATA_SIZE=$( z88dk-z80nm "$ofile" | grep -P "Section data_.* \d+ bytes" | awk '{print $3}' | perl -ne 'BEGIN{$s=0;} $s+=$_; END{print $s;}' )
	BSS_SIZE=$(  z88dk-z80nm "$ofile" | grep -P "Section bss_.* \d+ bytes"  | awk '{print $3}' | perl -ne 'BEGIN{$s=0;} $s+=$_; END{print $s;}' )

	TOTAL_CODE=$(( TOTAL_CODE + CODE_SIZE ))
	TOTAL_DATA=$(( TOTAL_DATA + DATA_SIZE ))
	TOTAL_BSS=$((  TOTAL_BSS  + BSS_SIZE ))

	printf "%-40s  %5d  %5d  %5d\n" "$ofile" "$CODE_SIZE" "$DATA_SIZE" "$BSS_SIZE"
done
echo "---------------------------------------------------------------------"
printf "%-40s  %5d  %5d  %5d\n" "TOTAL" $TOTAL_CODE $TOTAL_DATA $TOTAL_BSS

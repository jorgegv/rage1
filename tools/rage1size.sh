#!/bin/bash

echo "RAGE1 memory usage:"
printf "  code: %5d bytes\n" \
	$( z88dk-z80nm engine/src/*.o|grep "Section code_compiler:"|awk '{print $3}'|perl -ne 'BEGIN { $s=0; } $s+=$_; END { print $s;}' )
printf "  data: %5d bytes\n" \
	$( z88dk-z80nm engine/src/*.o|grep "Section data_compiler:"|awk '{print $3}'|perl -ne 'BEGIN { $s=0; } $s+=$_; END { print $s;}' )
printf "  bss : %5d bytes\n" \
	$( z88dk-z80nm engine/src/*.o|grep "Section bss_compiler:"|awk '{print $3}'|perl -ne 'BEGIN { $s=0; } $s+=$_; END { print $s;}' )

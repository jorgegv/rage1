#!/bin/bash

DATASETS=$( cd build/generated/datasets; ls -1 dataset*.bin* | cut -f2 -d_ | cut -f1 -d. | sort -n | uniq )

for i in $DATASETS; do
	dir="build/generated/datasets/dataset_$i.src"
	ARENA_SIZE=$( grep -E "^uint8_t all_dataset_btile_data" "$dir/main.c" | awk '{print $3}' )
	TILEPTR_SIZE=$( grep -E '^uint8_t \*btile.*tiles' "$dir/main.c" | awk '{print $3}' | perl -ne '$a+=3*$_; END { print $a,"\n"; }' )
	BTILEPOS_SIZE=$( grep -E '^struct btile_pos_s screen_' "$dir/main.c" | awk '{print $4}' | perl -ne '$a+=5*$_; END { print $a,"\n"; }' )
	SCREEN_SIZE=$( grep -E "^struct map_screen_s all_screens" "$dir/main.c" | awk '{print $4}' | perl -ne '$a+=29*$_; END { print $a,"\n"; }' )
	DS_SIZE=$( ls -l "build/generated/datasets/dataset_$i.bin.save" | awk '{print $5}' )
	REST=$(( DS_SIZE - ARENA_SIZE - TILEPTR_SIZE - BTILEPOS_SIZE - SCREEN_SIZE ))
	printf "Dataset %2d: %5d bytes - Arena: %4d - BTdefs: %4d - BTpos: %4d - Screens: %4d - Rest: %4d\n" \
		"$i" "$DS_SIZE" "$ARENA_SIZE" "$TILEPTR_SIZE" "$BTILEPOS_SIZE" "$SCREEN_SIZE" "$REST"
done

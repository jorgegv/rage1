#!/bin/bash

DATASETS=$( cd build/generated/datasets; ls -1 dataset*.bin* | cut -f2 -d_ | cut -f1 -d. | sort -n | uniq )

for i in $DATASETS; do
	dir="build/generated/datasets/dataset_$i.src"
	DS_SIZE=$( ls -l "build/generated/datasets/dataset_$i.bin.save" | awk '{print $5}' )
	DS_CSIZE=$( ls -l "build/generated/datasets/dataset_$i.zx0" | awk '{print $5}' )
	ARENA_SIZE=$( grep -E "^uint8_t all_dataset_btile_data" "$dir/main.c" | awk '{print $3}' )
	TILEPTR_COUNT=$( grep -E '^uint8_t \*btile.*tiles' "$dir/main.c" | awk '{print $3}' | perl -ne '$a+=$_; END { print $a,"\n"; }' )
	TILEPTR_SIZE=$(( TILEPTR_COUNT * 3 ))
	TILETAB_COUNT=$( grep -E '^struct btile_s all_btiles' "$dir/main.c" | awk '{print $4}' | perl -ne '$a+=$_; END { print $a,"\n"; }' )
	TILETAB_SIZE=$(( TILETAB_COUNT * 6 ))
	BTILEPOS_COUNT=$( grep -E '^struct btile_pos_s screen_' "$dir/main.c" | awk '{print $4}' | perl -ne '$a+=$_; END { print $a,"\n"; }' )
	BTILEPOS_SIZE=$(( BTILEPOS_COUNT * 5 ))
	SCREEN_COUNT=$( grep -E "^struct map_screen_s all_screens" "$dir/main.c" | awk '{print $4}' | perl -ne '$a+=$_; END { print $a,"\n"; }' )
	SCREEN_SIZE=$(( SCREEN_COUNT * 29 ))
	REST=$(( DS_SIZE - ARENA_SIZE - TILETAB_SIZE - TILEPTR_SIZE - BTILEPOS_SIZE - SCREEN_SIZE ))
	printf "Dataset %2d: %5db (C:%5db) - Arena: %4db - BTtab: %3d(%4db) BTptrs: %3d(%4db) - BTpos: %3d(%4db) - Screens: %3d(%4db) - Rest: %4db\n" \
		"$i" "$DS_SIZE" "$DS_CSIZE" "$ARENA_SIZE" "$TILETAB_COUNT" "$TILETAB_SIZE" "$TILEPTR_COUNT" "$TILEPTR_SIZE" "$BTILEPOS_COUNT" "$BTILEPOS_SIZE" "$SCREEN_COUNT" "$SCREEN_SIZE" "$REST"
done

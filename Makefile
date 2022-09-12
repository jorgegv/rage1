################################################################################
##
## RAGE1 - Retro Adventure Game Engine, release 1
## (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
##
## This code is published under a GNU GPL license version 3 or later.  See
## LICENSE file in the distribution for details.
##
################################################################################

-include Makefile.common

# build targets
.PHONY: data all build clean clean-config data_depend build-data help

help:
	@echo "============================================================"
	@echo "==  RAGE1 library Makefile                                =="
	@echo "============================================================"
	@echo ""
	@echo "Usage: make <target> [options]..."
	@echo ""
	@echo "Available targets:"
	@grep -P '^[\w\-]+:' Makefile | grep -v ":=" | cut -f1 -d: | grep -v -E '^default' | sed 's/^/    /g'
	@echo ""
	@echo "* Use 'make new-game' for creating a new template game using the library"
	@echo "* Use 'make update-game' for updating library code in an existing game"
	@echo ""

clean:
	@-rm -rf *.{lis,bin,tap,c.asm,map,log,sym} \
		$(BUILD_DIR)/{game_src,game_data,generated} \
		$(ENGINE_DIR)/src/*.{map,lis,o,c.asm,sym,bin} \
		$(ENGINE_DIR)/lowmem/*.{map,lis,o,c.asm,sym,bin} \
		$(GAME_SRC_DIR)/*.{map,lis,o,c.asm,sym,bin} \
		$(GAME_DATA_DIR)/*.{map,lis,o,c.asm,sym,bin} \
		$(BANKED_CODE_DIR)/*.{map,lis,o,c.asm,,sym,bin} \
		$(BANKED_CODE_DIR_COMMON)/*.{map,lis,o,c.asm,,sym,bin} \
		$(BANKED_CODE_DIR_128)/*.{map,lis,o,c.asm,,sym,bin} \
		2>/dev/null
config:
	@-rm -rf $(GAME_SRC_DIR)/* $(GAME_DATA_DIR)/* 2>/dev/null
	@-mkdir -p $(GAME_SRC_DIR)/ $(GAME_DATA_DIR)/ $(GENERATED_DIR)/ $(GENERATED_DIR_DATASETS)/ $(GENERATED_DIR_CODESETS)/ $(GENERATED_DIR_LOWMEM)/
	@cp -r $(TARGET_GAME)/game_data/* $(GAME_DATA_DIR)/
	@cp -r $(TARGET_GAME)/game_src/* $(GAME_SRC_DIR)/
	@$(MAKE) -s show	# shows game name and build configuration

# build: starts a build in the mode specified in the game config
build:
	@if [ -z "$(shell grep -E 'ZX_TARGET.+(48|128)$$' $(TARGET_GAME)/game_data/game_config/*.gdata 2>/dev/null|head -1|awk '{print $$2}')" ]; then echo "** Error: ZX_TARGET must be configured in the game if using default build"; exit 1; fi
	@$(MAKE) -s clean
	@$(MAKE) -s ZX_TARGET=$(shell grep -E 'ZX_TARGET.+(48|128)$$' $(TARGET_GAME)/game_data/game_config/*.gdata 2>/dev/null|head -1|awk '{print $$2}') config
	@$(MAKE) -s ZX_TARGET=$(shell grep -E 'ZX_TARGET.+(48|128)$$' $(TARGET_GAME)/game_data/game_config/*.gdata 2>/dev/null|head -1|awk '{print $$2}') data
	@$(MAKE) -s -f Makefile-$(shell grep -E 'ZX_TARGET.+(48|128)$$' $(TARGET_GAME)/game_data/game_config/*.gdata 2>/dev/null|head -1|awk '{print $$2}') build

build48:
	@$(MAKE) -s clean
	@$(MAKE) -s ZX_TARGET=48 config
	@$(MAKE) -s ZX_TARGET=48 data
	@$(MAKE) -s -f Makefile-48 build

build128:
	@$(MAKE) -s clean
	@$(MAKE) -s ZX_TARGET=128 config
	@$(MAKE) -s ZX_TARGET=128 data
	@$(MAKE) -s -f Makefile-128 build

# additional test games

build-tests: build-minimal build-blobs build-crumbs build-mapgen build-damage_mode

build-minimal:
	@$(MAKE) -s build target_game=games/minimal

build-blobs:
	@$(MAKE) -s build target_game=games/blobs

build-crumbs:
	@$(MAKE) -s build target_game=games/crumbs

build-mapgen:
	@$(MAKE) -s clean
	@cd games/mapgen && ../../tools/btilegen.pl game_data/png/test-tiles.png > game_data/btiles/autobtiles.gdata
	@cd games/mapgen && ../../tools/mapgen.pl --screen-cols 24 --screen-rows 16 \
		--game-data-dir game_data --game-area-top 1 --game-area-left 1 \
		--hero-sprite-width 16 --hero-sprite-height 16 --auto-hotzones \
		--generate-check-map \
		game_data/png/test-tiles.png \
		game_data/png/demo-map-3x2-screens-24x16.png
	@$(MAKE) -s ZX_TARGET=48 config target_game=games/mapgen
	@$(MAKE) -s ZX_TARGET=48 data
	@$(MAKE) -s -f Makefile-48 build

build-damage_mode:
	@$(MAKE) -s build target_game=games/damage_mode

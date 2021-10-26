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

# include minimal game configuration.  If the Makefile has been copied to a
# Game directory 'make build' works as usual.  If it is the Makefile on the
# RAGE1 directory, it will include minimal-game config and allow to use it
-include minimal-game.mk

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
	@echo "Build config: REGULAR GAME"	# change for the name of the game!
	@grep -qE 'ZX_TARGET.+(48|128)$$' game/game_data/game_config/*.gdata || \
		( echo "** Error: ZX_TARGET must be defined as 48|128" && exit 1 )
	@echo "Build target: $(ZX_TARGET)K"

build:
	@$(MAKE) -s clean
	@$(MAKE) -s config
	@$(MAKE) -s data
	@$(MAKE) -s -f Makefile-$(ZX_TARGET) build

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

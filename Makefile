################################################################################
##
## RAGE1 - Retro Adventure Game Engine, release 1
## (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
##
## This code is published under a GNU GPL license version 3 or later.  See
## LICENSE file in the distribution for details.
##
################################################################################

.SILENT:

MYMAKE	= make -s

-include Makefile.common

# build targets
.PHONY: data all build clean clean-config data_depend build-data help

help:
	echo "============================================================"
	echo "==  RAGE1 library Makefile                                =="
	echo "============================================================"
	echo ""
	echo "Usage: make <target> [options]..."
	echo ""
	echo "Available targets:"
	grep -P '^[\w\-]+:' Makefile | grep -v ":=" | cut -f1 -d: | grep -v -E '^default' | sed 's/^/    /g'
	echo ""
	echo "* Use 'make new-game' for creating a new template game using the library"
	echo ""

clean:
	-rm -rf *.{lis,linked,bin,tap,c.asm,map,log,sym} \
		$(BUILD_DIR)/{game_src,game_data,generated} \
		$(ENGINE_DIR)/src/*.{map,lis,linked,o,c.asm,sym,bin} \
		$(ENGINE_DIR)/lowmem/*.{map,lis,linked,o,c.asm,sym,bin} \
		$(GAME_SRC_DIR)/*.{map,lis,linked,o,c.asm,sym,bin} \
		$(GAME_DATA_DIR)/*.{map,lis,linked,o,c.asm,sym,bin} \
		$(BANKED_CODE_DIR)/*.{map,lis,linked,o,c.asm,,sym,bin} \
		$(BANKED_CODE_DIR_COMMON)/*.{map,lis,linked,o,c.asm,,sym,bin} \
		$(BANKED_CODE_DIR_128)/*.{map,lis,linked,o,c.asm,,sym,bin} \
		2>/dev/null
config:
	-rm -rf $(GAME_SRC_DIR)/* $(GAME_DATA_DIR)/* $(GENERATED_DIR)/* 2>/dev/null
	-mkdir -p $(GAME_SRC_DIR)/		\
		$(GAME_DATA_DIR)/		\
		$(GENERATED_DIR)/		\
		$(GENERATED_DIR_DATASETS)/	\
		$(GENERATED_DIR_CODESETS)/	\
		$(GENERATED_DIR_BANKED_128)/	\
		$(GENERATED_DIR_BANKED_COMMON)/	\
		$(GENERATED_DIR_ASMLOADER)/	\
		$(GENERATED_DIR_SUBS)/
	cp -r $(TARGET_GAME)/game_data/* $(GAME_DATA_DIR)/
	cp -r $(TARGET_GAME)/game_src/* $(GAME_SRC_DIR)/
	$(MYMAKE) show	# shows game name and build configuration

# build: starts a build of the 'default' game in the mode specified in the game config
build:
	if [ -z "$(shell grep -E 'ZX_TARGET.+(48|128)$$' $(TARGET_GAME)/game_data/game_config/*.gdata 2>/dev/null|head -1|awk '{print $$2}')" ]; then echo "** Error: ZX_TARGET must be configured in the game if using default build"; exit 1; fi
	$(MYMAKE) clean
	$(MYMAKE) ZX_TARGET=$(shell grep -E 'ZX_TARGET.+(48|128)$$' $(TARGET_GAME)/game_data/game_config/*.gdata 2>/dev/null|head -1|awk '{print $$2}') config
	$(MYMAKE) ZX_TARGET=$(shell grep -E 'ZX_TARGET.+(48|128)$$' $(TARGET_GAME)/game_data/game_config/*.gdata 2>/dev/null|head -1|awk '{print $$2}') data
	$(MYMAKE) -f Makefile-$(shell grep -E 'ZX_TARGET.+(48|128)$$' $(TARGET_GAME)/game_data/game_config/*.gdata 2>/dev/null|head -1|awk '{print $$2}') build

# forced config build for 48 mode
build48:
	$(MYMAKE) clean
	$(MYMAKE) ZX_TARGET=48 config
	$(MYMAKE) ZX_TARGET=48 data
	$(MYMAKE) -f Makefile-48 build

# forced config build for 128 mode
build128:
	$(MYMAKE) clean
	$(MYMAKE) ZX_TARGET=128 config
	$(MYMAKE) ZX_TARGET=128 data
	$(MYMAKE) -f Makefile-128 build

###############################################
##
## TARGETS FOR TEST GAME BUILDS
##
###############################################

# contains all the test games
ALL_TEST_GAMES		= $(shell cd $(TEST_GAMES_DIR)/ && ls -1 )

# detailed build rules for each test game
build-minimal:
	$(MYMAKE) build target_game=$(TEST_GAMES_DIR)/minimal

build-blobs:
	$(MYMAKE) build target_game=$(TEST_GAMES_DIR)/blobs

build-crumbs:
	$(MYMAKE) build target_game=$(TEST_GAMES_DIR)/crumbs

build-mapgen:
	$(MYMAKE) clean
	cd $(TEST_GAMES_DIR)/mapgen && ../../tools/btilegen.pl game_data/png/test-tiles.png > game_data/btiles/autobtiles.gdata
	cd $(TEST_GAMES_DIR)/mapgen && ../../tools/mapgen.pl --screen-cols 24 --screen-rows 16 \
		--game-data-dir game_data --game-area-top 1 --game-area-left 1 \
		--hero-sprite-width 16 --hero-sprite-height 16 --auto-hotzones \
		--generate-check-map \
		game_data/png/test-tiles.png \
		game_data/png/demo-map-3x2-screens-24x16.png
	$(MYMAKE) ZX_TARGET=48 config target_game=$(TEST_GAMES_DIR)/mapgen
	$(MYMAKE) ZX_TARGET=48 data
	$(MYMAKE) -f Makefile-48 build

build-damage_mode:
	$(MYMAKE) build target_game=$(TEST_GAMES_DIR)/damage_mode

build-get_weapon:
	$(MYMAKE) build target_game=$(TEST_GAMES_DIR)/get_weapon

build-monochrome:
	$(MYMAKE) build target_game=$(TEST_GAMES_DIR)/monochrome

build-vortex2:
	$(MYMAKE) build target_game=$(TEST_GAMES_DIR)/vortex2

build-sub_bufs_48:
	$(MYMAKE) build target_game=$(TEST_GAMES_DIR)/sub_bufs_48

build-sub_bufs_128:
	$(MYMAKE) build target_game=$(TEST_GAMES_DIR)/sub_bufs_128

# just a target for the default game for completeness
build-default: build

# generic rule for test builds
test-build-%:
	printf 'Building test game %.15s...' "'$*'..............."
	if ( ! $(MYMAKE) build-$* >/tmp/build-$*.log 2>&1 ) then echo " Errors - see /tmp/build-$*.log"; else echo " Build OK"; fi

all-test-builds:
	echo -n "START: "
	date
	for i in $(ALL_TEST_GAMES); do $(MYMAKE) test-build-$$i; done | tee /tmp/all-test-builds.log
	echo -n "END: "
	date
	if ( grep -i Errors /tmp/all-test-builds.log ) then \
		echo "*** Some tests failed ***"; \
		exit 1; \
	else \
		echo "All tests succeeded"; \
		exit 0; \
	fi

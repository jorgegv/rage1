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
.PHONY: data all build clean clean-config data_depend build-data help regression check-input-includes check-input-hal build-zx48 build-zx128 build48 build128 build-cpc464 data-cpc464 build-cpc-hello all-test-builds all-test-builds-zx all-test-builds-cpc

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
	echo "Platform build targets:"
	echo "    build-zx48     force ZX Spectrum 48K build"
	echo "    build-zx128    force ZX Spectrum 128K build"
	echo "    build48        legacy silent alias for build-zx48 (permanent, README §5.6)"
	echo "    build128       legacy silent alias for build-zx128 (permanent, README §5.6)"
	echo "    build-cpc464   force CPC464/664 (cpc-flat) build"
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
	# A2-1: per-platform sibling overlay copy. After the shared trees
	# above land in build/, overlay any files from the per-platform
	# sibling subtree at $(TARGET_GAME)/$(PLATFORM)/{game_data,game_src}/
	# on top. Later `cp -r` wins by default, so shared files at the same
	# relative path get shadowed. No-op when the overlay directory is
	# absent (any game that has not opted into multi-platform yet).
	if [ -n "$(PLATFORM)" ] && [ -d "$(TARGET_GAME)/$(PLATFORM)/game_data" ]; then \
		cp -r $(TARGET_GAME)/$(PLATFORM)/game_data/* $(GAME_DATA_DIR)/ ; \
	fi
	if [ -n "$(PLATFORM)" ] && [ -d "$(TARGET_GAME)/$(PLATFORM)/game_src" ]; then \
		cp -r $(TARGET_GAME)/$(PLATFORM)/game_src/* $(GAME_SRC_DIR)/ ; \
	fi
	$(MYMAKE) show	# shows game name and build configuration

# A1-4 / T1-1: resolve target platform from the game's .gdata.
#   - PLATFORM directive (preferred): zx48 / zx128
#   - ZX_TARGET directive (permanent silent alias per README §5.6): 48 / 128
# A1-6: tools/detect-platform.sh layers the platform-selection rule
# (CLI override > declared default; rejection if resolved platform has
# no overlay) on top of the same lookup. T1-1 makes it emit the canonical
# platform name ('zx48' / 'zx128') consumed by `Makefile-$(_RESOLVED_PLATFORM)`.
# The legacy ZX_TARGET internal token (48/128) is derived locally and passed
# to sub-makes for backward-compat with every ZX_TARGET-keyed lookup.
_RESOLVED_PLATFORM	= $(shell ./tools/detect-platform.sh $(TARGET_GAME) $(PLATFORM) 2>/dev/null)
_DETECT_PLATFORM_RC	= $(shell ./tools/detect-platform.sh $(TARGET_GAME) $(PLATFORM) >/dev/null 2>&1; echo $$?)
_RESOLVED_ZX_TARGET	= $(patsubst zx%,%,$(_RESOLVED_PLATFORM))

# A2-1: full platform name (zx48/zx128/cpc6128/...) used to locate the
# per-platform overlay subtree under $(TARGET_GAME)/<platform>/. Mirrors
# the resolution logic in tools/detect-platform.sh but emits the canonical
# platform token instead of the internal ZX_TARGET (48/128). Honours the
# CLI override $(PLATFORM) first, then the game's declared default.
_RESOLVED_PLATFORM	= $(shell \
				if [ -n "$(PLATFORM)" ]; then \
					echo "$(PLATFORM)" | tr '[:upper:]' '[:lower:]' ; \
				else \
					grep -hE '^\s*PLATFORM\s+\w+\s*$$' $(TARGET_GAME)/game_data/game_config/*.gdata 2>/dev/null \
						| grep -vP '^\s*//' \
						| head -1 \
						| awk '{print tolower($$2)}' \
						| { read p; \
						    if [ -n "$$p" ]; then echo "$$p"; \
						    else \
						        z=$$(grep -hE '^\s*ZX_TARGET\s+(48|128)\s*$$' $(TARGET_GAME)/game_data/game_config/*.gdata 2>/dev/null \
						                | grep -vP '^\s*//' | head -1 | awk '{print $$2}') ; \
						        if [ "$$z" = "48" ]; then echo zx48 ; \
						        elif [ "$$z" = "128" ]; then echo zx128 ; \
						        fi ; \
						    fi ; \
						  } ; \
				fi)

# build: starts a build of the target game in the mode specified in the game config
build:
	if [ "$(_DETECT_PLATFORM_RC)" != "0" ]; then ./tools/detect-platform.sh $(TARGET_GAME) $(PLATFORM); exit 1; fi
	$(MYMAKE) clean
	$(MYMAKE) ZX_TARGET=$(_RESOLVED_ZX_TARGET) PLATFORM=$(_RESOLVED_PLATFORM) config
	$(MYMAKE) ZX_TARGET=$(_RESOLVED_ZX_TARGET) data
	$(MYMAKE) -f Makefile-$(_RESOLVED_PLATFORM) build

# T1-5: canonical per-platform forced-build targets.
build-zx48:
	$(MYMAKE) clean
	$(MYMAKE) ZX_TARGET=48 PLATFORM=zx48 config
	$(MYMAKE) ZX_TARGET=48 data
	$(MYMAKE) -f Makefile-zx48 build

build-zx128:
	$(MYMAKE) clean
	$(MYMAKE) ZX_TARGET=128 PLATFORM=zx128 config
	$(MYMAKE) ZX_TARGET=128 data
	$(MYMAKE) -f Makefile-zx128 build

# T1-5: legacy build48 / build128 stay as permanent silent aliases for
# build-zx48 / build-zx128 (README §5.6).
build48: build-zx48
build128: build-zx128

# T2-7: CPC464/664 flat build target (symmetric with build-zx48 / build-zx128).
# CPC664 is a runtime target of the same cpc464 build; no build-cpc664 target.
# 'data' step still uses datagen.pl with -p cpc464 (no ZX_TARGET for CPC).
build-cpc464:
	$(MYMAKE) clean
	$(MYMAKE) PLATFORM=cpc464 config
	$(MYMAKE) PLATFORM=cpc464 data-cpc464
	$(MYMAKE) -f Makefile-cpc-flat build

# T2-7: datagen invocation for CPC464 — uses -p cpc464 instead of -p zx$(ZX_TARGET).
# Only emits game_data_home.c and features.h; no banked-function machinery.
data-cpc464:
	$(DATAGEN) -p cpc464 -c -d $(GENERATED_DIR) $(GDATA_FILES) $(GDATA_PATCHES)

###############################################
##
## TARGETS FOR TEST GAME BUILDS
##
###############################################

# contains all the test games
ALL_TEST_GAMES		= $(shell cd $(TEST_GAMES_DIR)/ && ls -1 )

# T2: split the test-game matrix by platform axis.
#   CPC_TEST_GAMES — games that build for the Amstrad CPC (cpc-flat/...).
#   ZX_TEST_GAMES  — everything else (the ZX 48/128 subset).
# The split keeps CPC binary output out of the ZX pass/fail log scrape and
# lets `make all-test-builds-zx` (toolchain.md T2 phase-exit criterion) build
# ONLY the ZX games. CPC games are matched by the 'cpc-' name prefix.
CPC_TEST_GAMES		= $(filter cpc-%,$(ALL_TEST_GAMES))
ZX_TEST_GAMES		= $(filter-out cpc-%,$(ALL_TEST_GAMES))

# T2-10: CPC hello-world test game build target
build-cpc-hello:
	$(MYMAKE) build-cpc464 target_game=$(TEST_GAMES_DIR)/cpc-hello

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
	$(MYMAKE) ZX_TARGET=48 PLATFORM=zx48 config target_game=$(TEST_GAMES_DIR)/mapgen
	$(MYMAKE) ZX_TARGET=48 data
	$(MYMAKE) -f Makefile-zx48 build

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

build-minimal_jsp:
	$(MYMAKE) build target_game=$(TEST_GAMES_DIR)/minimal_jsp

build-default_jsp:
	$(MYMAKE) build target_game=$(TEST_GAMES_DIR)/default_jsp

# Phase A4: exercises the sibling-tree overlay mechanism end-to-end.
# Shared game_data/ + a zx128/ overlay that recolours the Live BTile.
build-overlay_shadow:
	$(MYMAKE) build target_game=$(TEST_GAMES_DIR)/overlay_shadow

# just a target for the default game for completeness
build-default: build

# generic rule for test builds
test-build-%:
	printf 'Building test game %.15s...' "'$*'..............."
	if ( ! $(MYMAKE) build-$* >/tmp/build-$*.log 2>&1 ) then echo " Errors - see /tmp/build-$*.log"; else echo " Build OK"; fi

# T2: ZX-only test build (toolchain.md T2 phase-exit: "make all-test-builds-zx
# (ZX subset) green"). Builds ONLY the ZX games; CPC games are excluded so
# their binary output cannot pollute the pass/fail scrape. Verdict uses
# `grep -a` (binary-safe) on a dedicated log.
all-test-builds-zx:
	echo -n "START (zx): "
	date
	$(MYMAKE) check-input-includes
	$(MYMAKE) check-input-hal
	for i in $(ZX_TEST_GAMES); do $(MYMAKE) test-build-$$i; done | tee /tmp/all-test-builds-zx.log
	echo -n "END (zx): "
	date
	if ( grep -a -i Errors /tmp/all-test-builds-zx.log ) then \
		echo "*** Some ZX tests failed ***"; \
		exit 1; \
	else \
		echo "All ZX tests succeeded"; \
		exit 0; \
	fi

# T2: CPC-only test build. Builds the CPC games (cpc-flat/...). Kept separate
# from the ZX target per toolchain.md's per-platform matrix.
all-test-builds-cpc:
	echo -n "START (cpc): "
	date
	for i in $(CPC_TEST_GAMES); do $(MYMAKE) test-build-$$i; done | tee /tmp/all-test-builds-cpc.log
	echo -n "END (cpc): "
	date
	if ( grep -a -i Errors /tmp/all-test-builds-cpc.log ) then \
		echo "*** Some CPC tests failed ***"; \
		exit 1; \
	else \
		echo "All CPC tests succeeded"; \
		exit 0; \
	fi

# Combined matrix: ZX subset then CPC subset. Each subset is scraped on its
# own dedicated log (binary-safe) so a CPC binary cannot corrupt the ZX
# verdict; the combined target fails if either subset fails.
all-test-builds:
	$(MYMAKE) all-test-builds-zx
	$(MYMAKE) all-test-builds-cpc

###############################################
##
## STATIC CHECKS (Phase IN1-3 onwards)
##
###############################################

# Phase IN1-3: guard that no NEW file under engine/banked_code/ pulls
# z88dk's <input.h> directly. Allowed exceptions are frozen in
# tools/check-input-include-guard.sh and documented in
# doc/multiplatform-plan/input-baseline-coverage.md §IN1-3.
check-input-includes:
	bash tools/check-input-include-guard.sh

# Phase IN3-5: stricter guard that no engine source outside the HAL
# allowlist (rage1/input.h, rage1/input_zx.h, engine/src/input.c)
# references any legacy z88dk-input symbol. This is the IN3-exit
# invariant — see doc/multiplatform-plan/input.md §5 Phase IN3-5.
check-input-hal:
	bash tools/check-input-hal-clean.sh

###############################################
##
## SCREENSHOT REGRESSION
##
###############################################

# Run the JNEXT-driven screenshot regression suite over every game under
# tests/00regression/. Each <game>/test.conf is built (clean + make build
# target_game=...) and compared against its checked-in reference.png.
#
# See tests/00regression/README.md for prerequisites (JNEXT binary, SD-card
# image, ImageMagick `compare`) and for the workflow to add or refresh
# baselines.
regression:
	bash tests/00regression/regression.sh

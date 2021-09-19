################################################################################
##
## RAGE1 - Retro Adventure Game Engine, release 1
## (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
## 
## This code is ublished under a GNU GPL license version 3 or later.  See
## LICENSE file in the distribution for details.
## 
################################################################################

# directory configurations
ENGINE_DIR		= engine
BUILD_DIR		= build
GENERATED_DIR		= $(BUILD_DIR)/generated
GENERATED_DIR_DATASETS	= $(GENERATED_DIR)/datasets
GENERATED_DIR_LOWMEM	= $(GENERATED_DIR)/lowmem
GAME_SRC_DIR		= $(BUILD_DIR)/game_src
GAME_DATA_DIR		= $(BUILD_DIR)/game_data

# Main sources and objs
LOWMEM_CSRC		= $(wildcard $(ENGINE_DIR)/lowmem/*.c) $(wildcard $(GENERATED_DIR_LOWMEM)/*.c)
LOWMEM_ASMSRC		= $(wildcard $(ENGINE_DIR)/lowmem/*.asm) $(wildcard $(GENERATED_DIR_LOWMEM)/*.asm)
CSRC 			= $(wildcard $(ENGINE_DIR)/src/*.c) $(wildcard $(GAME_SRC_DIR)/*.c) $(wildcard $(GENERATED_DIR)/*.c)
ASMSRC			= $(wildcard $(ENGINE_DIR)/src/*.asm) $(wildcard $(GAME_SRC_DIR)/*.asm) $(wildcard $(GENERATED_DIR)/*.asm)
SRC			= $(LOWMEM_ASMSRC) $(LOWMEM_CSRC) $(CSRC) $(ASMSRC)
OBJS			= $(LOWMEM_CSRC:.c=.o) $(LOWMEM_ASMSRC:.asm=.o) $(CSRC:.c=.o) $(ASMSRC:.asm=.o)

# Dataset sources and binaries
CSRC_DATASETS		= $(wildcard $(GENERATED_DIR_DATASETS)/*.c)
SRC_DATASETS		= $(CSRC_DATASETS)
BIN_DATASETS		= $(CSRC_DATASETS:.c=.bin)
ZX0_DATASETS		= $(BIN_DATASETS:.bin=.zx0)
DATASET_MAXSIZE		= $(shell grep BUILD_MAX_DATASET_SIZE $(GENERATED_DIR)/game_data.h | awk '{print $$3}' )

# Bank binaries and taps
BANK_BINS_FILE		= $(GENERATED_DIR)/bank_bins.cfg
BANK_BINS		= $(shell cat $(BANK_BINS_FILE) 2>/dev/null )
BANK_TAPS		= $(BANK_BINS:.bin=.tap)

# Bank switcher routine for BASIC and tap
BSWITCH_SRC		= $(ENGINE_DIR)/bank/bswitch.asm
BSWITCH_BIN		= $(GENERATED_DIR)/bswitch.bin
BSWITCH_TAP		= $(BSWITCH_BIN:.bin=.tap)

# BASIC Loader and tap
BAS_LOADER		= $(GENERATED_DIR)/loader.bas
BAS_LOADER_TAP		= $(BAS_LOADER:.bas=.tap)

# Main binary and tap
MAIN_BIN		= main.bin
MAIN_TAP		= $(MAIN_BIN:.bin=.tap)

# All taps
TAPS			= $(BANK_TAPS) $(BSWITCH_TAP) $(BAS_LOADER_TAP) $(MAIN_TAP)

# Final game TAP
FINAL_TAP		= game.tap

# the default zx target matches the one in datagen.pl when no target is defined
ZX_TARGET		= $(shell ./tools/zx_target.sh)

# compiler and tools
ZCC			= zcc
ZX0			= z88dk-zx0

# compiler flags
ZPRAGMA_INC		= zpragma-$(ZX_TARGET).inc
INC			= -I$(ENGINE_DIR)/include -I$(GENERATED_DIR)
CFLAGS			= +zx -vn -SO3 --c-code-in-asm --list -m -compiler=sdcc -clib=sdcc_iy --max-allocs-per-node200000 -pragma-include $(ZPRAGMA_INC) $(INC)
CFLAGS_TO_ASM		= -a

# generic rules
%.o: %.c
	@echo Compiling $*.c ...
	@$(ZCC) $(CFLAGS) -c $*.c

%.o: %.asm
	@echo Assembling $*.asm ...
	@$(ZCC) $(CFLAGS) -c $*.asm

# rule for inspecting generated asm code - run 'make myfile.c.asm' to
# get the .c.asm assembler generated from C file, with C code as comments
%.c.asm: %.c
	@echo Generating ASM for $*.c ...
	@$(ZCC) $(CFLAGS) $(CFLAGS_TO_ASM) -c $*.c

# build targets
.PHONY: data all build clean data_depend build-data help

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

final: $(FINAL_TAP)

build:
	@$(MAKE) -s clean
	@$(MAKE) -s config
	@$(MAKE) -s data
	@if [ "$(ZX_TARGET)" == "128" ]; then $(MAKE) -s -j8 datasets; $(MAKE) -s -j8 banks; $(MAKE) -s bank_switcher; else cp $(ENGINE_DIR)/loader48/loader.bas $(BAS_LOADER); fi
	@$(MAKE) -s -j8 main
	@$(MAKE) -s -j8 taps
	@$(MAKE) -s final

# include minimal game configuration.  If the Makefile has been copied to a
# Game directory 'make build' works as usual.  If it is the Makefile on the
# RAGE1 directory, it will include minimal-game config and allow to use it
-include minimal-game.mk

clean:
	@-rm -rf *.{lis,bin,tap,c.asm,map,log} \
		$(BUILD_DIR)/{game_src,game_data,generated} \
		$(ENGINE_DIR)/src/*.{map,lis,o,c.asm} $(ENGINE_DIR)/lowmem/*.{map,lis,o,c.asm}\
		$(GAME_SRC_DIR)/*.{map,lis,o,c.asm} \
		$(GAME_DATA_DIR)/*.{map,lis,o,c.asm} \
		2>/dev/null
clean-config:
	@-rm -rf $(GAME_SRC_DIR)/* $(GAME_DATA_DIR)/* 2>/dev/null

config:
	@$(MAKE) -s clean-config
	@-mkdir -p $(GAME_SRC_DIR)/ $(GAME_DATA_DIR)/ $(GENERATED_DIR)/ $(GENERATED_DIR_DATASETS)/ $(GENERATED_DIR_LOWMEM)/
	@cp -r game/game_data/* $(GAME_DATA_DIR)/
	@cp -r game/game_src/* $(GAME_SRC_DIR)/
	@echo "Build config: REGULAR GAME"

$(MAIN_BIN): $(OBJS)
	@echo "Bulding $(MAIN_BIN)...."
	$(ZCC) $(CFLAGS) $(INCLUDE) $(LIBDIR) $(LIBS) $(OBJS) -startup=31 -o $(MAIN_BIN)

$(FINAL_TAP): $(TAPS)
	@echo "Building final TAP $(FINAL_TAP)..."
	@if [ "$(ZX_TARGET)" == "128" ]; then cat $(BAS_LOADER_TAP) $(BSWITCH_TAP) $(BANK_TAPS) $(MAIN_TAP) > $(FINAL_TAP) ; else cat $(BAS_LOADER_TAP) $(MAIN_TAP) > $(FINAL_TAP); fi
	@echo "Build completed SUCCESSFULLY"

##
## Generated source code targets
##

$(GENERATED_DIR)/game_data_home.c: $(GENERATED_DIR)/game_data.dep
	@$(MAKE) -s data

$(GENERATED_DIR_DATASETS)/game_data_banked.c: $(GENERATED_DIR)/game_data.dep
	@$(MAKE) -s data

$(GENERATED_DIR)/game_data.dep: data_depend

data:
	@./tools/datagen.pl -c -d $(GENERATED_DIR) $(GAME_DATA_DIR)/{game_config,btiles,sprites,map,heroes,flow}/*.gdata

data_depend:
	@if [ ! -f $(GENERATED_DIR)/game_data.dep ]; then ls -1 $(GAME_DATA_DIR)/{game_config,btiles,sprites,map,heroes}/*.gdata | xargs -l stat -c '%n%Y' | sha256sum > $(GENERATED_DIR)/game_data.dep; fi
	@ls -1 $(GAME_DATA_DIR)/{game_config,btiles,sprites,map,heroes}/*.gdata | xargs -l stat -c '%n%Y' | sha256sum > /tmp/game_data.dep
	@if ( ! cmp -s $(GENERATED_DIR)/game_data.dep /tmp/game_data.dep ) then rm $(GENERATED_DIR)/game_data.dep; mv /tmp/game_data.dep $(GENERATED_DIR)/game_data.dep; fi

##
## Dataset compilation to standalone binaries org'ed at 0x5C00
##

datasets: $(ZX0_DATASETS)

dataset_%.bin: dataset_%.c
	@echo "Compiling DATASET $< ..."
	@$(ZCC) $(CFLAGS) --no-crt -o $@ $<
	@mv $(GENERATED_DIR_DATASETS)/$(shell basename $@ .bin)_code_compiler.bin $@
	@if [ $$( stat -c%s $@ ) -gt $(DATASET_MAXSIZE) ]; then echo "** ERROR: $$( basename $@ ) size is greater than $(DATASET_MAXSIZE) bytes"; exit 1; fi

dataset_%.zx0: dataset_%.bin
	@echo "Compressing DATASET $< ..."
	@$(ZX0) $< $@ >/dev/null 2>&1

## Banks

banks:
	@echo "Building Bank binaries, BASIC loader and Dataset map..."
	@./tools/r1banktool.pl -i $(GENERATED_DIR_DATASETS) -o $(GENERATED_DIR) -l $(GENERATED_DIR_LOWMEM) -b .zx0

bank_switcher: $(BSWITCH_BIN)

$(BSWITCH_BIN):
	@echo "Assembling bank switch routine..."
	@$(ZCC) $(CFLAGS) --list --no-crt $(BSWITCH_SRC) -o $(BSWITCH_BIN)

## Taps

taps: $(TAPS)

# we set org at 0xC000 for the banks
bank_%.tap: bank_%.bin
	@echo "Creating TAP $@..."
	@z88dk-appmake +zx --noloader --org 0xC000 -b $<

# we set org at 0x8184 for 128 mode, 0x5F00 for 48 mode
$(MAIN_TAP): $(MAIN_BIN)
	@echo "Creating TAP $@..."
	@if [ "$(ZX_TARGET)" == "128" ]; then z88dk-appmake +zx --noloader --org 0x8184 -b $< ; else z88dk-appmake +zx --noloader --org 0x5F00 -b $< ; fi

# we set org at 0x8000 for bank switcher
$(BSWITCH_TAP): $(BSWITCH_BIN)
	@echo "Creating TAP $@..."
	@z88dk-appmake +zx --noloader --org 0x8000 -b $<

%.tap: %.bas
	@echo "Creating TAP $@..."
	@bas2tap -sLOADER -a10 -q $<

## Main game

main: $(MAIN_BIN)

##
## Run options
##

FUSE_RUN_OPTS		= --machine $(ZX_TARGET)

run: $(FINAL_TAP)
	@fuse $(FUSE_RUN_OPTS) $(FINAL_TAP) --debugger-command ''

debug: $(FINAL_TAP)
	@fuse $(FUSE_RUN_OPTS) $(FINAL_TAP) --debugger-command "$$(cat debug_script.cfg | ./tools/r1sym.pl -m main.map )"

runz: $(FINAL_TAP)
	@../zesarux/src/zesarux $(FINAL_TAP)

##
## Tests
##

# target to build all tests
tests: test1 test2 beeptest

# individual tests

TEST1_OBJS=memory.o sp1engine.o map.o
test1: tests/test1.c $(TEST1_OBJS)
	$(ZCC) $(CFLAGS) $(INCLUDE) $(LIBDIR) $(LIBS) tests/test1.c $(TEST1_OBJS) -startup=31 -create-app -o test1.bin

TEST2_OBJS=beeper.o
test2: tests/test2.c $(TEST2_OBJS)
	$(ZCC) $(CFLAGS) $(INCLUDE) $(LIBDIR) $(LIBS) tests/test2.c $(TEST2_OBJS) -startup=31 -create-app -o test2.bin

BEEPTEST_OBJS=beeper.o
beeptest: tests/beeptest.c $(BEEPTEST_OBJS)
	$(ZCC) $(CFLAGS) $(INCLUDE) $(LIBDIR) $(LIBS) tests/beeptest.c $(BEEPTEST_OBJS) -startup=31 -create-app -o beeptest.bin

TEXTBOX_OBJS=$(OBJS)
textbox: tests/textbox.c $(TEXTBOX_OBJS)
	$(ZCC) $(CFLAGS) $(INCLUDE) $(LIBDIR) $(LIBS) tests/textbox.c $(TEXTBOX_OBJS) -startup=31 -create-app -o textbox.bin

##
## Update and sync targets for games using the library. See USAGE-OVERVIEW.md document
##

# template files and directories needed for game creation and update

# these are pure library files that will be overwritten when updating the library
# do not modify these in your game!
LIB_ENGINE_FILES	= engine tools Makefile zpragma*.inc .gitignore env.sh

# these are game data directories that will be copied from the template when creating
# a new game, but will _not_ be overwritten when updating the library. These contain
# your game!
LIB_GAME_DATA_DIRS	= minimal_game/game_data minimal_game/game_src

# needed directories that will be created empty if they do not exist
LIB_ENGINE_EMPTY_DIRS	= build/generated tests

# create a minimal game using the library
new-game:
	@if [ -z "$(target)" ]; then echo "Usage: make new-game target=<game-directory>"; exit 1; fi
	@if [ -d "$(target)" ]; then echo "Existing game directory $(target) found, use 'make update-game' instead"; exit 2; fi
	@echo "Creating game directory $(target)..."
	@mkdir -p "$(target)/game"
	@echo -n "Syncing library and game template files... "
	@rsync -ap $(LIB_ENGINE_FILES) "$(target)"
	@rsync -ap $(LIB_GAME_DATA_DIRS) "$(target)/game"
	@for i in $(LIB_ENGINE_EMPTY_DIRS); do mkdir -p "$(target)/$$i"; done
	@echo "Done!"

# update the library for an existing game
update-game:
	@if [ -z "$(target)" ]; then echo "Usage: make update-game target=<game-directory>"; exit 1; fi
	@if [ ! -d "$(target)" ]; then echo "Game directory $(target) not found, use 'make new-game' instead"; exit 2; fi
	@echo -n "Syncing library and game template files... "
	@rsync -ap --delete $(LIB_ENGINE_FILES) "$(target)"
	@-for i in $(LIB_ENGINE_EMPTY_DIRS); do mkdir -p "$(target)/$$i"; done 2>/dev/null
	@echo "Done!"

# tools
mem:
	./tools/memmap.pl main.map

linecount: clean
	find . -type f |grep -v -E '^./.git'|xargs -l file|grep -E '(ASCII|Perl)'|cut -f1 -d:|xargs -l cat|wc -l

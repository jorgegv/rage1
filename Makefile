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
GAME_SRC_DIR		= $(BUILD_DIR)/game_src
GAME_DATA_DIR		= $(BUILD_DIR)/game_data

# Main sources and objs
CSRC 		= $(wildcard $(GAME_SRC_DIR)/*.c)   $(wildcard $(ENGINE_DIR)/src/*.c)   $(wildcard $(GENERATED_DIR)/*.c)
ASMSRC		= $(wildcard $(GAME_SRC_DIR)/*.asm) $(wildcard $(ENGINE_DIR)/src/*.asm) $(wildcard $(GENERATED_DIR)/*.asm)
SRC		= $(CSRC) $(ASMSRC)
OBJS		= $(CSRC:.c=.o) $(ASMSRC:.asm=.o)

# Dataset sources and binaries
CSRC_DATASETS	= $(wildcard $(GENERATED_DIR_DATASETS)/*.c)
SRC_DATASETS	= $(CSRC_DATASETS)
BIN_DATASETS	= $(CSRC_DATASETS:.c=.bin)
DATASET_MAXSIZE	= 9472

# Bank binaries and taps
BANKS_CFG	= $(GENERATED_DIR)/banks.cfg
BANK_BINS	= $(wildcard $(GENERATED_DIR)/bank_{$(shell cat $(BANKS_CFG) 2>/dev/null )}.bin)
BANK_TAPS	= $(BANK_BINS:.bin=.tap)

# Bank switcher routine for BASIC and tap
BSWITCH_SRC	= $(ENGINE_DIR)/bank/bswitch.asm
BSWITCH_BIN	= $(GENERATED_DIR)/bswitch.bin
BSWITCH_TAP	= $(BSWITCH_BIN:.bin=.tap)

# BASIC Loader and tap
BAS_LOADER	= $(GENERATED_DIR)/loader.bas
BAS_LOADER_TAP	= $(BAS_LOADER:.bas=.tap)

# Main binary and tap
MAIN_BIN	= main.bin
MAIN_TAP	= $(MAIN_BIN:.bin=.tap)

# All taps
TAPS		= $(BANK_TAPS) $(BSWITCH_TAP) $(BAS_LOADER_TAP) $(MAIN_TAP)

# Final game TAP
FINAL_TAP	= game.tap

# compiler
ZCC		= zcc

# compiler flags
INC		= -I$(ENGINE_DIR)/include -I$(GENERATED_DIR)
CFLAGS		= +zx -vn -SO3 -m -compiler=sdcc -clib=sdcc_iy --max-allocs-per-node200000 -pragma-include zpragma.inc $(INC)
CFLAGS_TO_ASM	= -a --c-code-in-asm --list

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
	@$(MAKE) -s datasets
	@$(MAKE) -s banks
	@$(MAKE) -s bank_switcher
	@$(MAKE) -s -j8 main
	@$(MAKE) -s taps
	@$(MAKE) -s final

# include minimal game configuration.  If the Makefile has been copied to a
# Game directory 'make build' works as usual.  If it is the Makefile on the
# RAGE1 directory, it will include minimal-game config and allow to use it
-include minimal-game.mk

clean:
	@-rm -rf *.{lis,bin,tap,c.asm,map,log} \
		$(BUILD_DIR)/{game_src,game_data,generated} \
		$(ENGINE_DIR)/src/*.{map,lis,o,c.asm} \
		$(GAME_SRC_DIR)/*.{map,lis,o,c.asm} \
		$(GAME_DATA_DIR)/*.{map,lis,o,c.asm} \
		2>/dev/null
clean-config:
	@-rm -rf $(GAME_SRC_DIR)/* $(GAME_DATA_DIR)/* 2>/dev/null

config:
	@$(MAKE) -s clean-config
	@-mkdir -p $(GAME_SRC_DIR)/ $(GAME_DATA_DIR)/ $(GENERATED_DIR)/ $(GENERATED_DIR_DATASETS)/
	@cp -r game/game_data/* $(GAME_DATA_DIR)/
	@cp -r game/game_src/* $(GAME_SRC_DIR)/
	@echo "Build config: REGULAR GAME"

$(MAIN_BIN): $(OBJS)
	@echo "Bulding $(MAIN_BIN)...."
	$(ZCC) $(CFLAGS) $(INCLUDE) $(LIBDIR) $(LIBS) $(OBJS) -startup=31 -o $(MAIN_BIN)

$(FINAL_TAP): $(TAPS)
	@echo "Building final TAP $(FINAL_TAP)..."
	@cat $(BAS_LOADER_TAP) $(BSWITCH_TAP) $(BANK_TAPS) $(MAIN_TAP) > $(FINAL_TAP)
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

datasets: $(BIN_DATASETS)

dataset_%.bin: dataset_%.c
	@echo "Compiling DATASET $< ..."
	@$(ZCC) $(CFLAGS) --no-crt -o $@ $<
	@mv $(GENERATED_DIR_DATASETS)/$(shell basename $@ .bin)_code_compiler.bin $@
	@if [ $$( stat -c%s $@ ) -gt $(DATASET_MAXSIZE) ]; then echo "** ERROR: $$( basename $@ ) size is greater than $(DATASET_MAXSIZE) bytes"; exit 1; \
		else echo "  DATASET $$( basename $@ ) size is $$( stat -c%s $@ ) bytes - Fine!"; fi

## Banks

banks:
	@echo "Building bank binaries and BASIC loader..."
	@./tools/r1banktool.pl -i $(GENERATED_DIR_DATASETS) -o $(GENERATED_DIR) -b .bin

bank_switcher: $(BSWITCH_BIN)

$(BSWITCH_BIN):
	@echo "Assembling bank switch routine..."
	@$(ZCC) $(CFLAGS) --list --no-crt $(BSWITCH_SRC) -o $(BSWITCH_BIN)

## Taps

taps: $(TAPS)

# we set org at 0x0000, the real load address is set in the BASIC loader
%.tap: %.bin
	@echo "Creating TAP $@..."
	@z88dk-appmake +zx --noloader --org 0x0000 -b $<

%.tap: %.bas
	@echo "Creating TAP $@..."
	@bas2tap -sLOADER -a10 -q $<

## Main game

main: $(MAIN_BIN)

##
## Run options and target
##

FUSE_RUN_OPTS=--machine 128
run: $(FINAL_TAP)
	@fuse $(FUSE_RUN_OPTS) $(FINAL_TAP)

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
LIB_ENGINE_FILES	= engine tools Makefile zpragma.inc .gitignore env.sh

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
	./tools/memmap.pl game.map

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
ENGINE_DIR	= engine
GENERATED_DIR	= generated
GAME_SRC_DIR	= game_src

# Sources
CSRC 		= $(wildcard $(GAME_SRC_DIR)/*.c)   $(wildcard $(ENGINE_DIR)/src/*.c)   $(wildcard $(GENERATED_DIR)/*.c)
ASMSRC		= $(wildcard $(GAME_SRC_DIR)/*.asm) $(wildcard $(ENGINE_DIR)/src/*.asm) $(wildcard $(GENERATED_DIR)/*.asm)
SRC		= $(CSRC) $(ASMSRC)

# Objs:
OBJS		= $(CSRC:.c=.o) $(ASMSRC:.asm=.o)

# compiler
ZCC		= zcc

# compiler flags
INC		= -I$(ENGINE_DIR)/include -I$(GENERATED_DIR)
CFLAGS		= +zx -vn -SO3 -m -compiler=sdcc -clib=sdcc_iy --max-allocs-per-node200000 -pragma-include zpragma.inc $(INC)
CFLAGS_TO_ASM	= -a --c-code-in-asm

# generic rules
%.o: %.c
	$(ZCC) $(CFLAGS) -c $*.c

%.o: %.asm
	$(ZCC) $(CFLAGS) -c $*.asm

# rule for inspecting generated asm code - run 'make myfile.c.asm' to
# get the .c.asm assembler generated from C file, with C code as comments
%.c.asm: %.c
	$(ZCC) $(CFLAGS) $(CFLAGS_TO_ASM) -c $*.c

# build targets
.PHONY: data flow all build clean data_depend flow_depend build-data help

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

all: data_depend flow_depend game.tap

build: clean data flow
	make -j8 all

clean:
	@-rm *.{lis,bin,tap,c.asm,map,log} \
		$(GENERATED_DIR)/*.{c,h,map,lis,o,c.asm,dep,dmp} \
		$(ENGINE_DIR)/src/*.{map,lis,o,c.asm} \
		$(GAME_SRC_DIR)/*.{map,lis,o,c.asm} \
		2>/dev/null

game.tap: $(OBJS)
	$(ZCC) $(CFLAGS) $(INCLUDE) $(LIBDIR) $(LIBS) $(OBJS) -startup=31 -create-app -o game.bin

##
## Generated source code targets
##

$(GENERATED_DIR)/game_data.c: $(GENERATED_DIR)/game_data.dep
	$(MAKE) -s data

$(GENERATED_DIR)/flow_data.c: $(GENERATED_DIR)/flow_data.dep
	$(MAKE) -s flow

data:
	@./tools/datagen.pl -c -d $(GENERATED_DIR) game_data/{btiles,sprites,map,heroes,game_config}/*.gdata

flow:
	@./tools/flowgen.pl -c -d $(GENERATED_DIR) game_data/flow/*.gdata

data_depend:
	@if [ ! -f $(GENERATED_DIR)/game_data.dep ]; then ls -1 game_data/{btiles,sprites,map,heroes,game_config}/*.gdata | xargs -l stat -c '%n%Y' | sha256sum > $(GENERATED_DIR)/game_data.dep; fi
	@ls -1 game_data/{btiles,sprites,map,heroes,game_config}/*.gdata | xargs -l stat -c '%n%Y' | sha256sum > /tmp/game_data.dep
	@if ( ! cmp -s $(GENERATED_DIR)/game_data.dep /tmp/game_data.dep ) then rm $(GENERATED_DIR)/game_data.dep; mv /tmp/game_data.dep $(GENERATED_DIR)/game_data.dep; fi

flow_depend:
	@if [ ! -f $(GENERATED_DIR)/flow_data.dep ]; then ls -1 game_data/flow/*.gdata | xargs -l stat -c '%n%Y' | sha256sum > $(GENERATED_DIR)/flow_data.dep; fi
	@ls -1 game_data/flow/*.gdata | xargs -l stat -c '%n%Y' | sha256sum > /tmp/flow_data.dep
	@if ( ! cmp -s $(GENERATED_DIR)/flow_data.dep /tmp/flow_data.dep ) then rm $(GENERATED_DIR)/flow_data.dep; mv /tmp/flow_data.dep $(GENERATED_DIR)/flow_data.dep; fi

##
## Run options and target
##

FUSE_RUN_OPTS=--machine 48
run: game.tap
	@fuse $(FUSE_RUN_OPTS) game.tap

runz: game.tap
	@../zesarux/src/zesarux game.tap

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
LIB_GAME_DATA_DIRS	= game_data game_src

# needed directories that will be created empty if they do not exist
LIB_ENGINE_EMPTY_DIRS	= generated tests

# create a game using the library
new-game:
	@if [ -z "$(target)" ]; then echo "Usage: make new-game target=<game-directory>"; exit 1; fi
	@if [ -d "$(target)" ]; then echo "Existing game directory $(target) detected, use 'make update-game' instead"; exit 2; fi
	@echo "Creating game directory $(target)..."
	@mkdir -p "$(target)"
	@echo -n "Syncing library and game template files... "
	@rsync -ap $(LIB_ENGINE_FILES) "$(target)"
	@rsync -ap $(LIB_GAME_DATA_DIRS) "$(target)"
	@for i in $(LIB_ENGINE_EMPTY_DIRS); do mkdir -p "$(target)/$$i"; done
	@echo "Done!"

# update the library for an existing game
update-game:
	@if [ -z "$(target)" ]; then echo "Usage: make update-game target=<game-directory>"; exit 1; fi
	@if [ ! -d "$(target)" ]; then echo "Game directory $(target) not detected, use 'make new-game' instead"; exit 2; fi
	@echo -n "Syncing library and game template files... "
	@rsync -ap $(LIB_ENGINE_FILES) "$(target)"
	@-for i in $(LIB_ENGINE_EMPTY_DIRS); do mkdir -p "$(target)/$$i"; done 2>/dev/null
	@echo "Done!"

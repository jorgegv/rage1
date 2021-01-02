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
CSRC 		= $(wildcard $(ENGINE_DIR)/src/*.c) $(wildcard $(GENERATED_DIR)/*.c) $(wildcard $(GAME_SRC_DIR)/*.c)
ASMSRC		= $(wildcard $(ENGINE_DIR)/src/*.asm) $(wildcard $(GAME_SRC_DIR)/*.asm )
SRC		= $(CSRC) $(ASMSRC)

# Objs:
OBJS		= $(CSRC:.c=.o) $(ASMSRC:.asm=.o)

# compiler
ZCC		= zcc

# compiler flags
INC		= -I$(ENGINE_DIR)/include -I$(GENERATED_DIR)
CFLAGS		= +zx -vn -SO3 -m --list -compiler=sdcc -clib=sdcc_iy --max-allocs-per-node200000 -pragma-include zpragma.inc $(INC)
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
.PHONY: data all build clean depend build-data

all: depend game.tap

build: clean data
	make -j8 all

clean:
	@-rm *.{lis,bin,tap,c.asm,map,log} \
		$(GENERATED_DIR)/*.{c,h,map,lis,o,c.asm,dep} \
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

data:
	@./tools/datagen.pl -c -d $(GENERATED_DIR) game_data/{btiles,sprites,map,heroes,game_config}/*.gdata

depend:
	@if [ ! -f $(GENERATED_DIR)/game_data.dep ]; then ls -1 game_data/{btiles,sprites,map,heroes,game_config}/*.gdata | xargs -l stat -c '%n%Y' | sha256sum > $(GENERATED_DIR)/game_data.dep; fi
	@ls -1 game_data/{btiles,sprites,map,heroes,game_config}/*.gdata | xargs -l stat -c '%n%Y' | sha256sum > /tmp/game_data.dep
	@if ( ! cmp -s $(GENERATED_DIR)/game_data.dep /tmp/game_data.dep ) then rm $(GENERATED_DIR)/game_data.dep; mv /tmp/game_data.dep $(GENERATED_DIR)/game_data.dep; fi

##
## Run options and target
##

RUNOPTS		+= --machine 48 --rs232-rx serial.log --rs232-tx serial.log
run: game.tap
	@rm -f serial.log; touch serial.log && fuse $(RUNOPTS) game.tap

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

# Phase G4 compile-cleanly-with-uint16 test.
#
# Default target compiles tests/g4/test_xpos16.c with the host C compiler
# under strict warning flags, just to prove that the engine-style code
# patterns stay type-safe when gfx_xpos_t / gfx_ypos_t are widened to
# uint16_t on a CPC / Layer-2 backend.
#
# It does NOT link any z88dk library and does NOT produce a ZX binary;
# the test only proves the type system is consistent.

CC      ?= gcc
CFLAGS  := -std=c99 -Wall -Werror -Wconversion -Wshadow -Wno-unused-function

.PHONY: all clean

all:
	@echo "Compiling tests/g4/test_xpos16.c with -Wall -Werror -Wconversion ..."
	$(CC) $(CFLAGS) -c tests/g4/test_xpos16.c -o /dev/null
	@echo "PASS: gfx_xpos_t == uint16_t compile-clean smoke test"

clean:
	@rm -f tests/g4/*.o

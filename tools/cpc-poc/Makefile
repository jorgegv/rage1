# RAGE1 CPC R2 PoC build.
#
# Builds a CPC image with z88dk's zcc +cpc (SDCC frontend), linking the
# hand-translated cpctelera primitives from engine/src/cpc/. cpctelera itself
# is NEVER compiled here (it has no .c and z88dk's z80asm cannot assemble its
# sdas syntax) — see doc/multiplatform-plan/cpc-renderer.md §4.2 / §6.

NAME       = poc
CC         = zcc
TARGET     = +cpc
# NOTE: org MUST be >= 0x4000. drawStringM1 pages in the lower ROM (0x0000-
# 0x3FFF) to read the CPC font, which would mask any program code/data living
# below 0x4000 (z88dk's +cpc default org is 0x1200) and crash the call.
CFLAGS     = -compiler=sdcc -zorg=0x4000 -SO2 --max-allocs-per-node200000
ENGINE_CPC = ../../engine/src/cpc
ASMSRC     = $(ENGINE_CPC)/cpct_video.asm $(ENGINE_CPC)/cpct_strings_m1.asm

.PHONY: all clean

all: $(NAME).dsk

# .dsk (Caprice32-loadable) and .cdt are both emitted by appmake +cpc.
$(NAME).dsk: main.c $(ASMSRC)
	$(CC) $(TARGET) $(CFLAGS) -create-app -subtype=dsk -o $(NAME) main.c $(ASMSRC)
	$(CC) $(TARGET) $(CFLAGS) -create-app -subtype=none -o $(NAME)_tape main.c $(ASMSRC) 2>/dev/null || true

clean:
	rm -f $(NAME) $(NAME).* $(NAME)_tape* *.o $(ENGINE_CPC)/*.o

# RAGE1 CPC R2 PoC build.
#
# Builds a bootable .dsk that proves the Phase 4 R2 pipeline: z88dk +cpc links
# the hand-translated cpctelera primitives (engine/src/cpc/) and draws mode-1
# firmware-font text.  (The R3 PNG->sprite extension that once lived here used
# cpctelera's cpct_img2tileset converter, revoked and removed at R10 — see
# doc/multiplatform-plan/cpc-renderer.md §0.)

NAME         = poc
CC           = zcc
TARGET       = +cpc
# NOTE: -zorg=0x4000 is a PoC-specific workaround for the firmware-font
# lower-ROM page-in (see R2 / caprice-testing skill).  The real engine
# renders from its own charset and won't need this relocation.
CFLAGS       = -compiler=sdcc -zorg=0x4000 -SO2 --max-allocs-per-node200000
ENGINE_CPC   = ../../engine/src/cpc
ASMSRC       = $(ENGINE_CPC)/cpct_video.asm $(ENGINE_CPC)/cpct_strings_m1.asm
CSRC         = main.c

.PHONY: all clean

all: $(NAME).dsk

# .dsk (Caprice32-loadable)
$(NAME).dsk: $(CSRC) $(ASMSRC)
	$(CC) $(TARGET) $(CFLAGS) -create-app -subtype=dsk -o $(NAME) \
	    $(CSRC) $(ASMSRC)
	$(CC) $(TARGET) $(CFLAGS) -create-app -subtype=none -o $(NAME)_tape \
	    $(CSRC) $(ASMSRC) 2>/dev/null || true

clean:
	rm -f $(NAME) $(NAME).* $(NAME)_tape* *.o $(ENGINE_CPC)/*.o

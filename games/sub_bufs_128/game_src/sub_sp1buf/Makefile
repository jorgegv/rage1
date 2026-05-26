# This Makefile must always offer the target "sub_bin" which is used by the
# main Makefiles and the loadertool

.SILENT:

.PHONY: clean sub_bin sub_tap sub_tap_nohdr

SUB_BIN = sub.bin
SUB_SRC = main.asm main.c

# DATASET buffer address
ORG = 0xD1ED

# T1-7: route z88dk target through $(ZCC_TARGET) / $(APPMAKE).
ZCC_TARGET = +zx
APPMAKE    = z88dk-appmake $(ZCC_TARGET)
BIN_CMD = zcc $(ZCC_TARGET) -Wno-incompatible-pointer-types -zorg=$(ORG) -Ca -D__ORG=$(ORG) -m --list --c-code-in-asm --no-crt -o $(SUB_BIN)

# binary-only generation, used for getting exact size
sub_bin:
	$(BIN_CMD) $(SUB_SRC)

# full tap generation with loader, useful for testing
sub_tap: sub_bin
	$(APPMAKE) -b sub.bin --org $(ORG)

clean:
	-rm -f sub* *.c.lis *.map *.lis

run: sub_tap
	fuse sub.tap

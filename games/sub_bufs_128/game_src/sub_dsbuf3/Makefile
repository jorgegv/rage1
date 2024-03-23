# This Makefile must always offer the target "sub_bin" which is used by the
# main Makefiles and the loadertool

.SILENT:

.PHONY: clean sub_bin sub_tap sub_tap_nohdr

SUB_BIN = sub.bin
SUB_SRC = main.asm main.c

# DATASET buffer address
ORG = 0xD200

BIN_CMD = zcc +zx -Wno-incompatible-pointer-types -zorg=$(ORG) -Ca -D__ORG=$(ORG) -m --list --c-code-in-asm --no-crt -o $(SUB_BIN)
ZX0	= z88dk-zx0 -f

# binary-only generation, used for getting exact size
# generate also the compressed binary
sub_bin:
	$(BIN_CMD) $(SUB_SRC)
	$(ZX0) $(SUB_BIN)

# full tap generation with loader, useful for testing
sub_tap: sub_bin
	z88dk-appmake +zx -b sub.bin --org $(ORG)

clean:
	-rm -f sub* *.c.lis *.map *.lis

run: sub_tap
	fuse sub.tap

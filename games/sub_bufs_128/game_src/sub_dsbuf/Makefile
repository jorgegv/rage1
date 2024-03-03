# This Makefile must always offer the targets "sub_bin" and "sub_bin_nohdr",
# which are used by the main Makefiles

.SILENT:

.PHONY: clean sub_bin sub_tap sub_tap_nohdr


# DATASET buffer address
ORG = 0x5B00

BIN_CMD = zcc +zx -zorg=$(ORG) -o sub.bin main.c -pragma-redirect=CRT_FONT=_font_8x8_bbc_system

# binary-only generation, used for getting exact size
sub_bin:
	$(BIN_CMD)

# full tap generation with loader, useful for testing
sub_tap:
	$(BIN_CMD) -create-app

# reduced tap, loaderless and headerless, used by the RAGE1 loader
sub_tap_nohdr:
	$(BIN_CMD) -create-app -Cz --noloader -Cz --noheader

clean:
	-rm -f sub*

run: sub_tap
	fuse sub.tap

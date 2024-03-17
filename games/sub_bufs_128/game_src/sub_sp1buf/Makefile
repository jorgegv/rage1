# This Makefile must always offer the target "sub_bin" which is used by the
# main Makefiles and the loadertool

.SILENT:

.PHONY: clean sub_bin sub_tap sub_tap_nohdr

SUB_BIN = sub.bin
SUB_SRC = main.c

# SP1 buffer address
ORG = 0xD1ED

BIN_CMD = zcc +zx -zorg=$(ORG) -o $(SUB_BIN) -pragma-redirect=CRT_FONT=_font_8x8_bbc_system

# binary-only generation, used for getting exact size
sub_bin:
	$(BIN_CMD) $(SUB_SRC)

# full tap generation with loader, useful for testing
sub_tap:
	$(BIN_CMD) $(SUB_SRC) -create-app

clean:
	-rm -f sub*

run: sub_tap
	fuse sub.tap

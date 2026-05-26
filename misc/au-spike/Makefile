# misc/au-spike/Makefile — Phase AU1-3 spike
#
# Assembles the Arkos2 AKG player source twice — once with
# PLY_AKG_HARDWARE_SPECTRUM defined, once with PLY_AKG_HARDWARE_CPC defined —
# to confirm that a SINGLE Arkos2 player source can target both backends
# under the project's existing assembler toolchain.
#
# This is a standalone spike — no engine link, no z88dk C glue.

RASM     ?= /home/jorgegv/src/spectrum/rasm/rasm.exe

# Default: build both targets and summarise
.PHONY: all spike clean
all: spike

spike: spike_zx.bin spike_cpc.bin
	@echo
	@echo "=== AU1-3 dual-target spike — sizes ==="
	@ls -l spike_zx.bin spike_cpc.bin
	@echo
	@echo "ZX vs CPC byte delta (CPC is typically slightly larger):"
	@printf "  zx   : %s bytes\n" "$$(stat -c%s spike_zx.bin)"
	@printf "  cpc  : %s bytes\n" "$$(stat -c%s spike_cpc.bin)"
	@printf "  diff : %s bytes\n" "$$(($$(stat -c%s spike_cpc.bin) - $$(stat -c%s spike_zx.bin)))"

spike_zx.bin: spike_zx.asm PlayerAkg.asm PlayerAkg_SoundEffects.asm
	$(RASM) spike_zx.asm -o spike_zx -s -sl -sq

spike_cpc.bin: spike_cpc.asm PlayerAkg.asm PlayerAkg_SoundEffects.asm
	$(RASM) spike_cpc.asm -o spike_cpc -s -sl -sq

clean:
	@-rm -f spike_zx.bin spike_zx.sym spike_cpc.bin spike_cpc.sym

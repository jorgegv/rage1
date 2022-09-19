RASM	= ~/src/spectrum/rasm/rasm.exe
DISARK	= '/home/jorgegv/src/spectrum/arkos/Arkos Tracker 2/tools/Disark'
FINAL_ASM = asm_arkos2.asm

.PHONY: convert

convert:
	$(RASM) PlayerAkg.asm -o AT2Player -s -sl -sq
	$(DISARK) AT2Player.bin $(FINAL_ASM) --symbolFile AT2Player.sym --sourceProfile pasmo
	cp $(FINAL_ASM) $(FINAL_ASM).save
	./convert-arkos-source.pl $(FINAL_ASM)
	zcc +zx -vn -m -s -l -compiler=sdcc -clib=sdcc_iy -create-app $(FINAL_ASM) arkos2_c_stubs_simple.asm hocuspocus.asm main.c -o arkos

clean:
	@-rm *.bin *.tap *.o *.sym $(FINAL_ASM) *.map *.save arkos

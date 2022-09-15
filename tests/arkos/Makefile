RASM	= ~/src/spectrum/rasm/rasm.exe
DISARK	= '/home/jorgegv/src/spectrum/arkos/Arkos Tracker 2/tools/Disark'
FINAL_ASM = arkos2.asm

.PHONY: comvert

convert:
	$(RASM) PlayerAkg.asm -o AT2Player -s -sl -sq
	$(DISARK) AT2Player.bin $(FINAL_ASM) --symbolFile AT2Player.sym --sourceProfile pasmo
	./convert-arkos-source.pl $(FINAL_ASM)
	zcc +zx --nocrt -c $(FINAL_ASM)

clean:
	@-rm *.bin *.tap *.o *.sym $(FINAL_ASM)


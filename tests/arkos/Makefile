RASM	= ~/src/spectrum/rasm/rasm.exe
DISARK	= '/home/jorgegv/src/spectrum/arkos/Arkos Tracker 2/tools/Disark'

.PHONY: comvert

convert:
	$(RASM) PlayerAkg.asm -o AT2Player -s -sl -sq
	$(DISARK) AT2Player.bin Final.asm --symbolFile AT2Player.sym --sourceProfile pasmo
	dos2unix Final.asm
	./convert-arkos-source.pl Final.asm > perltmp
	mv perltmp Final.asm
	zcc +zx --nocrt -c Final.asm

clean:
	@-rm *.bin *.tap *.o *.sym Final.asm

RASM = /home/jorgegv/src/spectrum/rasm/rasm.exe
PASMO = /home/jorgegv/src/spectrum/pasmo/pasmo
Z80ASM = z88dk-z80asm
PASMO2Z88DK = ../../../tools/pasmo-to-z88dk.pl
DISARK = '/home/jorgegv/src/spectrum/arkos/Arkos Tracker 2/tools/Disark'

test: test-song test-player
	@echo "3 files with the same hash should be shown below:"
	@sha1sum output-song-*.bin
	@echo "3 files with the same hash should be shown below:"
	@sha1sum output-player*.bin

test-song:
	$(RASM) hocuspocus.asm -o output-song-rasm
	$(PASMO) hocuspocus.asm output-song-pasmo.bin 2>/dev/null
	$(PASMO2Z88DK) hocuspocus.asm > converted.asm
	$(Z80ASM) -l -mz80 -b -ooutput-song-z80asm.bin converted.asm
	for i in rasm pasmo z80asm; do od -A x -tx1 output-song-$$i.bin > output-song-$$i.hex ; done

test-player:
	$(RASM) PlayerAkg.asm -o output-player-rasm
	$(RASM) PlayerAkg.asm -o AT2Player -s -sl -sq
	$(DISARK) AT2Player.bin PlayerAkg_pasmo.asm --symbolFile AT2Player.sym --sourceProfile pasmo
	$(PASMO) PlayerAkg_pasmo.asm output-player-pasmo.bin 2>/dev/null
	$(PASMO2Z88DK) PlayerAkg_pasmo.asm > converted.asm
	$(Z80ASM) -l -mz80 -b -ooutput-player-z80asm.bin converted.asm
	for i in rasm pasmo z80asm; do od -A x -tx1 output-player-$$i.bin > output-player-$$i.hex ; done

clean:
	@-rm -f *.o *.bin *.sym *.hex *.lis PlayerAkg_pasmo.asm converted.asm

# This Makefile automates the generation of the Z88Dk version of Arkos
# Tracker 2 AKG player using only the original Arkos 2 package.
#
# The player is included in RAGE1, already generated and ready for use under
# the engine/banked/128 directory; these recipes are provided to make it
# easy to update it when new versions of Arkos player appear

# adjust these as needed
RASM			= /home/jorgegv/src/spectrum/rasm/rasm.exe
PASMO			= /home/jorgegv/src/spectrum/pasmo/pasmo
ARKOS_DIR		= '/home/jorgegv/src/spectrum/arkos/Arkos Tracker 2'

# no more config needed below here
Z80ASM			= z88dk-z80asm
PASMO2Z88DK 		= ../../tools/pasmo-to-z88dk.pl
DISARK			= $(ARKOS_DIR)/tools/Disark
PLAYER_SRC_DIR		= $(ARKOS_DIR)/players/playerAkg/sources
PLAYER_ASM		= PlayerAkg.asm
CONF_PLAYER_ASM		= PlayerAkg-configured.asm
RAGE1_PLAYER_ASM	= arkos2-player.asm

.PHONY: update

update:
	make -s clean
	make -s arkos2-player.asm

$(RAGE1_PLAYER_ASM):
	cp $(PLAYER_SRC_DIR)/*.asm .
	( echo "PLY_AKG_HARDWARE_SPECTRUM = 1" && \
	echo "PLY_AKG_MANAGE_SOUND_EFFECTS = 1" && \
	cat $(PLAYER_ASM) ) > $(CONF_PLAYER_ASM)
	$(RASM) $(CONF_PLAYER_ASM) -o AT2Player -s -sl -sq
	$(DISARK) AT2Player.bin AT2Player.asm --symbolFile AT2Player.sym --sourceProfile pasmo
	echo "section code_compiler" > $(RAGE1_PLAYER_ASM)
	$(PASMO2Z88DK) AT2Player.asm >> $(RAGE1_PLAYER_ASM)
	perl -e 'print join("\n", map { "public PLY_AKG_$$_" } qw( INIT STOP PLAY INITSOUNDEFFECTS PLAYSOUNDEFFECT ) ),"\n";' >>$(RAGE1_PLAYER_ASM)
	echo "New Arkos Player generated, file: $(RAGE1_PLAYER_ASM)"

clean:
	@-rm -f *.o *.bin *.sym *.hex *.lis PlayerAkg* AT2Player.asm $(CONF_PLAYER_ASM) $(RAGE1_PLAYER_ASM)

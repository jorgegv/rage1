# configure these if needed
RASM	= ~/src/spectrum/rasm/rasm.exe
DISARK	= '/home/jorgegv/src/spectrum/arkos/Arkos Tracker 2/tools/Disark'
PASMO2Z88DK = ../../../tools/pasmo-to-z88dk.pl

# intermediate files
PASMO_ASM = pasmo_arkos2.asm
Z88DK_ASM = z88dk_arkos2.asm
ARKOS_ASM = asm_arkos2.asm
ARKOS_OBJ = $(ARKOS_ASM:.asm=.o)

# song files
SONG_ASM = song.asm
CONVSONG_ASM = converted_song.asm
CONVSONG_OBJ =$(CONVSONG_ASM:.asm=.o)

# main target objs
#MAIN_OBJS = main.o arkos2_c_stubs.o $(CONVSONG_OBJ) $(ARKOS_OBJ)
MAIN_OBJS = main.o arkos2_c_stubs_simple.o $(CONVSONG_OBJ) $(ARKOS_OBJ)

# targets
.PHONY: build clean

build: $(MAIN_OBJS)
	zcc +zx -vn -m -s --list -compiler=sdcc -clib=sdcc_iy -create-app -o arkos $(MAIN_OBJS)

# convert Arkos RASM player to relocatable Z88DK asm player
# reference: "Source conversion with Disark" article:
# https://www.julien-nevo.com/arkostracker/index.php/source-conversion-with-disark/
$(ARKOS_ASM): PlayerAkg.asm PlayerAkg_SoundEffects.asm
	$(RASM) PlayerAkg.asm -o AT2Player -s -sl -sq
	$(DISARK) AT2Player.bin $(PASMO_ASM) --symbolFile AT2Player.sym --sourceProfile pasmo
	$(PASMO2Z88DK) $(PASMO_ASM) > $(Z88DK_ASM)
	echo "section code_compiler" > $(ARKOS_ASM)
	cat $(Z88DK_ASM) >> $(ARKOS_ASM)
	perl -e 'print join("\n", map { "public PLY_AKG_$$_" } qw( INIT STOP PLAY INITSOUNDEFFECTS PLAYSOUNDEFFECT ) );' >>$(ARKOS_ASM)

$(CONVSONG_ASM): $(SONG_ASM)
	echo "section code_compiler"		> $(CONVSONG_ASM)
	echo -e "PUBLIC _song\n\n_song:\n\n"	>> $(CONVSONG_ASM)
	cat $(SONG_ASM) 			>> $(CONVSONG_ASM)
	dos2unix $(CONVSONG_ASM)

%.o: %.c
	zcc +zx -vn -c -s --list -compiler=sdcc -clib=sdcc_iy $*.c

%.o: %.asm
	zcc +zx -vn -c -s --list -compiler=sdcc -clib=sdcc_iy $*.asm

clean:
	@-rm *.lis *.bin *.tap *.o *.sym $(ARKOS_ASM) $(PASMO_ASM) $(Z88DK_ASM) $(CONVSONG_ASM) *.map *.save arkos 2>/dev/null

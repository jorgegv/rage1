# common flags
CFLAGS 			= --list -s -m --c-code-in-asm

# special cases
CFLAGS_SCCZ80_CLASSIC 	= 
CFLAGS_SDCC_CLASSIC 	= -compiler=sdcc
CFLAGS_SCCZ80_NEW 	= -clib=new
CFLAGS_SDCC_NEW 	= -compiler=sdcc -clib=sdcc_iy

all: sccz80_classic sdcc_classic sccz80_new sdcc_new

sccz80_classic: clean
	zcc +zx -vn -c $(CFLAGS) $(CFLAGS_SCCZ80_CLASSIC) main.c
	zcc +zx -vn -c $(CFLAGS) $(CFLAGS_SCCZ80_CLASSIC) bank6.c
	zcc +zx -vn $(CFLAGS) $(CFLAGS_SCCZ80_CLASSIC) main.o bank6.o -lndos -create-app -o banked.bin
	-mkdir -p out/sccz80-classic
	-rm out/sccz80-classic/*
	-cp -f * out/sccz80-classic

sdcc_classic: clean
	zcc +zx -vn -c $(CFLAGS) $(CFLAGS_SDCC_CLASSIC) main.c
	zcc +zx -vn -c $(CFLAGS) $(CFLAGS_SDCC_CLASSIC) bank6.c
	zcc +zx -vn $(CFLAGS) $(CFLAGS_SDCC_CLASSIC) main.o bank6.o -lndos -create-app -o banked.bin
	-mkdir -p out/sdcc-classic
	-rm out/sdcc-classic/*
	-cp -f * out/sdcc-classic

sccz80_new: clean
	zcc +zx -vn -c $(CFLAGS) $(CFLAGS_SCCZ80_NEW) main.c
	zcc +zx -vn -c $(CFLAGS) $(CFLAGS_SCCZ80_NEW) bank6.c
	zcc +zx -vn $(CFLAGS) $(CFLAGS_SCCZ80_NEW) main.o bank6.o -create-app -o banked.bin
	-mkdir -p out/sccz80-new
	-rm out/sccz80-new/*
	-cp -f * out/sccz80-new

sdcc_new: clean
	zcc +zx -vn -c $(CFLAGS) $(CFLAGS_SDCC_NEW) main.c
	zcc +zx -vn -c $(CFLAGS) $(CFLAGS_SDCC_NEW) bank6.c
	zcc +zx -vn $(CFLAGS) $(CFLAGS_SDCC_NEW) main.o bank6.o -create-app -o banked.bin
	-mkdir -p out/sdcc-new
	-rm out/sdcc-new/*
	-cp -f * out/sdcc-new

clean:
	-rm -rf *.o *.c.asm *.lis *.map *.sym *.bin *.tap out

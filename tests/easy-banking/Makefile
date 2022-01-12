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
	-mkdir sccz80-classic
	-rm sccz80-classic/*
	-cp -f * sccz80-classic

sdcc_classic: clean
	zcc +zx -vn -c $(CFLAGS) $(CFLAGS_SDCC_CLASSIC) main.c
	zcc +zx -vn -c $(CFLAGS) $(CFLAGS_SDCC_CLASSIC) bank6.c
	zcc +zx -vn $(CFLAGS) $(CFLAGS_SDCC_CLASSIC) main.o bank6.o -lndos -create-app -o banked.bin
	-mkdir sdcc-classic
	-rm sdcc-classic/*
	-cp -f * sdcc-classic

sccz80_new: clean
	zcc +zx -vn -c $(CFLAGS) $(CFLAGS_SCCZ80_NEW) main.c
	zcc +zx -vn -c $(CFLAGS) $(CFLAGS_SCCZ80_NEW) bank6.c
	zcc +zx -vn $(CFLAGS) $(CFLAGS_SCCZ80_NEW) main.o bank6.o -create-app -o banked.bin
	-mkdir sccz80-new
	-rm sccz80-new/*
	-cp -f * sccz80-new

sdcc_new: clean
	zcc +zx -vn -c $(CFLAGS) $(CFLAGS_SDCC_NEW) main.c
	zcc +zx -vn -c $(CFLAGS) $(CFLAGS_SDCC_NEW) bank6.c
	zcc +zx -vn $(CFLAGS) $(CFLAGS_SDCC_NEW) main.o bank6.o -create-app -o banked.bin
	-mkdir sdcc-new
	-rm sdcc-new/*
	-cp -f * sdcc-new

clean:
	-rm *.o *.c.asm *.lis *.map *.sym *.bin *.tap

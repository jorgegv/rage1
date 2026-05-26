# T1-7: dev fixture — route z88dk target through $(ZCC_TARGET) / $(APPMAKE).
ZCC_TARGET = +zx
APPMAKE    = z88dk-appmake $(ZCC_TARGET)

all: all.tap

clean:
	-rm *.tap *.o *.bin

bank3.tap:
	zcc $(ZCC_TARGET) -compiler=sdcc -clib=sdcc_iy --no-crt -o bank3 bank3.c
	$(APPMAKE) --org 0xC000  --noloader -b bank3_code_compiler.bin -o bank3.tap

main.tap:
	zcc $(ZCC_TARGET) -compiler=sdcc -clib=sdcc_iy -create-app -o main main.c

all.tap: main.tap bank3.tap
	cat main.tap bank3.tap >> all.tap

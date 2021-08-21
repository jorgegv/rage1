all: all.tap

clean:
	-rm *.tap *.o *.bin

bank3.tap:
	zcc +zx -compiler=sdcc -clib=sdcc_iy --no-crt -o bank3 bank3.c
	z88dk-appmake +zx --org 0xC000  --noloader -b bank3_code_compiler.bin -o bank3.tap

main.tap:
	zcc +zx -compiler=sdcc -clib=sdcc_iy -create-app -o main main.c

all.tap: main.tap bank3.tap
	cat main.tap bank3.tap >> all.tap

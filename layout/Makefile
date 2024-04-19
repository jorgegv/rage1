run: clean
	zcc +zx -clib=sdcc_iy -I../engine/include -I../build/generated layout.c -o layout -create-app
	./run_and_kill.sh
	dos2unix output.txt

clean:
	-rm *.tap *.bin output.txt layout

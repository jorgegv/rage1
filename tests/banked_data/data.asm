;; Compile with:
;;
;;   zcc +zx -vn -SO3 -m -compiler=sdcc -clib=sdcc_iy --max-allocs-per-node200000 --no-crt data.asm -o data.bin
;;
;; Dump binary in hex with:
;;
;;   od -tx1 data.bin
;;
;; This data should be compiled to base address 5B00, so that when it's
;; decompressed to that address everything works OK

	org	0x5b00

my_data_ptr:	dw	d1		;; this should contain 0x5B02
d1:		db	1, 2
		dw	0x3456
d2:		db	7, 8
		dw	0x9012
my_data_ptr2:	dq	d2		;; this should contain 0x5B06

;; binary dump of the generated data file should be these 12 bytes, in order:
;; 02 5B 01 02 56 34 07 08 12 90 06 5B

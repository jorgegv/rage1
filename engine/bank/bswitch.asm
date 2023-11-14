;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; RAGE1 - Retro Adventure Game Engine, release 1
;; (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
;; 
;; This code is published under a GNU GPL license version 3 or later.  See
;; LICENSE file in the distribution for details.
;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; minimal bank switching routine for use in program loader

;; org address is not relevant, the whole routine just needs to be below
;; 0xC000.  When the last bank is loaded, this loader will be overwritten by
;; the main load (banks 5,2,0)

		org	0x8000

; BASIC will put here the bank number to activate
bank_num:	db	0	; addr: ORG

; ...and call here
bswitch:	ld	a,(bank_num)	; get desired new bank from BASIC
		and	0x07		; get 3 low bits only
		ld	b,a		; save for later
		ld	a,(0x5b5c)	; get last value from SYS.BANKM
		and	0xf8		; save 5 top bits
		or	b		; mix new value with old
		ld	bc,0x7ffd	; set the port number
		di			; atomically...
		ld	(0x5b5c),a	; ...store the new value to SYS.BANKM
		out	(c),a		; ...and select the new bank
		ei			; end atomic section
		ret			; back to BASIC

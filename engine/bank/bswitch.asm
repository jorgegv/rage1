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

		org	0x8000

; BASIC will put here the bank number to activate
bank:		db	0	; addr: ORG

; ...and call here
bswitch:	ld	a,(0x5b5c)	; get last value from BANKM (SYSVARS)
		and	0xf8		; save 5 top bits
		ld	b,a		; save for later
		ld	a,(bank)	; get new bank from BASIC
		and	0x08		; get 3 low bits only
		or	b		; mix new value with old
		ld	bc,0x7ffd	; set the port number
		di			; atomically...
		ld	(0x5b5c),a	; ...store the new value to BANKM
		out	(c),a		; ...and select the new bank
		ei			; end atomic section
		ret			; back to BASIC

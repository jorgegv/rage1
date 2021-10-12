;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; RAGE1 - Retro Adventure Game Engine, release 1
;; (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
;; 
;; This code is published under a GNU GPL license version 3 or later.  See
;; LICENSE file in the distribution for details.
;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; This file contains data that needs to be in low memory at all times, so
;; it is placed in the code_crt_common section

section		code_crt_common

;;
;; Data follows
;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Timekeeping structure, updated via interrupts. Declared in interrupts.h
;;
;; extern struct time_s current_time;
;;

public		_current_time

_current_time:

hour:		db	0
min:		db	0
sec:		db	0
frame:		db	0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Global structs that hold the current banked and home asset tables.  They
;; must go in low memory, so they are instead included in
;; lowmem/asmdata.asm.  Declaration in dataset.h
;;
;; extern struct dataset_assets_s *banked_assets;
;; extern struct dataset_assets_s *home_assets;
;;

public		_banked_assets
_banked_assets:
		dw	0

public		_home_assets
_home_assets:
		dw	0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Global pointer for the codeset assets.  It must go in low memory, so it
;; is instead included in lowmem/asmdata.asm.  Declaration in codeset.h
;;
;; extern struct codeset_assets_s *codeset_assets;
;;

public		_codeset_assets
_codeset_assets:
		dw	0

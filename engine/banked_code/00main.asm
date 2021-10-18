;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; RAGE1 - Retro Adventure Game Engine, release 1
;; (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
;; 
;; This code is published under a GNU GPL license version 3 or later.  See
;; LICENSE file in the distribution for details.
;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


	section	code_compiler
	org	0xC000

public	_all_banked_functions
public	_banked_function_args

extern	_sound_play_pending_fx

;; 0xC000 (offset 0): banked_args - pointer to struct banked_function_args_s
;; initialized at startup by init_memory
_banked_function_args:
	dw	0

;; 0xC002 (offset 2): banked functions table
_all_banked_functions:
	;; index 0
	dw	_sound_play_pending_fx
	
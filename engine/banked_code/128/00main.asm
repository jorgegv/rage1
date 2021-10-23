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

extern	_sound_play_pending_fx
extern	_hero_animate_and_move

;;
;; 0xC000: banked functions table
;;
_all_banked_functions:
	dw	_sound_play_pending_fx		;; index 0
	dw	_hero_animate_and_move		;; index 1

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
extern	_enemy_animate_and_move_all
extern	_bullet_animate_and_move_all
extern	_bullet_add
extern	_init_tracker
extern	_tracker_select_song
extern	_tracker_start
extern	_tracker_stop
extern	_tracker_do_periodic_tasks
extern	_init_tracker_sound_effects
extern	_tracker_play_fx

;;
;; 0xC000: banked functions table
;;
_all_banked_functions:
	dw	_sound_play_pending_fx		;; index 0
	dw	_hero_animate_and_move		;; index 1
	dw	_enemy_animate_and_move_all	;; index 2
	dw	_bullet_animate_and_move_all	;; index 3
	dw	_bullet_add			;; index 4
	dw	_init_tracker			;; index 5
	dw	_tracker_select_song		;; index 6
	dw	_tracker_start			;; index 7
	dw	_tracker_stop			;; index 8
	dw	_tracker_do_periodic_tasks	;; index 9
	dw	_init_tracker_sound_effects	;; index 10
	dw	_tracker_play_fx		;; index 11

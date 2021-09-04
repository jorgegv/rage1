;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; RAGE1 - Retro Adventure Game Engine, release 1
;; (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
;; 
;; This code is published under a GNU GPL license version 3 or later.  See
;; LICENSE file in the distribution for details.
;; 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; This file contains data that needs to be in low memory at all times. It
;; is placed in the code_crt_common section for thi reason

section		code_crt_common

;;
;; Data follows
;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Timekeeping structure, updated via interrupts. Declared in interrupts.h
;;
;; struct time_s {
;;    uint8_t hour, min, sec, frame;
;; };
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
;; Global struct that holds the current assets table.  This must go in low
;; memory, so it is instead included in lowmem/asmdata.asm
;; struct dataset_assets_s {
;;     // BTiles
;;     uint8_t                             num_btiles;
;;     struct btile_s                      *all_btiles;
;;     // Sprites
;;     uint8_t                             num_sprite_graphics;
;;     struct sprite_graphic_data_s        *all_sprite_graphics;
;;     // Flow rules
;;     // FIXME: this needs to be upgraded to a 16 bit number - we can easily have more than 255 rules in a game
;;     uint8_t                             num_flow_rules;
;;     struct flow_rule_s                  *all_flow_rules;
;;     // Map
;;     uint8_t                             num_screens;
;;     struct map_screen_s                 *all_screens;
;; };
;; extern struct dataset_assets_s current_assets;

public		_current_assets

_current_assets:
num_btiles:		db	0
all_btiles:		dw	0
num_sprite_graphics:	db	0
all_sprite_graphics:	dw	0
num_flow_rules:		db	0
all_flow_rules:		dw	0
num_screens:		db	0
all_screens:		dw	0

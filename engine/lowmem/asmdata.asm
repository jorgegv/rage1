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

;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
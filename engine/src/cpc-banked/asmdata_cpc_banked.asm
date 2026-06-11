;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; RAGE1 - Retro Adventure Game Engine, release 1
;; (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
;;
;; This code is published under a GNU GPL license version 3 or later.  See
;; LICENSE file in the distribution for details.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; B7 step 9.4: cpc-banked LOWMEM discipline.
;;
;; The engine's swap-active globals (the bank-state variable, the interrupt
;; interlock, the timekeeping struct written by the 50 Hz ISR, and the
;; renderer / codeset asset pointers) MUST stay mapped whenever a dataset or
;; codeset bank is paged into the 0x4000-0x7FFF Gate-Array swap window (page
;; B).  The CPC GA can only rotate RAM4-7 through 0x4000-0x7FFF; page A
;; (0x0000-0x3FFF, RAM0) stays fixed, so these globals must live below 0x4000.
;;
;; They are hand-placed here in the `code_crt_common` section, which the
;; cpc-banked custom linker map (mmap-cpc-banked.inc) orders EARLY in SECTION
;; CODE (right after the CRT init sections), so it lands in page A below
;; 0x4000.  This mirrors engine/src/00asmdata.asm on ZX 128 (where
;; code_crt_common is low-memory by the ZX CRT model), but is cpc-banked-only:
;; it is linked exclusively by the Makefile-cpc-banked CPC_LINK_ENGINE_FULL
;; path and is NOT under engine/src/cpc/*.asm, so it never leaks into the
;; cpc-flat (CPC464) build (where these globals are plain C BSS defined by
;; engine/src/cpc/asmdata_cpc.c).
;;
;; The symbols, types and zero-seed are byte-for-byte what the shared engine
;; expects (declared in interrupts.h / dataset.h / codeset.h / memory.h).

section		code_crt_common

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Timekeeping structure, updated via the CPC IM1 ISR. Declared in interrupts.h
;;
;; extern struct time_s current_time;
;;

public		_current_time
_current_time:
hour:		db	0
min:		db	0
sec:		db	0
frame:		db	0
ticks:		dq	0	;; 32-bit

;; extern uint8_t periodic_tasks_enabled;

public		_periodic_tasks_enabled
_periodic_tasks_enabled:
		db	0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Global structs that hold the current banked and home asset tables.
;; Declaration in dataset.h
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
;; Global pointer for the codeset assets.  Declaration in codeset.h
;;
;; extern struct codeset_assets_s *codeset_assets;
;;

public		_codeset_assets
_codeset_assets:
		dw	0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Global interrupt nesting counter (the bank-switch interlock).  Declaration
;; in interrupts.h
;;
;; extern uint8_t interrupt_nesting_level;
;;

public		_interrupt_nesting_level
_interrupt_nesting_level:
		db	0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Currently-mapped memory bank.  Written by memory_switch_bank() (00bswitch.c)
;; AFTER the Gate-Array RAMR `out`, so it MUST stay mapped across the bank
;; switch — i.e. live in page A.  On ZX 128 this is a plain C BSS global in
;; 00bswitch.c (bss_compiler, low by the ZX CRT model); on cpc-banked the C
;; definition is compiled out and this asm definition is used instead.
;; Declaration in memory.h
;;
;; extern uint8_t memory_current_memory_bank;
;;

public		_memory_current_memory_bank
_memory_current_memory_bank:
		db	0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; CPC IM1 ISR state (rage1_cpc_isr.asm).  BOTH must be page-A low: the ISR
;; reads/writes the counter on EVERY interrupt — including ticks that fire while a
;; dataset bank is paged into 0x4000-0x7FFF — and tests/sets the reentrancy guard
;; there too.  Declared in interrupts.h.
;;
;; extern uint8_t cpc_isr_div_counter;   // divide-by-six counter / sub-frame index (0..5)
;; extern uint8_t isr_busy;              // 1-bit 50 Hz-body reentrancy guard
;;

public		_cpc_isr_div_counter
_cpc_isr_div_counter:
		db	0

public		_isr_busy
_isr_busy:
		db	0

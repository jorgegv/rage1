;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; RAGE1 - Retro Adventure Game Engine, release 1
;; (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
;;
;; This code is published under a GNU GPL license version 3 or later.  See
;; LICENSE file in the distribution for details.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; cpc-banked PLACEMENT WRAPPER for the shared RAGE1-owned IM1 handler.
;;
;; The handler code itself is shared with cpc-flat in
;; engine/src/cpc/rage1_cpc_isr_body.inc (full design rationale there and in
;; doc/multiplatform-plan/cpc-interrupts.md).  This wrapper only fixes its
;; PLACEMENT for cpc-banked: it puts the handler (and so its whole IRQ path) in
;; the `code_crt_common` section, which the cpc-banked custom linker map
;; (mmap-cpc-banked.inc) orders EARLY in SECTION CODE — landing below 0x4000
;; (page A, always mapped).  That is mandatory here: a tick may fire while a
;; dataset bank is paged into the 0x4000-0x7FFF Gate-Array swap window, so the
;; handler must stay mapped (interrupts stay live across dataset_activate's
;; decompress).  The ISR state (_cpc_isr_div_counter, _isr_busy) is likewise
;; hand-placed in code_crt_common by asmdata_cpc_banked.asm.  cpc-banked-ONLY
;; (engine/src/cpc-banked/*.asm; the cpc-flat wrapper rage1_cpc_isr_flat.asm is
;; filtered OUT of this build in Makefile-cpc-banked).

    section     code_crt_common

    INCLUDE "engine/src/cpc/rage1_cpc_isr_body.inc"

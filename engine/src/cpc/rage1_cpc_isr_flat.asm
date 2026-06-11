;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; RAGE1 - Retro Adventure Game Engine, release 1
;; (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
;;
;; This code is published under a GNU GPL license version 3 or later.  See
;; LICENSE file in the distribution for details.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; cpc-flat PLACEMENT WRAPPER for the shared RAGE1-owned IM1 handler.
;;
;; The handler code itself is shared with cpc-banked in
;; engine/src/cpc/rage1_cpc_isr_body.inc (full design rationale there and in
;; doc/multiplatform-plan/cpc-interrupts.md).  This wrapper only fixes its
;; PLACEMENT for cpc-flat: it uses the DEFAULT code section (no `section`
;; directive — exactly like the other engine/src/cpc/*.asm primitives), which the
;; +cpc default linker map places in the program area above CRT_ORG_CODE (0x1200).
;; cpc-flat is a flat 64 KB model with no bank-switched window, so the handler has
;; no low-memory placement constraint — any address but the 0x0000 restart/IM1
;; vectors is fine, and the default section satisfies that.  (This is why the
;; handler must NOT be put in `code_crt_common` here: under the +cpc CRT that
;; section collapses to 0x0000 and would collide with the restart vectors — see
;; engine/src/cpc/asmdata_cpc.c.)
;;
;; This file is the cpc-FLAT half: it is compiled by the Makefile-cpc-flat build
;; (which globs engine/src/cpc/*.asm) and is explicitly filtered OUT of the
;; cpc-banked build (Makefile-cpc-banked), which supplies its own placement
;; wrapper engine/src/cpc-banked/rage1_cpc_isr.asm.

    INCLUDE "engine/src/cpc/rage1_cpc_isr_body.inc"

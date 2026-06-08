;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; RAGE1 CUSTOM MEMORY MODEL FOR THE LINKER — CPC-BANKED (CPC 6128)
;;
;; Phase T3a: identical section layout to cpc-flat (the smoke game has no
;; banking). The cpc-banked page map (swap window 0x4000, datasets/codesets
;; in RAM 4-7, JSP in RAM1) and its sections land in Phase B6/B7 — see
;; doc/multiplatform-plan/management/cpc-banked-bringup.md (DC3 / Shape A|B).
;;
;; cpc-banked memory map (Shape A, banking.md §3.1.4):
;;   0x0000-0x3FFF  Page A (RAM0): Z80 vectors, ISR, resident code (CRT @0x1200)
;;   0x4000-0x7FFF  Page B: swap window (RAM1 home: JSP buffers) — B6/B7
;;   0x8000-0xBFFF  Page C (RAM2): dataset buffer + home data; stack @0xBF00
;;   0xC000-0xFFFF  Screen RAM (RAM3) — code/data MUST NOT live here
;;
;; This file is published under the same license as Z88DK itself.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; memory model ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

SECTION CODE

org __crt_org_code

IF (__crt_org_vector_table = -0x80) || (__crt_org_vector_table = -0x100)

section code_crt_interrupt_vector_table
section code_crt_start

ENDIF

section code_crt_init
section code_crt_main
section code_crt_exit
section code_crt_return
section code_crt_common
section code_l
section code_l_sdcc
section code_l_sccz80
section code_math
section code_stdlib
section code_compress_zx0
section code_im2
section code_z80

;; cpc-flat has no SUB loader (no banking, no bank-switch primitive)

;; the following sections have been moved from their normal places so
;; that game data is placed at the start of the memory map
section rodata_input
section rodata_compiler
section rodata_sound_bit
section data_compiler
section data_arch
section data_stdlib
section data_sound_bit
section bss_compiler
section bss_error
section bss_stdlib

IF (__crt_org_vector_table) && (__crt_org_vector_table != -0x80) && (__crt_org_vector_table != -0x100)

section code_crt_interrupt_vector_table

ENDIF

section code_compiler
section code_driver
section code_font
section code_clib
  include "../../clib_code.inc"
section code_lib
section code_user
section code_sound_bit

section rodata_align_256
align 256

section rodata_align_128
align 128

section rodata_align_64
align 64

section rodata_align_32
align 32

section rodata_align_16
align 16

section rodata_align_8
align 8

section rodata_align_4
align 4

section rodata_align_2
align 2

section rodata_driver
section rodata_font
section rodata_clib
  include "../../clib_rodata.inc"
section rodata_lib
section rodata_user

SECTION CODE_END

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

SECTION DATA

IF __crt_org_data

   org __crt_org_data

ELSE

   IF __crt_model

      "DATA section address must be specified for rom models"

   ENDIF

ENDIF

section data_align_256
align 256

section data_align_128
align 128

section data_align_64
align 64

section data_align_32
align 32

section data_align_16
align 16

section data_align_8
align 8

section data_align_4
align 4

section data_align_2
align 2

section smc_jump_vectors
section smc_driver
section smc_font
section smc_clib
  include "../../clib_smc.inc"
section smc_lib
section smc_compiler
section smc_user

section data_driver
section data_font
section data_clib
  include "../../clib_data.inc"
section data_lib
section data_user

SECTION DATA_END

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

SECTION BSS

IF __crt_org_bss

   org __crt_org_bss

ELSE

   IF __crt_model

      org -1

   ENDIF

ENDIF

section bss_align_256
align 256

section bss_align_128
align 128

section bss_align_64
align 64

section bss_align_32
align 32

section bss_align_16
align 16

section bss_align_8
align 8

section bss_align_4
align 4

section bss_align_2
align 2

section bss_driver
section bss_font
section bss_clib
  include "../../clib_bss.inc"
section bss_lib
section bss_user

section BSS_UNINITIALIZED
SECTION BSS_END

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

IF (__crt_org_vector_table = 0)

section code_crt_interrupt_vector_table
org 0

ENDIF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

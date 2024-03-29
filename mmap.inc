;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; RAGE1 CUSTOM MEMORY MODEL FOR THE LINKER
;;
;; See doc/BANKING-DESIGN, section "C Binary Linker Memory Map"
;; for the design that led to using this file.
;;
;; This file is published under the same license as Z88DK
;; itself
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; memory model ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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

;; the following section is the SUB loader and must be as low in memory as
;; possible to avoid being overwritten or swapped
section rage1_subs_loader
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
;; place the bit_beepfx routine and pals in non-contended memory
;; above code_compiler section
section code_sound_bit
section code_temp_sp1

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
  ;;section rodata_error_strings
  ;;section rodata_error_string_end
  ;;defb 0
section rodata_lib
;; moved to the start of the memory map
;;section rodata_compiler
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
  ;;section data_fcntl_stdio_heap_head
  ;;section data_fcntl_stdio_heap_body
  ;;section data_fcntl_stdio_heap_tail
  ;;section data_fcntl_fdtable_body
section data_lib
;; moved to the start of the memory map
;;section data_compiler
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
;; moved to the start of he memory map
;;section bss_compiler
section bss_user

section BSS_UNINITIALIZED
SECTION BSS_END

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

IF (__crt_org_vector_table = 0)

section code_crt_interrupt_vector_table
org 0

ENDIF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

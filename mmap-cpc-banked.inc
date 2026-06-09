;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; RAGE1 CUSTOM MEMORY MODEL FOR THE LINKER — CPC-BANKED (CPC 6128)
;;
;; B7 step 9.4: REAL custom linker memory map (enabled via `#pragma output
;; MMAP = -1` in zpragma-cpc-banked.inc).  Its job is the cpc-banked LOWMEM
;; discipline: pin the engine's SWAP-ACTIVE code+data BELOW 0x4000 (page A,
;; RAM0 — always mapped), out of the 0x4000-0x7FFF Gate-Array swap window
;; (page B), which is shadowed whenever a dataset/codeset bank (RAM4-7) is
;; paged in.
;;
;; IMPORTANT — this is the CLASSIC +cpc clib model (clib=default), NOT the ZX
;; newlib (sdcc_iy) model that mmap.inc / mmap-128.inc use.  The two are
;; structurally different (classic has no `org __crt_org_code` head, no
;; `../../clib_*.inc` section lists, and the SECTION ordering lives in
;; crt/classic/crt_section_{code,rodata,data,bss}.inc).  So this file is built
;; on the CLASSIC standard map (a near-verbatim crt_section_standard.inc) with
;; ONE change: it positions `code_crt_common` and `code_compress_zx0` EARLY in
;; SECTION CODE (right after the CRT init sections) so they land at the lowest
;; free addresses from CRT_ORG_CODE = 0x1200 upward, i.e. below 0x4000.
;;
;;   - code_crt_common  : the 7 swap-active globals (current_time,
;;                        periodic_tasks_enabled, banked/home/codeset_assets,
;;                        interrupt_nesting_level, memory_current_memory_bank —
;;                        engine/src/cpc-banked/asmdata_cpc_banked.asm — plus
;;                        the generated _dataset_info).  In the stock classic
;;                        map this section has no home and the linker dumps it
;;                        at 0x0000 (over the CPC restart / 0x0038 IM1 vectors).
;;   - code_compress_zx0: the dzx0 decompressor, whose own instructions run
;;                        while a dataset bank is mapped at 0x4000.
;; The engine BULK (code_compiler / bss_compiler / rodata, etc.) may stay
;; higher in page B: it is only live in Config 0 (home mapping).
;;
;; The SECTION declarations below pre-position the two LOWMEM sections; the
;; INCLUDEs then pull in the full classic section lists (sections re-declared
;; there just continue at their already-fixed position).  The classic includes
;; resolve via the assembler -I lib root the +cpc link already passes, so no
;; ../../clib_*.inc relative paths are needed.
;;
;; cpc-banked memory map (Shape A, banking.md §3.1.4):
;;   0x0000-0x11FF  Page A (RAM0): Z80 restart/IM1 vectors, firmware area
;;   0x1200-0x3FFF  Page A (RAM0): resident engine code + the LOWMEM globals
;;   0x4000-0x7FFF  Page B: swap window (RAM1 home: JSP buffers; RAM4-7 banks)
;;   0x8000-0xBFFF  Page C (RAM2): dataset buffer + home data; stack @0xBF00
;;   0xC000-0xFFFF  Screen RAM (RAM3) — code/data MUST NOT live here
;;
;; NOTE on includes: this file is staged AS `./mmap.inc` in the link cwd by the
;; Makefile-cpc-banked recipe (crt/classic/crt_section.inc hard-codes
;; `INCLUDE "./mmap.inc"` when __MMAP == -1).
;;
;; This file is published under the same license as Z88DK itself.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CODE — LOWMEM sections pinned first, then the classic CODE list
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    SECTION CODE
    SECTION code_crt_init
    SECTION code_crt_init_exit
    SECTION code_crt_exit
    SECTION code_crt_exit_exit
    ;; LOWMEM discipline: these two land below 0x4000 (page A).
    SECTION code_crt_common
    SECTION code_compress_zx0

    ;; full classic CODE/RODATA/DATA/BSS section ordering
    INCLUDE "crt/classic/crt_section_code.inc"
    INCLUDE "crt/classic/crt_section_rodata.inc"
    SECTION ROMABLE_END
IF !__crt_model
    INCLUDE "crt/classic/crt_section_data.inc"
ENDIF
    INCLUDE "crt/classic/crt_section_bss.inc"

; For ROM compilation, the data section has to sit in RAM. It's placed
; after the BSS section
IF __crt_model > 0
    SECTION DATA
    org     -1
    defb    0		; control name of data binary
    INCLUDE "crt/classic/crt_section_data.inc"
ENDIF
    SECTION BSS_END

; On some targets, the program sits in low memory AND the screen can
; only be accessed by paging it into low memory. To mitigate this
; routines that access the screen are placed in high memory.
;
; We might have a similar issue with far code, so create a placeholder
; for that as well
IF __crt_org_graphics > 0 || __crt_org_far > 0
    SECTION	HIMEM

IF __crt_org_graphics > 0
    org	__crt_org_graphics
ELIF  __crt_org_far > 0
    org	__crt_org_far
ENDIF
    SECTION code_himem
    SECTION rodata_himem
    SECTION data_himem
    SECTION bss_himem
IF __crt_org_graphics > 0
    SECTION smc_clib
    SECTION code_graphics
    SECTION rodata_graphics
    SECTION data_graphics
    SECTION bss_graphics
ENDIF

IF __crt_org_far > 0
    SECTION code_far
    SECTION code_l_sccz80_far
    SECTION data_far
    SECTION rodata_far
    SECTION bss_far
ENDIF
    SECTION HIMEM_END
ENDIF

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CPC expansion-bank scaffolding (RAM4-7 at 0xC4-0xC7 0000 + page-B window).
;; With MMAP=-1 the +cpc CRT skips its built-in BANK_0..7 block (cpc_crt0.asm
;; `IF __MMAP != -1`), but target/cpc/classic/loader.asm (included by the CRT)
;; still references CRT_ORG_BANK_0..7 and __BANK_<n>_END_tail — so this custom
;; map MUST carry them.  Copied verbatim from cpc_crt0.asm's else-branch.
;; (The CRT defines `SECTION UNASSIGNED / org 0` itself, unconditionally, so it
;; is NOT repeated here — repeating it triggers an "ORG redefined" error.)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    IFNDEF CRT_ORG_BANK_0
        defc CRT_ORG_BANK_0 = 0x0000
    ENDIF

    IFNDEF CRT_ORG_BANK_1
        defc CRT_ORG_BANK_1 = 0x4000
    ENDIF

    IFNDEF CRT_ORG_BANK_2
        defc CRT_ORG_BANK_2 = 0x8000
    ENDIF

    IFNDEF CRT_ORG_BANK_3
        defc CRT_ORG_BANK_3 = 0xc000
    ENDIF

    IFNDEF CRT_ORG_BANK_4
        defc CRT_ORG_BANK_4 = 0x4000
    ENDIF

    IFNDEF CRT_ORG_BANK_5
        defc CRT_ORG_BANK_5 = 0x4000
    ENDIF

    IFNDEF CRT_ORG_BANK_6
        defc CRT_ORG_BANK_6 = 0x4000
    ENDIF

    IFNDEF CRT_ORG_BANK_7
        defc CRT_ORG_BANK_7 = 0x4000
    ENDIF

    SECTION BANK_0
    org 0xc00000 + CRT_ORG_BANK_0
    SECTION CODE_0
    SECTION RODATA_0
    SECTION RODATA_0_align_256
    align 256
    SECTION RODATA_0_align_128
    align 128
    SECTION RODATA_0_align_64
    align 64
    SECTION RODATA_0_align_32
    align 32
    SECTION RODATA_0_align_16
    align 16
    SECTION RODATA_0_align_8
    align 8
    SECTION RODATA_0_align_4
    align 4
    SECTION RODATA_0_align_2
    align 2
    SECTION DATA_0
    SECTION DATA_0_align_256
    align 256
    SECTION DATA_0_align_128
    align 128
    SECTION DATA_0_align_64
    align 64
    SECTION DATA_0_align_32
    align 32
    SECTION DATA_0_align_16
    align 16
    SECTION DATA_0_align_8
    align 8
    SECTION DATA_0_align_4
    align 4
    SECTION DATA_0_align_2
    align 2
    SECTION BSS_0
    SECTION BANK_0_END

    SECTION BANK_1
    org 0xc00000 + CRT_ORG_BANK_1
    SECTION CODE_1
    SECTION RODATA_1
    SECTION RODATA_1_align_256
    align 256
    SECTION RODATA_1_align_128
    align 128
    SECTION RODATA_1_align_64
    align 64
    SECTION RODATA_1_align_32
    align 32
    SECTION RODATA_1_align_16
    align 16
    SECTION RODATA_1_align_8
    align 8
    SECTION RODATA_1_align_4
    align 4
    SECTION RODATA_1_align_2
    align 2
    SECTION DATA_1
    SECTION DATA_1_align_256
    align 256
    SECTION DATA_1_align_128
    align 128
    SECTION DATA_1_align_64
    align 64
    SECTION DATA_1_align_32
    align 32
    SECTION DATA_1_align_16
    align 16
    SECTION DATA_1_align_8
    align 8
    SECTION DATA_1_align_4
    align 4
    SECTION DATA_1_align_2
    align 2
    SECTION BSS_1
    SECTION BANK_1_END

    SECTION BANK_2
    org 0xc00000 + CRT_ORG_BANK_2
    SECTION CODE_2
    SECTION RODATA_2
    SECTION RODATA_2_align_256
    align 256
    SECTION RODATA_2_align_128
    align 128
    SECTION RODATA_2_align_64
    align 64
    SECTION RODATA_2_align_32
    align 32
    SECTION RODATA_2_align_16
    align 16
    SECTION RODATA_2_align_8
    align 8
    SECTION RODATA_2_align_4
    align 4
    SECTION RODATA_2_align_2
    align 2
    SECTION DATA_2
    SECTION DATA_2_align_256
    align 256
    SECTION DATA_2_align_128
    align 128
    SECTION DATA_2_align_64
    align 64
    SECTION DATA_2_align_32
    align 32
    SECTION DATA_2_align_16
    align 16
    SECTION DATA_2_align_8
    align 8
    SECTION DATA_2_align_4
    align 4
    SECTION DATA_2_align_2
    align 2
    SECTION BSS_2
    SECTION BANK_2_END

    SECTION BANK_3
    org 0xc00000 + CRT_ORG_BANK_3
    SECTION CODE_3
    SECTION RODATA_3
    SECTION RODATA_3_align_256
    align 256
    SECTION RODATA_3_align_128
    align 128
    SECTION RODATA_3_align_64
    align 64
    SECTION RODATA_3_align_32
    align 32
    SECTION RODATA_3_align_16
    align 16
    SECTION RODATA_3_align_8
    align 8
    SECTION RODATA_3_align_4
    align 4
    SECTION RODATA_3_align_2
    align 2
    SECTION DATA_3
    SECTION DATA_3_align_256
    align 256
    SECTION DATA_3_align_128
    align 128
    SECTION DATA_3_align_64
    align 64
    SECTION DATA_3_align_32
    align 32
    SECTION DATA_3_align_16
    align 16
    SECTION DATA_3_align_8
    align 8
    SECTION DATA_3_align_4
    align 4
    SECTION DATA_3_align_2
    align 2
    SECTION BSS_3
    SECTION BANK_3_END

    SECTION BANK_4
    org 0xc40000 + CRT_ORG_BANK_4
    SECTION CODE_4
    SECTION RODATA_4
    SECTION RODATA_4_align_256
    align 256
    SECTION RODATA_4_align_128
    align 128
    SECTION RODATA_4_align_64
    align 64
    SECTION RODATA_4_align_32
    align 32
    SECTION RODATA_4_align_16
    align 16
    SECTION RODATA_4_align_8
    align 8
    SECTION RODATA_4_align_4
    align 4
    SECTION RODATA_4_align_2
    align 2
    SECTION DATA_4
    SECTION DATA_4_align_256
    align 256
    SECTION DATA_4_align_128
    align 128
    SECTION DATA_4_align_64
    align 64
    SECTION DATA_4_align_32
    align 32
    SECTION DATA_4_align_16
    align 16
    SECTION DATA_4_align_8
    align 8
    SECTION DATA_4_align_4
    align 4
    SECTION DATA_4_align_2
    align 2
    SECTION BSS_4
    SECTION BANK_4_END

    SECTION BANK_5
    org 0xc50000 + CRT_ORG_BANK_5
    SECTION CODE_5
    SECTION RODATA_5
    SECTION RODATA_5_align_256
    align 256
    SECTION RODATA_5_align_128
    align 128
    SECTION RODATA_5_align_64
    align 64
    SECTION RODATA_5_align_32
    align 32
    SECTION RODATA_5_align_16
    align 16
    SECTION RODATA_5_align_8
    align 8
    SECTION RODATA_5_align_4
    align 4
    SECTION RODATA_5_align_2
    align 2
    SECTION DATA_5
    SECTION DATA_5_align_256
    align 256
    SECTION DATA_5_align_128
    align 128
    SECTION DATA_5_align_64
    align 64
    SECTION DATA_5_align_32
    align 32
    SECTION DATA_5_align_16
    align 16
    SECTION DATA_5_align_8
    align 8
    SECTION DATA_5_align_4
    align 4
    SECTION DATA_5_align_2
    align 2
    SECTION BSS_5
    SECTION BANK_5_END

    SECTION BANK_6
    org 0xc60000 + CRT_ORG_BANK_6
    SECTION CODE_6
    SECTION RODATA_6
    SECTION RODATA_6_align_256
    align 256
    SECTION RODATA_6_align_128
    align 128
    SECTION RODATA_6_align_64
    align 64
    SECTION RODATA_6_align_32
    align 32
    SECTION RODATA_6_align_16
    align 16
    SECTION RODATA_6_align_8
    align 8
    SECTION RODATA_6_align_4
    align 4
    SECTION RODATA_6_align_2
    align 2
    SECTION DATA_6
    SECTION DATA_6_align_256
    align 256
    SECTION DATA_6_align_128
    align 128
    SECTION DATA_6_align_64
    align 64
    SECTION DATA_6_align_32
    align 32
    SECTION DATA_6_align_16
    align 16
    SECTION DATA_6_align_8
    align 8
    SECTION DATA_6_align_4
    align 4
    SECTION DATA_6_align_2
    align 2
    SECTION BSS_6
    SECTION BANK_6_END

    SECTION BANK_7
    org 0xc70000 + CRT_ORG_BANK_7
    SECTION CODE_7
    SECTION RODATA_7
    SECTION RODATA_7_align_256
    align 256
    SECTION RODATA_7_align_128
    align 128
    SECTION RODATA_7_align_64
    align 64
    SECTION RODATA_7_align_32
    align 32
    SECTION RODATA_7_align_16
    align 16
    SECTION RODATA_7_align_8
    align 8
    SECTION RODATA_7_align_4
    align 4
    SECTION RODATA_7_align_2
    align 2
    SECTION DATA_7
    SECTION DATA_7_align_256
    align 256
    SECTION DATA_7_align_128
    align 128
    SECTION DATA_7_align_64
    align 64
    SECTION DATA_7_align_32
    align 32
    SECTION DATA_7_align_16
    align 16
    SECTION DATA_7_align_8
    align 8
    SECTION DATA_7_align_4
    align 4
    SECTION DATA_7_align_2
    align 2
    SECTION BSS_7
    SECTION BANK_7_END

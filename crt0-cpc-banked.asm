;       CRT0 for the Amstrad CPC family — RAGE1 cpc-banked CUSTOM MINIMAL variant
;
;       Derived from z88dk lib/target/cpc/classic/cpc_crt0.asm (Stefano Bodrato,
;       $Id: cpc_crt0.asm,v 1.37 2016-07-15 21:03:25 dom Exp $).  Selected for the
;       GAME.BIN link via `-crt0=crt0-cpc-banked.asm` (Makefile-cpc-banked).
;
;       WHY A CUSTOM CRT0 (cpc-banked B7 step 9.5, "Option 1"):
;       GAME.BIN is the resident full-engine image, entered by `jp 0x1200` from
;       LOADER.BIN — itself a +cpc CRT that has already run mc_start_program
;       (ROMs disabled) and cpc_enable_process_exx_set (firmware alt/exx set left
;       in PROCESS state).  The STOCK +cpc CRT prologue runs firmware-dependent
;       startup BEFORE its own exx-seize — kl_rom_walk (unconditional), the AMSDOS
;       drive restore, and `call loadbanks` (a direct CAS call) — all of which
;       execute against that non-native firmware register state and CRASH before
;       main() (proven 2026-06-09: a screen-fill probe at main() top never paints
;       until the loader restores fw-exx state).  This crt0 DROPS that firmware
;       prologue entirely: GAME.BIN is self-contained at entry and relies only on
;       the state the loader already established (ROMs off).  Everything from `di`
;       onward is IDENTICAL to the stock cpc_crt0.asm.
;
;       KEPT (essential, and firmware-free under CRT_DISABLE_FIRMWARE_ISR=1):
;         - SP init, crt0_init (data/BSS), atexit init, heap/eidi init
;         - cpc_enable_process_exx_set: exx bookkeeping + installs a do-nothing IM1
;           stub (__interposer_isr__ = ei/ret) at 0x0038/0x0039 to cover the brief
;           startup window before main() runs init_interrupts(), which then pokes
;           `jp rage1_cpc_isr` over 0x0038 and OWNS IM1 (engine/src/cpc-banked/
;           rage1_cpc_isr.asm).  No firmware call, no clib ISR dispatcher.
;         - the exx routines, the do-nothing __interposer_isr__, and the MMAP BANK
;           scaffolding.  The clib fast/VSYNC vector walk + cpc_add_fast_isr/
;           cpc_add_vsync_isr aliases are REMOVED (RAGE1 never registers a clib
;           handler — they only pulled the clib dispatcher into the link).
;       DROPPED (firmware-dependent, would crash on jp-entry; also redundant here):
;         - AMSDOS drive read/restore (($be7d)), mc_start_program (ROMs already
;           off), kl_rom_walk, and loadbanks (banks are streamed by LOADER.BIN,
;           not by this CRT — so the target/cpc/classic/loader.asm INCLUDE and its
;           __BANK_<n>_END_tail externs are omitted too).
;

    MODULE  cpc_crt0


    defc    crt0 = 1
    INCLUDE "zcc_opt.def"

    EXTERN  _main           ;main() is always external to crt0 code

    PUBLIC  __Exit         ;jp'd to by exit()
    PUBLIC  l_dcal          ;jp(hl)


IF DEFINED_CLIB_DEFAULT_SCREEN_MODE
    IF CLIB_DEFAULT_SCREEN_MODE = 0
        defc    CONSOLE_COLUMNS = 20
    ELIF CLIB_DEFAULT_SCREEN_MODE = 1
        defc    CONSOLE_COLUMNS = 40
    ELIF CLIB_DEFAULT_SCREEN_MODE = 2
        defc    CONSOLE_COLUMNS = 80
    ENDIF
ELSE
    defc    CONSOLE_COLUMNS = 40
ENDIF
    defc    CONSOLE_ROWS = 25

IF !DEFINED_CRT_DISABLE_FIRMWARE_ISR
    defc CRT_DISABLE_FIRMWARE_ISR = 0
ENDIF

IF CRT_DISABLE_FIRMWARE_ISR = 0
    PUBLIC CRT_EVENT_BLOCKS
    PUBLIC CRT_EVENT_BLOCKS_NUM

    ; 8 slots of 16 bytes = 128
    defc CRT_EVENT_BLOCKS = 0xa600
    defc CRT_EVENT_BLOCKS_NUM = 8
ENDIF


IF !DEFINED_CRT_MAX_HEAP_ADDRESS
    defc    CRT_MAX_HEAP_ADDRESS = 0xa600
ENDIF

    ; Floating point accumulator needs to be in middle 32k
    PUBLIC  fa
    defc    fa = 0xa680


    PUBLIC  cpc_enable_fw_exx_set       ;needed by firmware interposer
    PUBLIC  cpc_enable_process_exx_set  ;needed by firmware interposer

    GLOBAL  __interposer_isr__

    defc    TAR__no_ansifont = 1
    defc    TAR__register_sp = -1
    defc    TAR__clib_exit_stack_size = 8
    defc    TAR__clib_banking_stack_size = 16
    defc    TAR__crt_enable_eidi = $02  ; ei on startup
    defc    CRT_KEY_DEL = 12
    defc    __CPU_CLOCK = 4000000
    INCLUDE "crt/classic/crt_rules.inc"

    INCLUDE "target/cpc/def/cpcfirm.def"

;--------
; Set an origin for the application (-zorg=) default to $1200
;--------

IF      !DEFINED_CRT_ORG_CODE
    defc    CRT_ORG_CODE  = $1200
ENDIF
    org     CRT_ORG_CODE


;--------
; REAL CODE
;--------
; RAGE1 cpc-banked: the stock +cpc firmware prologue (AMSDOS drive read,
; mc_start_program, kl_rom_walk, AMSDOS drive restore, loadbanks) is REMOVED.
; GAME.BIN is jp'd into from LOADER.BIN (already in process-exx state with ROMs
; disabled), so those firmware calls would run against a non-native firmware
; register state and crash before main().  Everything below is identical to the
; stock cpc_crt0.asm `start:` body from `di` onward.

start:
    di
    ld      (__restore_sp_onexit+1),sp
    INCLUDE "crt/classic/crt_init_sp.inc"
    call    crt0_init
    INCLUDE "crt/classic/crt_init_atexit.inc"


    ; enable process exx set
    ; install interrupt interposer
    call    cpc_enable_process_exx_set

    INCLUDE "crt/classic/crt_init_heap.inc"
    INCLUDE "crt/classic/crt_init_eidi.inc"

IF DEFINED_CLIB_DEFAULT_SCREEN_MODE
    ld      a,CLIB_DEFAULT_SCREEN_MODE
    call    cpc_setmode
ENDIF

    call    _main

__Exit:
    call    crt0_exit
IF CLIB_EXIT_SCREEN_MODE != -1
    ld      a,CLIB_EXIT_SCREEN_MODE
    call    cpc_setmode
ENDIF

    di
    call    cpc_enable_fw_exx_set
__restore_sp_onexit:
    ld      sp,0
    ei
    ret

l_dcal:
    jp      (hl)


; These subroutines make it possible to coexist with the firmware.
; Interrupts must be disabled while these routines run.

cpc_enable_fw_exx_set:

    exx
    ex      af,af'

    ld      (__process_exx_set_hl__),hl      ; save process exx set
    ld      (__process_exx_set_de__),de
    ld      (__process_exx_set_bc__),bc
    push    af
    pop     hl
    ld      (__process_exx_set_af__),hl

IF startup != 2
  IF CRT_DISABLE_FIRMWARE_ISR = 0
    ld      hl,(__fw_int_address__)
    ld      (0x0039),hl                      ; restore firmware isr
  ELSE
    ld      hl,$c9fb                         ; ei ret
    ld      (0x0038),hl
  ENDIF
ENDIF

    ld      bc,(__fw_exx_set_bc__)           ; restore firmware exx set
    or      a

    ex      af,af'
    exx

    ret

cpc_enable_process_exx_set:

    exx
    ex      af,af'

    ld      (__fw_exx_set_bc__),bc           ; save firmware exx set

IF startup != 2
  IF CRT_DISABLE_FIRMWARE_ISR = 0
    ld      hl,(0x0039)
    ld      (__fw_int_address__),hl          ; save firmware interrupt entry
  ELSE
    ld      a,195                            ; jp
    ld      (0x0038),a
  ENDIF
    ld      hl,__interposer_isr__
    ld      (0x0039),hl                      ; interposer receives interrupts
ENDIF

    ld      hl,(__process_exx_set_af__)      ; restore process exx set
    push    hl
    pop     af
    ld      bc,(__process_exx_set_bc__)
    ld      de,(__process_exx_set_de__)
    ld      hl,(__process_exx_set_hl__)

    ex      af,af'
    exx

    ret

IF startup != 2

; RAGE1 cpc-banked: the engine OWNS the IM1 vector from init_interrupts(), which
; pokes `jp rage1_cpc_isr` at 0x0038 (engine/src/cpc-banked/rage1_cpc_isr.asm).
; This interposer therefore only has to survive the brief startup window between
; crt_init_eidi (EI on startup) and init_interrupts() — so it is a do-nothing ISR
; (the GA interrupt is acknowledged by the Z80 INT cycle; ei/ret is sufficient).
; The z88dk-clib fast/VSYNC vector walk (im1_vectors/fast_vectors via
; asm_interrupt_handler) and the cpc_add_fast_isr/cpc_add_vsync_isr registration
; aliases are REMOVED: RAGE1 never registers a clib handler, so they were dead code
; that needlessly pulled the clib interrupt dispatcher into the link.

__interposer_isr__:
   ei
   ret

ENDIF


    INCLUDE "crt/classic/crt_runtime_selection.inc"

    INCLUDE "crt/classic/crt_section.inc"

    SECTION code_crt_init
    ld      hl,$c000
    ld      (base_graphics),hl

    SECTION	bss_crt
__fw_exx_set_bc__:        defs 2
__process_exx_set_af__:   defs 2
__process_exx_set_bc__:   defs 2
__process_exx_set_de__:   defs 2
__process_exx_set_hl__:   defs 2
__fw_int_address__:       defs 2

IF CRT_DISABLE_FIRMWARE_ISR = 0
    SECTION     data_crt
__im_counter:             defb 6
ENDIF


IF __MMAP != -1
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; Define Memory Banks
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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
ENDIF

    SECTION UNASSIGNED
    org     0

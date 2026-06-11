;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; RAGE1 - Retro Adventure Game Engine, release 1
;; (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
;;
;; This code is published under a GNU GPL license version 3 or later.  See
;; LICENSE file in the distribution for details.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; cpc-banked: RAGE1-owned IM1 interrupt handler, in always-mapped low memory.
;; Full design: doc/multiplatform-plan/cpc-interrupts.md.
;;
;; The CPC raster interrupt fires ~6x/frame (~300 Hz), hardware-locked to the
;; display frame by the Gate Array (exactly 6 per frame, no drift).  We derive the
;; engine's 50 Hz tick by DIVIDING BY SIX: every 6th interrupt is one frame tick.
;;
;; Why divide-by-six and NOT reading the VSYNC bit at interrupt time: the firmware-
;; free CPC raster interrupt and the CRTC VSYNC pulse do not reliably coincide — an
;; interrupt almost never samples VSYNC high at interrupt time.  Established CPC
;; practice (and z88dk's own firmware-free path — which only reliably frame-syncs via
;; the firmware kl_add_framefly event, and carries an orphaned `__im_counter: defb 6`
;; = an abandoned divide-by-six) is to NOT read VSYNC in the ISR; frame sync, when a
;; program needs it, is a busy-wait on the VSYNC bit in the MAIN LOOP.  Since the GA
;; already locks 6 interrupts/frame to the display, counting them gives a drift-free
;; 50 Hz.  Frame-aligned RENDERING, if ever needed, belongs in a main-loop VSYNC
;; wait, not here.
;;
;; The tick body (_rage1_50hz_tick) runs with interrupts ENABLED so a long body
;; never loses interrupts and may call banked code (future tracker music) via
;; memory_switch_bank.  This handler + its state (_cpc_isr_div_counter, _isr_busy)
;; live in the code_crt_common section, ordered below 0x4000 (page A, always mapped)
;; by the cpc-banked custom linker map — so a tick may fire safely while a dataset
;; bank is paged into the 0x4000-0x7FFF window (interrupts stay live across
;; dataset_activate's decompress).  cpc-banked-ONLY (engine/src/cpc-banked/*.asm).
;;
;; Reentrancy: _isr_busy is a 1-bit guard, test+set while DI and cleared while DI
;; (NEVER with interrupts enabled), so a tick that lands while the body is still
;; running is dropped (a missed tick — same as ZX), never re-entering the body.

    section     code_crt_common

    public      _rage1_cpc_isr

    extern      _cpc_isr_div_counter        ; divide-by-six counter / sub-frame index
    extern      _isr_busy                   ; 1-bit 50 Hz-body reentrancy guard
    extern      _rage1_50hz_tick            ; the C body (must also link <0x4000)

_rage1_cpc_isr:
    ;; entered DI (Z80 auto-DI on IM1 accept).  Fast path (5 of 6) saves only AF.
    push    af

    ;; divide by six: tick on every 6th interrupt
    ld      a,(_cpc_isr_div_counter)
    inc     a
    cp      6
    jr      nc,_rage1_cpc_isr_tick          ; a >= 6 -> frame tick
    ld      (_cpc_isr_div_counter),a        ; a < 6 -> just advance and return
    pop     af
    ei
    ret

_rage1_cpc_isr_tick:
    xor     a
    ld      (_cpc_isr_div_counter),a        ; reset counter (0..5 sub-frame index)

    ld      a,(_isr_busy)
    or      a
    jr      nz,_rage1_cpc_isr_exit          ; body still running -> drop (missed tick)
    ld      a,1
    ld      (_isr_busy),a                   ; [DI] atomic test+set

    ;; full save for the C body (BC/DE/HL/IX/IY + shadow set).  Shadow set saved for
    ;; parity with the ZX IM2 ISR and because a banked Arkos2/AU5 tracker run from the
    ;; body uses exx internally; cheap here (50 Hz only).
    push    bc
    push    de
    push    hl
    push    ix
    push    iy
    exx
    ex      af,af'
    push    af
    push    bc
    push    de
    push    hl
    exx

    ei                                      ; body runs INTERRUPTIBLE
    call    _rage1_50hz_tick
    di                                      ; back to DI before touching the flag

    exx
    pop     hl
    pop     de
    pop     bc
    pop     af
    ex      af,af'
    exx
    pop     iy
    pop     ix
    pop     hl
    pop     de
    pop     bc

    xor     a
    ld      (_isr_busy),a                   ; clear flag while DI

_rage1_cpc_isr_exit:
    pop     af
    ei
    ret

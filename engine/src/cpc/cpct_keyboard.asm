;;-----------------------------------------------------------------------------
;; RAGE1 - CPC backend : translated cpctelera keyboard primitives (Phase IN6)
;;
;; Hand-translated sdas -> z88dk z80asm from cpctelera (pinned 662fc885):
;;   src/keyboard/cpct_scanKeyboard.s      -> full keyboard/joystick matrix scan
;;   src/keyboard/cpct_scanKeyboard_f.s    -> faster (unrolled) matrix scan
;;   src/keyboard/cpct_isKeyPressed.s      -> single-key query (fastcall)
;;   src/keyboard/cpct_isAnyKeyPressed_f.s -> "any key down?" (unrolled)
;;   src/keyboard/keyboard.s               -> 10-byte cpct_keyboardStatusBuffer
;;
;; These back the real CPC input HAL bodies in engine/src/input.c
;; (BUILD_FEATURE_INPUT_BACKEND_CPC) and the macros in rage1/input_cpc.h.
;;
;; cpctelera is LGPL-3.0 (c) ronaldo / Fremos / Cheesetea / ByteRealms
;; (@FranGallegoBR). These translations are LGPL-derived works, built as
;; ordinary engine asm.  The external/cpctelera submodule (canonical reference)
;; was removed at R10; these translations derive from cpctelera commit 662fc885.
;; See engine/src/cpc/README.md.
;;
;; Translation conventions (sdas -> z80asm), per engine/src/cpc/README.md:
;;   .module X        -> MODULE X
;;   _sym::           -> PUBLIC _sym + _sym:
;;   ld bc,#0xF782    -> ld bc,0xF782       (drop the '#' immediate prefix)
;;   .dw #0x71ED      -> defw 0x71ED        (the encoded "out (c),0" opcode)
;;   .db ...          -> defb ...
;;   The C-callable ABI (__z88dk_fastcall / void) is preserved exactly, so no
;;   symbol renaming is needed at the C boundary.
;;-----------------------------------------------------------------------------

        MODULE cpct_keyboard

;;-----------------------------------------------------------------------------
;; cpct_keyboardStatusBuffer : 10 bytes (80 bits), one bit per CPC key/button.
;; 0 = pressed, 1 = not pressed (AY-3-8912 / PPI encoding).  Initialised to all
;; "not pressed" (0xFF).  Refreshed by the scan routines below; read by
;; cpct_isKeyPressed / cpct_isAnyKeyPressed_f and the input.c buffer walks.
;;-----------------------------------------------------------------------------
        PUBLIC _cpct_keyboardStatusBuffer
_cpct_keyboardStatusBuffer:
        defb 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF

;;-----------------------------------------------------------------------------
;; void cpct_scanKeyboard( void )
;;   Reads the whole 80-key matrix into cpct_keyboardStatusBuffer.  Manages its
;;   own DI/EI (safe to call directly from C).  Rolled loop (212 us).
;;   Destroys AF, BC, DE, HL.
;;-----------------------------------------------------------------------------
        PUBLIC _cpct_scanKeyboard
_cpct_scanKeyboard:
        di                              ;; disable interrupts during the scan

        ;; Configure PPI: select AY register 14 (keyboard) for reading
        ld   bc, 0xF782                 ;; PPI: Port A & C = Output
        out  (c), c
        ld   bc, 0xF40E                 ;; write 14 to PPI Port A (select AY reg 14)
        ld   e, b                       ;; E = 0xF4 (Port A) for the loop
        out  (c), c
        ld   bc, 0xF6C0                 ;; write 0xC0 to PPI Port C: "select register"
        ld   d, b                       ;; D = 0xF6 (Port C) for the loop
        out  (c), c
        defw 0x71ED                     ;; out (c),0 : put PSG in inactive mode
        ld   bc, 0xF792                 ;; PPI: Port A = Input, Port C = Output
        out  (c), c

        ;; Read loop: 10 matrix lines (0x40..0x49) into the buffer
        ld   a, 0x40                    ;; A = first matrix line selector
        ld   c, 10                      ;; 10 lines to read
        ld   hl, _cpct_keyboardStatusBuffer

scan_next_line:
        ld   b, d                       ;; B = 0xF6 (Port C): select matrix line
        out  (c), a
        ld   b, e                       ;; B = 0xF4 (Port A): read line status
        ini                             ;; (HL) = port; HL++, B--
        inc  a                          ;; next matrix line
        dec  c
        jr   nz, scan_next_line

        ;; Restore PPI Port A & C = Output
        ld   bc, 0xF782
        out  (c), c

        ei                              ;; re-enable interrupts
        ret

;;-----------------------------------------------------------------------------
;; void cpct_scanKeyboard_f( void )
;;   Same as cpct_scanKeyboard but with an unrolled read loop (~25% faster,
;;   170 us).  Manages its own DI/EI.  Destroys AF, BC, DE, HL.
;;-----------------------------------------------------------------------------
        PUBLIC _cpct_scanKeyboard_f
_cpct_scanKeyboard_f:
        di

        ld   bc, 0xF782                 ;; PPI: Port A & C = Output
        out  (c), c
        ld   bc, 0xF40E                 ;; select AY reg 14
        ld   e, b
        out  (c), c
        ld   bc, 0xF6C0
        ld   d, b
        out  (c), c
        defw 0x71ED                     ;; out (c),0
        ld   bc, 0xF792                 ;; PPI: Port A = Input, Port C = Output
        out  (c), c

        ld   a, 0x40
        ld   hl, _cpct_keyboardStatusBuffer

        ;; line 0x40
        ld   b, d
        out  (c), a
        ld   b, e
        ini
        inc  a
        ;; line 0x41
        ld   b, d
        out  (c), a
        ld   b, e
        ini
        inc  a
        ;; line 0x42
        ld   b, d
        out  (c), a
        ld   b, e
        ini
        inc  a
        ;; line 0x43
        ld   b, d
        out  (c), a
        ld   b, e
        ini
        inc  a
        ;; line 0x44
        ld   b, d
        out  (c), a
        ld   b, e
        ini
        inc  a
        ;; line 0x45
        ld   b, d
        out  (c), a
        ld   b, e
        ini
        inc  a
        ;; line 0x46
        ld   b, d
        out  (c), a
        ld   b, e
        ini
        inc  a
        ;; line 0x47
        ld   b, d
        out  (c), a
        ld   b, e
        ini
        inc  a
        ;; line 0x48
        ld   b, d
        out  (c), a
        ld   b, e
        ini
        inc  a
        ;; line 0x49 (no inc a after the last)
        ld   b, d
        out  (c), a
        ld   b, e
        ini

        ld   bc, 0xF782                 ;; restore Port A & C = Output
        out  (c), c

        ei
        ret

;;-----------------------------------------------------------------------------
;; u8 cpct_isKeyPressed( cpct_keyID key ) __z88dk_fastcall
;;   fastcall: key in HL (L = matrix line 0..9, H = bit mask).
;;   Returns (in L/A) 0 if not pressed, non-zero (the bit) if pressed.
;;   Destroys A, D, BC, HL.
;;-----------------------------------------------------------------------------
        PUBLIC _cpct_isKeyPressed
_cpct_isKeyPressed:
        ld   a, h                       ;; A = bit mask (the single key bit)
        ld   d, a                       ;; D = save mask
        ld   h, 0                       ;; HL = matrix line (offset into buffer)
        ld   bc, _cpct_keyboardStatusBuffer
        add  hl, bc                     ;; HL -> TargetByte
        xor  (hl)                       ;; invert the key's bit (buffer is active-low)
        and  d                          ;; keep only the target key's bit
        ld   l, a                       ;; L = return value (0 / bit set)
        ret

;;-----------------------------------------------------------------------------
;; u8 cpct_isAnyKeyPressed_f( void )
;;   Returns (in L/A) 0 if no key is down, non-zero if at least one key is
;;   down.  AND of the 10 buffer bytes, then INC (0xFF -> 0 == none).
;;   Destroys A, B, HL.
;;-----------------------------------------------------------------------------
        PUBLIC _cpct_isAnyKeyPressed_f
_cpct_isAnyKeyPressed_f:
        ld   hl, _cpct_keyboardStatusBuffer
        ld   a, (hl)                    ;; A = buffer[0]
        inc  hl
        and  (hl)                       ;; A &= buffer[1]
        inc  hl
        and  (hl)                       ;; buffer[2]
        inc  hl
        and  (hl)                       ;; buffer[3]
        inc  hl
        and  (hl)                       ;; buffer[4]
        inc  hl
        and  (hl)                       ;; buffer[5]
        inc  hl
        and  (hl)                       ;; buffer[6]
        inc  hl
        and  (hl)                       ;; buffer[7]
        inc  hl
        and  (hl)                       ;; buffer[8]
        inc  hl
        and  (hl)                       ;; buffer[9]
        inc  a                          ;; 0xFF (none) -> 0 ; else non-zero
        ld   l, a                       ;; L = return value
        ret

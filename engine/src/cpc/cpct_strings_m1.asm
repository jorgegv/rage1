;;-----------------------------------------------------------------------------
;; RAGE1 - CPC backend : translated cpctelera mode-1 text primitives (R1-5/R2)
;;
;; Hand-translated sdas -> z88dk z80asm from cpctelera (pinned 662fc885):
;;   src/strings/cpct_setDrawCharM1.asm  (+ _cbindings.s)
;;   src/strings/cpct_drawCharM1_inner.s
;;   src/strings/cpct_drawStringM1.asm   (+ _cbindings.s)
;;   src/strings/cpct_dc_mode1_ct.s      (pen -> 4-pixel table)
;;   src/strings/strings.s               (constants)
;;
;; cpctelera is LGPL-3.0 (c) ronaldo / Fremos / Cheesetea / ByteRealms.
;; LGPL-derived translation; see engine/src/cpc/README.md.
;;
;; These mode-1 text routines render characters from the CPC firmware font
;; in LOWER ROM (char N at 0x3800 + 8*N). cpct_drawStringM1 enables lower
;; ROM (with interrupts disabled) for the duration of the draw and restores
;; the previous mode/rom status afterwards.
;;-----------------------------------------------------------------------------

        MODULE cpct_strings_poc

        defc GA_port_byte = 0x7F
        EXTERN _cpct_mode_rom_status            ;; defined in cpct_video.asm

;;-----------------------------------------------------------------------------
;; dc_mode1_ct: PEN (0..3) -> mode-1 byte whose 4 pixels are all that PEN.
;;-----------------------------------------------------------------------------
dc_mode1_ct:
        defb 0x00, 0xF0, 0x0F, 0xFF

;;-----------------------------------------------------------------------------
;; cpct_char2pxM1: 16 FG/BG pixel-combination bytes, filled by setDrawCharM1
;; and consumed by drawCharM1_inner. Index = 4-bit mask (bit i set => pixel i
;; is foreground).
;;-----------------------------------------------------------------------------
        PUBLIC cpct_char2pxM1
cpct_char2pxM1:
        defs 16

;;-----------------------------------------------------------------------------
;; void cpct_setDrawCharM1( u8 fg_pen, u8 bg_pen ) __z88dk_callee
;;   callee: after pop/push below  E = fg_pen, D = bg_pen.
;;   Builds the 16-entry cpct_char2pxM1 table. Faithful translation,
;;   including the original NOP/RET self-modifying loop terminator.
;;-----------------------------------------------------------------------------
        PUBLIC _cpct_setDrawCharM1
_cpct_setDrawCharM1:
        pop  af                         ;; AF = return address
        pop  de                         ;; E = fg_pen, D = bg_pen
        push af                         ;; ret addr back on stack (__z88dk_callee)

        ld   hl, dc_mode1_ct
        ld   a, d                       ;; A = bg_pen (save)
        ld   d, 0                       ;; DE = fg_pen
        add  hl, de
        ld   c, (hl)                    ;; C = 4 foreground pixels
        ld   hl, dc_mode1_ct
        ld   e, a                       ;; DE = bg_pen
        add  hl, de
        ld   b, (hl)                    ;; B = 4 background pixels

        ld   hl, cpct_char2pxM1
        ld   (hl), b                    ;; entry 0 = BG-BG-BG-BG
        inc  hl
        ld   a, b                       ;; A = BG-BG-BG-BG
setdc_loop:
        ld   de, 0xEEDD                 ;; D=0xEE [1110|1110], E=0xDD [1101|1101]
        xor  c                          ;; [BG/FG]-BG-BG-FG
        and  d
        xor  c
        ld   (hl), a
        inc  hl
        ld   a, b                       ;; [BG/FG]-BG-FG-BG
        xor  c
        and  e
        xor  c
        ld   (hl), a
        inc  hl
        xor  c                          ;; [BG/FG]-BG-FG-FG
        and  d
        xor  c
        ld   (hl), a
        inc  hl
        ld   a, b                       ;; [BG/FG]-FG-BG-BG
        xor  c
        and  0xBB
        xor  c
        ld   (hl), a
        inc  hl
        xor  c                          ;; [BG/FG]-FG-BG-FG
        and  d
        xor  c
        ld   (hl), a
        inc  hl
        ld   a, b                       ;; [BG/FG]-FG-FG-BG
        xor  c
        and  0x99
        xor  c
        ld   (hl), a
        inc  hl
        xor  c                          ;; [BG/FG]-FG-FG-FG
        and  d
        xor  c
        ld   (hl), a
        ld   de, setdc_nopret           ;; flip the terminator NOP<->RET
        ld   a, (de)
        xor  0xC9
        ld   (de), a
setdc_nopret:
        ret                             ;; NOP (1st pass) / RET (2nd pass)
        inc  hl
        ld   a, b                       ;; FG-BG-BG-BG (byte 8)
        xor  c
        and  0x77
        xor  c
        ld   (hl), a
        inc  hl
        ld   b, a                       ;; B = FG-BG-BG-BG for 2nd pass
        jr   setdc_loop

;;-----------------------------------------------------------------------------
;; cpct_drawCharM1_inner_asm  (asm-internal; A = ASCII, HL = video address)
;;   Draws one 8x8 character. Assumes lower ROM is enabled + interrupts off
;;   (the caller, drawStringM1, arranges that). Translated from
;;   cpct_drawCharM1_inner.s.
;;-----------------------------------------------------------------------------
        PUBLIC cpct_drawCharM1_inner_asm
cpct_drawCharM1_inner_asm:
        ld   b, 0x07                    ;; BC = 0x3800 + 8*A (font def in ROM)
        rla
        rl   b
        rla
        rl   b
        rla
        rl   b
        ld   c, a
charm1_nextrow:
        ex   de, hl                     ;; DE = video dest, HL free
        ld   hl, cpct_char2pxM1
        ld   a, (bc)                    ;; row bits; high nibble = first 4 pixels
        rrca
        rrca
        rrca
        rrca
        and  0x0F
        add  a, l                       ;; HL += A  (A in 0..15)
        ld   l, a
        adc  a, h
        sub  l
        ld   h, a
        ld   a, (hl)
        ld   (de), a                    ;; write first 4 pixels
        inc  de
        ld   hl, cpct_char2pxM1
        ld   a, (bc)                    ;; row bits; low nibble = next 4 pixels
        and  0x0F
        add  a, l
        ld   l, a
        adc  a, h
        sub  l
        ld   h, a
        ld   a, (hl)
        ld   (de), a                    ;; write next 4 pixels
charm1_endpixelline:
        inc  c                          ;; next pixel line of the char
        ld   a, c
        and  0x07
        ret  z                          ;; finished 8 lines -> done
        ld   hl, 0x800-1                ;; next line is 0x800 bytes away (DE already +1)
        add  hl, de
        ld   a, h
        and  0x38                       ;; crossed an 8-line block boundary?
        jr   nz, charm1_nextrow
        ld   de, 0xC050                 ;; yes: relocate to start of next char line
        add  hl, de
        jr   charm1_nextrow

;;-----------------------------------------------------------------------------
;; void cpct_drawStringM1( void *string, void *video_mem ) __z88dk_callee
;;   callee: after the prologue below  IY = string, HL = video address.
;;   Translated from cpct_drawStringM1.asm + _cbindings.s. The IY save/restore
;;   self-modifying idiom is rendered as a plain RAM word (identical effect).
;;-----------------------------------------------------------------------------
        PUBLIC _cpct_drawStringM1
_cpct_drawStringM1:
        ld   (strm1_saveiy), iy         ;; save caller IY
        pop  hl                         ;; HL = return address
        pop  iy                         ;; IY = string pointer
        ex   (sp), hl                   ;; HL = video address ; ret addr back on stack

        ld   a, (_cpct_mode_rom_status)
        and  0xFB                       ;; enable lower ROM (clear bit 2) to read the font
        ld   b, GA_port_byte
        di                              ;; firmware off while lower ROM is paged in
        out  (c), a
        jr   strm1_first
strm1_next:
        push hl
        call cpct_drawCharM1_inner_asm
        pop  hl
        inc  hl                         ;; HL += 2 (next char cell, 8 px right in mode 1)
        inc  hl
        inc  iy                         ;; next char in string
strm1_first:
        ld   a, (iy+0)
        or   a
        jr   nz, strm1_next
        ld   a, (_cpct_mode_rom_status) ;; restore previous mode/rom status
        ld   b, GA_port_byte
        out  (c), a
        ei
        ld   iy, (strm1_saveiy)         ;; restore caller IY
        ret

strm1_saveiy:
        defw 0

;;-----------------------------------------------------------------------------
;; RAGE1 - CPC backend : translated cpctelera graphics primitives (Phase R4)
;;
;; Hand-translated / re-derived sdas -> z88dk z80asm from cpctelera
;; (pinned 662fc885):
;;   src/video/cpct_getScreenPtr.asm      (+ _cbindings.s)  -> byte (x,y) -> vmem ptr
;;   src/sprites/cpct_drawSprite.asm      (+ _cbindings.s)  -> solid sprite blit
;;   src/video/cpct_setBorder / GA border-ink set
;;
;; cpctelera is LGPL-3.0 (c) ronaldo / Fremos / Cheesetea / ByteRealms
;; (@FranGallegoBR). These translations are LGPL-derived works, built as
;; ordinary engine asm.  The external/cpctelera submodule (canonical reference)
;; was removed at R10; these translations derive from cpctelera commit 662fc885.
;; See engine/src/cpc/README.md.
;;
;; cpct_drawSprite here is a CLEAN, FAITHFUL re-derivation: cpctelera's
;; original uses a 63-LDI self-modifying unroll (which cannot run from ROM and
;; bloats the binary). We keep the load-bearing CPC video-memory address
;; stepping EXACTLY (0x0800 between the 8 pixel lines of a char row, 0xC050
;; wrap to the next char row) but copy each line with a plain LDIR loop. The
;; visible result is byte-identical; only the inner copy strategy differs.
;; (Permitted by cpc-renderer.md R-1 mitigation: "hand-write the equivalent
;; z80asm from cpctelera's API docs".)
;;-----------------------------------------------------------------------------

        MODULE cpct_gfx_m1

        defc GA_port_byte = 0x7F        ;; 8-bit port of the Gate Array
        defc PAL_INKR     = 0x40        ;; GA "set INK of selected PEN/border" cmd
        defc PAL_BORDER   = 0x10        ;; "border" is PEN 16 on the Gate Array

;;-----------------------------------------------------------------------------
;; u8* cpct_getScreenPtr( void *screen_start, u8 x_byte, u8 y_byte ) __z88dk_callee
;;   Returns (in HL) the video-memory byte address of byte-column x_byte,
;;   pixel-row y_byte, relative to screen_start (normally 0xC000).
;;   addr = screen_start + 2048*(y>>3) + 80*(y>>3 ... )  -- see derivation below.
;;
;;   Faithful translation of cpctelera cpct_getScreenPtr (+ _cbindings.s).
;;   callee: params on stack.  After the pop sequence below:
;;     DE = screen_start, B = y_byte, C = x_byte.
;;-----------------------------------------------------------------------------
        PUBLIC _cpct_getScreenPtr
_cpct_getScreenPtr:
        pop  af                         ;; AF = return address
        pop  de                         ;; DE = screen_start
        pop  bc                         ;; B = y_byte, C = x_byte
        push af                         ;; ret addr back on stack (__z88dk_callee)

        ;; HL = 256*(Y%8) + 8*int(Y/8)
        ld   a, b                       ;; A = Y
        and  0x07                       ;; A = Y % 8  (pixel line within char row, L)
        ld   h, a                       ;; H = L
        ld   a, b                       ;; A = Y
        and  0xF8                       ;; A = 8*int(Y/8)  (char row * 8)
        ld   l, a                       ;; L = 8*R   ;; HL = 256*L + 8*R

        ;; turn 8*R into 10*R so HL = 256*L + 10*R
        rrca                            ;; A = 2*int(Y/8)
        rrca
        add  a, l                       ;; A = 8*int(Y/8) + 2*int(Y/8) = 10*int(Y/8)
        ld   l, a                       ;; L = 10*R   ;; HL = 256*L + 10*R

        ;; HL *= 8  -> 2048*L + 80*R
        add  hl, hl
        add  hl, hl
        add  hl, hl

        ;; add X-coordinate (byte) and screen start
        ld   b, 0                       ;; BC = X (C already = x_byte)
        add  hl, bc                     ;; HL += X
        add  hl, de                     ;; HL += screen_start
        ret

;;-----------------------------------------------------------------------------
;; void cpct_drawSprite( void *sprite, void *memory, u8 width, u8 height )
;;        __z88dk_callee
;;   Copies a solid (no-mask) WxH-byte sprite into CPC video memory honouring
;;   the CPC's interleaved pixel-line layout.
;;     sprite = source pixel bytes (row-major, width bytes/row)
;;     memory = destination video address (e.g. from cpct_getScreenPtr)
;;     width  = sprite width in BYTES (mode 1: 1 byte = 4 px)
;;     height = sprite height in pixel rows (>0)
;;
;;   callee: after the pops below  HL = sprite, DE = memory, C = width, B = height.
;;-----------------------------------------------------------------------------
        PUBLIC _cpct_drawSprite
_cpct_drawSprite:
        pop  af                         ;; AF = return address
        pop  hl                         ;; HL = sprite source
        pop  de                         ;; DE = destination (video mem)
        pop  bc                         ;; B = height, C = width
        push af                         ;; ret addr back on stack (__z88dk_callee)

        ;; We keep: H'L' free for line maths via the stack-saved width.
        ld   a, c                       ;; A = width (bytes/row)
        ld   (ds_width), a              ;; remember width for the per-line LDIR
        ld   a, b                       ;; A = height counter (pixel rows)

ds_next_line:
        ;; copy one sprite line: width bytes from (HL) -> (DE)
        push af                         ;; save row counter
        ld   a, (ds_width)
        ld   c, a
        ld   b, 0                       ;; BC = width
        ldir                            ;; HL += width, DE += width
        pop  af                         ;; A = row counter

        dec  a
        ret  z                          ;; all rows done

        ;; advance DE to the next pixel line.
        ;; Within an 8-line char block, consecutive lines are 0x0800 apart.
        ;; DE currently sits just past the end of the line just drawn, i.e.
        ;; (line_start + width).  Next line start = line_start + 0x0800
        ;;   = DE - width + 0x0800.
        push af                         ;; save counter
        ld   a, (ds_width)
        ld   c, a
        ld   b, 0                       ;; BC = width
        ex   de, hl                     ;; HL = dest (we need 16-bit maths on it)
        or   a
        sbc  hl, bc                     ;; HL = line_start
        ld   bc, 0x0800
        add  hl, bc                     ;; HL = line_start + 0x0800
        ;; did we cross the 8-line char-block boundary?  Bits 13..11 of the
        ;; address are 0 only when we wrapped past the block (cpctelera trick).
        ld   a, h
        and  0x38
        jr   nz, ds_no_wrap
        ;; wrapped past the 16K char-block: cpctelera advances a further 0xC050
        ;; (= 48K+0x50 mod 64K), which relocates to the next char row.
        ld   bc, 0xC050
        add  hl, bc                     ;; HL = line_start + 0x0800 + 0xC050
ds_no_wrap:
        ex   de, hl                     ;; DE = next line start
        pop  af                         ;; A = counter
        jr   ds_next_line

ds_width:
        defb 0

;;-----------------------------------------------------------------------------
;; void cpct_setBorder( u8 hw_ink ) __z88dk_fastcall
;;   Sets the CPC border colour. fastcall: hw_ink in L (the 6-bit GA hardware
;;   ink value, NOT firmware index).  Border is PEN 16 on the Gate Array.
;;-----------------------------------------------------------------------------
        PUBLIC _cpct_setBorder
_cpct_setBorder:
        ld   c, l                       ;; C = hw_ink
        ld   b, GA_port_byte            ;; B = 0x7F
        ld   a, PAL_BORDER              ;; select PEN 16 (border): cmd 0x00 | 16
        out  (c), a
        ld   a, PAL_INKR                ;; INKR command (0x40)
        or   c                          ;; A = 0x40 | hw_ink
        out  (c), a                     ;; set border ink
        ret

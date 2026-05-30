;;-----------------------------------------------------------------------------
;; RAGE1 - CPC backend : translated cpctelera video primitives (Phase R1-5/R2)
;;
;; Hand-translated sdas -> z88dk z80asm from cpctelera (pinned 662fc885):
;;   src/video/cpct_setVideoMode.asm (+ _cbindings.s)
;;   src/video/cpct_setPALColour.asm (+ _cbindings.s)
;;   src/video/videomode.s        (constants)
;;   src/firmware/cpc_mode_rom_status.s (mode/rom status byte)
;;
;; cpctelera is LGPL-3.0 (c) ronaldo / Fremos / Cheesetea / ByteRealms
;; (@FranGallegoBR). These translations are LGPL-derived works; cpctelera
;; stays pinned in external/cpctelera as the canonical reference and is
;; never compiled by RAGE1 (z88dk has no sdasz80). See engine/src/cpc/README.md.
;;-----------------------------------------------------------------------------

        MODULE cpct_video_poc

        defc GA_port_byte = 0x7F        ;; 8-bit port of the Gate Array
        defc PAL_INKR     = 0x40        ;; GA "set INK of selected PEN" command

;;-----------------------------------------------------------------------------
;; Mode / ROM / interrupt-generator status byte. Shared with the strings
;; module (which toggles lower-ROM to read the font). Default 0x8D matches
;; cpctelera's cpc_mode_rom_status.s (mode 1, upper+lower ROM disabled).
;;-----------------------------------------------------------------------------
        PUBLIC _cpct_mode_rom_status
_cpct_mode_rom_status:
        defb 0x8D

;;-----------------------------------------------------------------------------
;; void cpct_setVideoMode( u8 videoMode ) __z88dk_fastcall
;;   fastcall: videoMode in L.  Sends SET_VIDEO_MODE to the Gate Array.
;;-----------------------------------------------------------------------------
        PUBLIC _cpct_setVideoMode
_cpct_setVideoMode:
        ld   c, l                       ;; C = video mode (0..3)
        ld   hl, _cpct_mode_rom_status
        ld   a, (hl)                    ;; A = current mode/rom/int status
        and  0xFC                       ;; clear the 2 mode bits
        or   c                          ;; insert requested mode
        ld   b, GA_port_byte            ;; B = 0x7F (GA port hi byte; lo byte ignored by GA)
        out  (c), a                     ;; GA: set video mode
        ld   (hl), a                    ;; remember new status
        ret

;;-----------------------------------------------------------------------------
;; void cpct_setPALColour( u8 pen, u8 hw_ink ) __z88dk_callee
;;   callee: params on stack; after the pop/ex below  L = pen, H = hw_ink.
;;-----------------------------------------------------------------------------
        PUBLIC _cpct_setPALColour
_cpct_setPALColour:
        pop  hl                         ;; HL = return address
        ex   (sp), hl                   ;; L = pen, H = hw_ink ; ret addr back on stack
        ld   b, GA_port_byte            ;; B = 0x7F
        out  (c), l                     ;; GA: select PEN (PENR cmd 0x00 | pen, in L)
        ld   a, PAL_INKR                ;; A = INKR command (0x40)
        or   h                          ;; A = 0x40 | hw_ink
        out  (c), a                     ;; GA: set INK of the selected PEN
        ret

; spike_zx.asm — AU1-3 spike wrapper, ZX Spectrum target
;
; Assembles the Arkos2 AKG player with PLY_AKG_HARDWARE_SPECTRUM defined.
; Source: PlayerAkg.asm (copied verbatim from
; tests/arkos/binary-tests/PlayerAkg.asm but with the line
;   PLY_AKG_HARDWARE_SPECTRUM = 1
; stripped — the hardware define is now injected here.

        PLY_AKG_HARDWARE_SPECTRUM = 1
        PLY_AKG_MANAGE_SOUND_EFFECTS = 1

        INCLUDE "PlayerAkg.asm"

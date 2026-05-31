;;
;; RAGE1 - Retro Adventure Game Engine, release 1
;; (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
;;
;; This code is published under a GNU GPL license version 3 or later.  See
;; LICENSE file in the distribution for details.
;;

;;
;; Spectrum-variant include wrapper for the Arkos2 AKG player (Phase AU4-4).
;;
;; The actual player asm now lives at the SHARED canonical location
;;   engine/banked_code/audio/arkos2_player.asm
;; (one copy, used by both ZX and — eventually — CPC backends).
;;
;; This wrapper selects the SPECTRUM hardware variant and includes the shared
;; player. The shared player defaults to PLY_AKG_HARDWARE_SPECTRUM when no
;; hardware symbol is set, so the assembled ZX bytes are BYTE-IDENTICAL to the
;; pre-move single-file player. AU5 adds the companion CPC wrapper
;; (audio_cpc_ay_arkos2_player_asm.inc) which sets PLY_AKG_HARDWARE_CPC instead.
;;

defc PLY_AKG_HARDWARE_SPECTRUM = 1
include "engine/banked_code/audio/arkos2_player.asm"

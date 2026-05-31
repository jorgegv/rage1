;;
;; RAGE1 - Retro Adventure Game Engine, release 1
;; (c) Copyright 2020 Jorge Gonzalez Villalonga <jorgegv@daikon.es>
;;
;; This code is published under a GNU GPL license version 3 or later.  See
;; LICENSE file in the distribution for details.
;;

;;
;; CPC-variant include wrapper for the Arkos2 AKG player (Phase AU5-1).
;;
;; The actual player asm lives at the SHARED canonical location
;;   engine/banked_code/audio/arkos2_player.asm
;; (one copy, used by both ZX and CPC backends). This wrapper selects the CPC
;; hardware variant (PLY_AKG_HARDWARE_CPC), which makes the player's
;; PLY_AKG_SENDPSGREGISTERS routine drive the PSG through the 8255 PPI (the
;; CPC has no AY ports) instead of the Spectrum register/data ports.
;;
;; The C stubs (the _ply_akg_* -> PLY_AKG_* zcc entry points) are SHARED with
;; the ZX path — the C calling convention is identical; only the PSG output
;; hardware differs. The CPC C bindings (engine/src/audio_cpc_ay_arkos2.c)
;; pull this file in via an __asm include, mirroring the ZX wrapper
;; (engine/banked_code/128/audio_zx_ay_arkos2.c -> arkos2-player_asm.inc).
;;

defc PLY_AKG_HARDWARE_CPC = 1
include "engine/banked_code/128/arkos2-stubs_asm.inc"
include "engine/banked_code/audio/arkos2_player.asm"

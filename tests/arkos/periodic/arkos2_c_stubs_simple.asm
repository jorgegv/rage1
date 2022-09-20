;;
;; C stubs for Arkos invocation from zcc
;;

section code_compiler

;; public C symbols
PUBLIC _ply_akg_init
PUBLIC _ply_akg_play
PUBLIC _ply_akg_stop
PUBLIC _ply_akg_initsoundeffects
PUBLIC _ply_akg_playsoundeffect

;; external Arkos 2 entry points
EXTERN PLY_AKG_INIT
EXTERN PLY_AKG_INITSOUNDEFFECTS
EXTERN PLY_AKG_PLAY
EXTERN PLY_AKG_PLAYSOUNDEFFECT
EXTERN PLY_AKG_STOP


;;
;; void ply_akg_init( void *song, uint8_t subsong ) __z88dk_callee;
;;   (params pushed on the stack right to left, all 16-bit)
;;
_ply_akg_init:
	pop bc		; BC = retaddr
	pop hl		; HL = song address
	pop af		; A = subsong number
	push bc		; restore retaddr
	jp PLY_AKG_INIT

;;
;; void ply_akg_play( void );
;;
defc _ply_akg_play = PLY_AKG_PLAY

;;
;; void ply_akg_stop( void );
;;
defc _ply_akg_stop = PLY_AKG_STOP


;;
;; void ply_akg_initsoundeffects( void *effects_table ) __z88dk_fastcall;
;;   (param in HL)
;;
defc _ply_akg_initsoundeffects = PLY_AKG_INITSOUNDEFFECTS


;;
;; void _ply_akg_playsoundeffect( uint8_t effect ) __z88dk_fastcall;
;;   (param in HL)
;;
_ply_akg_playsoundeffect = PLY_AKG_PLAYSOUNDEFFECT
	ld a,l
	jp PLY_AKG_PLAYSOUNDEFFECT

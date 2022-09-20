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
	push ix
	push iy
	call PLY_AKG_INIT
	pop iy
	pop ix
	ret

;;
;; void ply_akg_play( void );
;;
_ply_akg_play:
	push ix
	push iy
	call PLY_AKG_PLAY
	pop iy
	pop ix
	ret

;;
;; void ply_akg_stop( void );
;;
_ply_akg_stop:
	push ix
	push iy
	call PLY_AKG_STOP
	pop iy
	pop ix
	ret


;;
;; void ply_akg_initsoundeffects( void *effects_table ) __z88dk_fastcall;
;;   (param in HL)
;;
_ply_akg_initsoundeffects:
	push ix
	push iy
	call PLY_AKG_INITSOUNDEFFECTS
	pop iy
	pop ix
	ret


;;
;; void _ply_akg_playsoundeffect( uint8_t effect ) __z88dk_fastcall;
;;   (param in HL)
;;
_ply_akg_playsoundeffect:
	ld a,l
	push ix
	push iy
	call PLY_AKG_PLAYSOUNDEFFECT
	pop iy
	pop ix
	ret

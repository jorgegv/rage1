;// Churrera Engine
;// ===============
;// Copyleft 2010, 2011, 2012, 2013 by The Mojon Twins
;
;// beeper.h
;// Cointains Beeper sound effects
;
;// Most effects have been taken off beep_fx's demo project.
;// So I guess they should be credited to Shiru again ;)
;
;// Adaptation for direct fx address and fastcall by JorgeGV 2021
;

        SECTION code_compiler

; void bit_beepfx_fastcall(void *bfx) __z88dk_fastcall

PUBLIC _bit_beepfx_fastcall

_bit_beepfx_fastcall:

.sound_play
	
	push ix
	push iy

	push hl
	pop ix			;put it into ix

.readData
	ld a,(ix+0)		;read block type
	or a
	jr nz,readData_sound
	pop iy
	pop ix
;	ei
	ret
	
.readData_sound
	ld c,(ix+1)		;read duration 1
	ld b,(ix+2)
	ld e,(ix+3)		;read duration 2
	ld d,(ix+4)
	push de
	pop iy

	dec a
	jr nz,sfxRoutineNoise



;this routine generate tone with many parameters

.sfxRoutineTone
	ld e,(ix+5)		;freq
	ld d,(ix+6)
	ld a,(ix+9)		;duty
	ld (sfxRoutineTone_duty + 1),a
	ld hl,0

.sfxRoutineTone_l0
	push bc
	push iy
	pop bc
.sfxRoutineTone_l1
	add hl,de
	ld a,h
.sfxRoutineTone_duty
	cp 0
	sbc a,a
	and 16
.sfxRoutineTone_border
	or 0
	out ($fe),a

	dec bc
	ld a,b
	or c
	jr nz,sfxRoutineTone_l1

	ld a,(sfxRoutineTone_duty + 1)
	add a,(ix+10)	;duty change
	ld (sfxRoutineTone_duty + 1),a

	ld c,(ix+7)		;slide
	ld b,(ix+8)
	ex de,hl
	add hl,bc
	ex de,hl

	pop bc
	dec bc
	ld a,b
	or c
	jr nz,sfxRoutineTone_l0

	ld c,11
.nextData
	add ix,bc		;skip to the next block
	jr readData

;this routine generate noise with two parameters

.sfxRoutineNoise
	ld e,(ix+5)		;pitch

	ld d,1
	ld h,d
	ld l,d
.sfxRoutineNoise_l0
	push bc
	push iy
	pop bc
.sfxRoutineNoise_l1
	ld a,(hl)
	and 16
.sfxRoutineNoise_border
	or 0
	out ($fe),a
	dec d
	jr nz,sfxRoutineNoise_l2
	ld d,e
	inc hl
	ld a,h
	and $1f
	ld h,a
.sfxRoutineNoise_l2
	dec bc
	ld a,b
	or c
	jr nz,sfxRoutineNoise_l1

	ld a,e
	add a,(ix+6)	;slide
	ld e,a

	pop bc
	dec bc
	ld a,b
	or c
	jr nz,sfxRoutineNoise_l0

	ld c,7
	jr nextData
	
;// end

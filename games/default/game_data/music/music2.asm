section data_compiler
public _tracker_song_menu_song
_tracker_song_menu_song:
; A Harmless Grenade, AKG format, v1.0.

; Generated by Arkos Tracker 2.

Start:
StartDisarkGenerateExternalLabel:

DisarkByteRegionStart0:
	db "AT20"
DisarkPointerRegionStart1:
	dw ArpeggioTable	; The address of the Arpeggio table.
	dw PitchTable	; The address of the Pitch table.
	dw InstrumentTable	; The address of the Instrument table.
	dw EffectBlockTable	; The address of the Effect Block table.
DisarkPointerRegionEnd1:


; The addresses of each Subsong:
DisarkPointerRegionStart2:
	dw Subsong0_Start
DisarkPointerRegionEnd2:

; Declares all the Arpeggios.
ArpeggioTable:
DisarkPointerRegionStart3:
	dw Arpeggio1
	dw Arpeggio2
DisarkPointerRegionEnd3:

Arpeggio1:
	db 1	; The speed.

	db 0
	db 12
	db 9
	db -12
	db 18
	db -128
DisarkWordForceReference4:
	dw Arpeggio1 + 0 + 1	; Loop.

Arpeggio2:
	db 1	; The speed.

	db 0
	db 6
	db -3
	db -12
	db -6
	db 0
	db 12
	db -128
DisarkWordForceReference5:
	dw Arpeggio2 + 0 + 1	; Loop.

; Declares all the Pitches.
PitchTable:
DisarkPointerRegionStart6:
	dw Pitch1
DisarkPointerRegionEnd6:

Pitch1:
	db 2	; The speed.

	dw 0
Pitch1_GotoNextForLine0:
DisarkWordForceReference7:
	dw Pitch1_GotoNextForLine0 + 2
	dw 0
Pitch1_GotoNextForLine1:
DisarkWordForceReference8:
	dw Pitch1_GotoNextForLine1 + 2
	dw 0
Pitch1_GotoNextForLine2:
DisarkWordForceReference9:
	dw Pitch1_GotoNextForLine2 + 2
	dw -1
Pitch1_GotoNextForLine3:
DisarkWordForceReference10:
	dw Pitch1_GotoNextForLine3 + 2
	dw -4
Pitch1_GotoNextForLine4:
DisarkWordForceReference11:
	dw Pitch1_GotoNextForLine4 + 2
	dw 2
DisarkWordForceReference12:
	dw Pitch1 + 4 * 2 + 1

; Declares all the Instruments.
InstrumentTable:
DisarkPointerRegionStart13:
	dw EmptyInstrument
	dw Instrument1
	dw Instrument2
	dw Instrument3
	dw Instrument4
	dw Instrument5
	dw Instrument6
	dw Instrument7
	dw Instrument8
	dw Instrument9
	dw Instrument10
	dw Instrument11
	dw Instrument12
	dw Instrument13
	dw Instrument14
	dw Instrument15
	dw Instrument16
	dw Instrument17
	dw Instrument18
	dw Instrument19
DisarkPointerRegionEnd13:

EmptyInstrument:
	db 0	; The speed (>0, 0 for 256).
EmptyInstrument_Loop:	db 0	; No Soft no Hard. Volume: 0. Noise? false.

	db 6	; Loop to silence.

Instrument1:
	db 2	; The speed (>0, 0 for 256).
	db 2	; Soft to Hard. Envelope: 8. Retrig ? false. Noise ? false.
	db 34	; Complex case. Ratio: 5
	db 12	; Arpeggio.

	db 2	; Soft to Hard. Envelope: 8. Retrig ? false. Noise ? false.
	db 36	; Complex case. Ratio: 3
	db 12	; Arpeggio.

	db 2	; Soft to Hard. Envelope: 8. Retrig ? false. Noise ? false.
	db 36	; Complex case. Ratio: 3
	db 12	; Arpeggio.

	db 2	; Soft to Hard. Envelope: 8. Retrig ? false. Noise ? false.
	db 130	; Simple case. Ratio: 5

	db 81	; Soft only. Volume: 10.
	db 64	; Additional data. Noise: 0. Pitch? false. Arp? true. Period? false.
	db 12	; Arpeggio.

	db 209	; Soft only. Volume: 10. Volume only.

	db 81	; Soft only. Volume: 10.
	db 64	; Additional data. Noise: 0. Pitch? false. Arp? true. Period? false.
	db 12	; Arpeggio.

	db 201	; Soft only. Volume: 9. Volume only.

	db 193	; Soft only. Volume: 8. Volume only.

	db 6	; Loop to silence.

Instrument2:
	db 1	; The speed (>0, 0 for 256).
	db 121	; Soft only. Volume: 15.
	db 2	; Additional data. Noise: 2. Pitch? false. Arp? false. Period? false.

	db 121	; Soft only. Volume: 15.
	db 33	; Additional data. Noise: 1. Pitch? true. Arp? false. Period? false.
	dw 32	; Pitch.

	db 121	; Soft only. Volume: 15.
	db 32	; Additional data. Noise: 0. Pitch? true. Arp? false. Period? false.
	dw 48	; Pitch.

	db 121	; Soft only. Volume: 15.
	db 32	; Additional data. Noise: 0. Pitch? true. Arp? false. Period? false.
	dw 68	; Pitch.

	db 121	; Soft only. Volume: 15.
	db 32	; Additional data. Noise: 0. Pitch? true. Arp? false. Period? false.
	dw 116	; Pitch.

	db 121	; Soft only. Volume: 15.
	db 32	; Additional data. Noise: 0. Pitch? true. Arp? false. Period? false.
	dw 228	; Pitch.

	db 113	; Soft only. Volume: 14.
	db 32	; Additional data. Noise: 0. Pitch? true. Arp? false. Period? false.
	dw 180	; Pitch.

	db 105	; Soft only. Volume: 13.
	db 32	; Additional data. Noise: 0. Pitch? true. Arp? false. Period? false.
	dw 292	; Pitch.

	db 6	; Loop to silence.

Instrument3:
	db 1	; The speed (>0, 0 for 256).
	db 248	; No Soft no Hard. Volume: 15. Noise? true.
	db 1	; Noise: 1.

	db 216	; No Soft no Hard. Volume: 11. Noise? true.
	db 1	; Noise: 1.

	db 184	; No Soft no Hard. Volume: 7. Noise? true.
	db 1	; Noise: 1.

	db 6	; Loop to silence.

Instrument4:
	db 1	; The speed (>0, 0 for 256).
	db 248	; No Soft no Hard. Volume: 15. Noise? true.
	db 4	; Noise: 4.

	db 200	; No Soft no Hard. Volume: 9. Noise? true.
	db 1	; Noise: 1.

	db 6	; Loop to silence.

Instrument5:
	db 1	; The speed (>0, 0 for 256).
Instrument5_Loop:	db 248	; No Soft no Hard. Volume: 15. Noise? true.
	db 1	; Noise: 1.

	db 200	; No Soft no Hard. Volume: 9. Noise? true.
	db 1	; Noise: 1.

	db 176	; No Soft no Hard. Volume: 6. Noise? true.
	db 1	; Noise: 1.

	db 7	; Loop.
DisarkWordForceReference14:
	dw Instrument5_Loop	; Loop here.

Instrument6:
	db 4	; The speed (>0, 0 for 256).
	db 248	; No Soft no Hard. Volume: 15. Noise? true.
	db 1	; Noise: 1.

	db 6	; Loop to silence.

Instrument7:
	db 3	; The speed (>0, 0 for 256).
	db 249	; Soft only. Volume: 15. Volume only.

	db 233	; Soft only. Volume: 13. Volume only.

	db 225	; Soft only. Volume: 12. Volume only.

	db 217	; Soft only. Volume: 11. Volume only.

	db 209	; Soft only. Volume: 10. Volume only.

	db 201	; Soft only. Volume: 9. Volume only.

	db 193	; Soft only. Volume: 8. Volume only.

	db 185	; Soft only. Volume: 7. Volume only.

	db 177	; Soft only. Volume: 6. Volume only.

	db 169	; Soft only. Volume: 5. Volume only.

	db 161	; Soft only. Volume: 4. Volume only.

	db 153	; Soft only. Volume: 3. Volume only.

	db 145	; Soft only. Volume: 2. Volume only.

	db 137	; Soft only. Volume: 1. Volume only.

	db 6	; Loop to silence.

Instrument8:
	db 1	; The speed (>0, 0 for 256).
Instrument8_Loop:	db 34	; Soft to Hard. Envelope: 10. Retrig ? false. Noise ? false.
	db 131	; Simple case. Ratio: 4

	db 7	; Loop.
DisarkWordForceReference15:
	dw Instrument8_Loop	; Loop here.

Instrument9:
	db 1	; The speed (>0, 0 for 256).
	db 248	; No Soft no Hard. Volume: 15. Noise? true.
	db 2	; Noise: 2.

	db 241	; Soft only. Volume: 14. Volume only.

	db 105	; Soft only. Volume: 13.
	db 33	; Additional data. Noise: 1. Pitch? true. Arp? false. Period? false.
	dw 208	; Pitch.

	db 89	; Soft only. Volume: 11.
	db 33	; Additional data. Noise: 1. Pitch? true. Arp? false. Period? false.
	dw 400	; Pitch.

	db 216	; No Soft no Hard. Volume: 11. Noise? true.
	db 1	; Noise: 1.

	db 216	; No Soft no Hard. Volume: 11. Noise? true.
	db 3	; Noise: 3.

	db 208	; No Soft no Hard. Volume: 10. Noise? true.
	db 4	; Noise: 4.

	db 200	; No Soft no Hard. Volume: 9. Noise? true.
	db 1	; Noise: 1.

	db 6	; Loop to silence.

Instrument10:
	db 5	; The speed (>0, 0 for 256).
Instrument10_Loop:	db 2	; Soft to Hard. Envelope: 8. Retrig ? false. Noise ? false.
	db 130	; Simple case. Ratio: 5

	db 7	; Loop.
DisarkWordForceReference16:
	dw Instrument10_Loop	; Loop here.

Instrument11:
	db 2	; The speed (>0, 0 for 256).
Instrument11_Loop:	db 2	; Soft to Hard. Envelope: 8. Retrig ? false. Noise ? false.
	db 35	; Complex case. Ratio: 4
	db 12	; Arpeggio.

	db 2	; Soft to Hard. Envelope: 8. Retrig ? false. Noise ? false.
	db 35	; Complex case. Ratio: 4
	db 12	; Arpeggio.

	db 120	; No Soft no Hard. Volume: 15. Noise? false.

	db 7	; Loop.
DisarkWordForceReference17:
	dw Instrument11_Loop	; Loop here.

Instrument12:
	db 1	; The speed (>0, 0 for 256).
Instrument12_Loop:	db 249	; Soft only. Volume: 15. Volume only.

	db 7	; Loop.
DisarkWordForceReference18:
	dw Instrument12_Loop	; Loop here.

Instrument13:
	db 1	; The speed (>0, 0 for 256).
	db 249	; Soft only. Volume: 15. Volume only.

	db 6	; Loop to silence.

Instrument14:
	db 1	; The speed (>0, 0 for 256).
Instrument14_Loop:	db 34	; Soft to Hard. Envelope: 10. Retrig ? false. Noise ? false.
	db 132	; Simple case. Ratio: 3

	db 7	; Loop.
DisarkWordForceReference19:
	dw Instrument14_Loop	; Loop here.

Instrument15:
	db 2	; The speed (>0, 0 for 256).
	db 249	; Soft only. Volume: 15. Volume only.

Instrument15_Loop:	db 113	; Soft only. Volume: 14.
	db 32	; Additional data. Noise: 0. Pitch? true. Arp? false. Period? false.
	dw -5	; Pitch.

	db 225	; Soft only. Volume: 12. Volume only.

	db 89	; Soft only. Volume: 11.
	db 32	; Additional data. Noise: 0. Pitch? true. Arp? false. Period? false.
	dw 5	; Pitch.

	db 249	; Soft only. Volume: 15. Volume only.

	db 105	; Soft only. Volume: 13.
	db 32	; Additional data. Noise: 0. Pitch? true. Arp? false. Period? false.
	dw -7	; Pitch.

	db 201	; Soft only. Volume: 9. Volume only.

	db 81	; Soft only. Volume: 10.
	db 32	; Additional data. Noise: 0. Pitch? true. Arp? false. Period? false.
	dw 32	; Pitch.

	db 217	; Soft only. Volume: 11. Volume only.

	db 225	; Soft only. Volume: 12. Volume only.

	db 241	; Soft only. Volume: 14. Volume only.

	db 7	; Loop.
DisarkWordForceReference20:
	dw Instrument15_Loop	; Loop here.

Instrument16:
	db 1	; The speed (>0, 0 for 256).
	db 232	; No Soft no Hard. Volume: 13. Noise? true.
	db 5	; Noise: 5.

	db 216	; No Soft no Hard. Volume: 11. Noise? true.
	db 5	; Noise: 5.

	db 208	; No Soft no Hard. Volume: 10. Noise? true.
	db 5	; Noise: 5.

	db 200	; No Soft no Hard. Volume: 9. Noise? true.
	db 5	; Noise: 5.

	db 184	; No Soft no Hard. Volume: 7. Noise? true.
	db 5	; Noise: 5.

	db 6	; Loop to silence.

Instrument17:
	db 1	; The speed (>0, 0 for 256).
	db 232	; No Soft no Hard. Volume: 13. Noise? true.
	db 9	; Noise: 9.

	db 216	; No Soft no Hard. Volume: 11. Noise? true.
	db 9	; Noise: 9.

	db 208	; No Soft no Hard. Volume: 10. Noise? true.
	db 9	; Noise: 9.

	db 200	; No Soft no Hard. Volume: 9. Noise? true.
	db 9	; Noise: 9.

	db 184	; No Soft no Hard. Volume: 7. Noise? true.
	db 9	; Noise: 9.

	db 6	; Loop to silence.

Instrument18:
	db 1	; The speed (>0, 0 for 256).
	db 232	; No Soft no Hard. Volume: 13. Noise? true.
	db 17	; Noise: 17.

	db 216	; No Soft no Hard. Volume: 11. Noise? true.
	db 17	; Noise: 17.

	db 208	; No Soft no Hard. Volume: 10. Noise? true.
	db 17	; Noise: 17.

	db 200	; No Soft no Hard. Volume: 9. Noise? true.
	db 17	; Noise: 17.

	db 184	; No Soft no Hard. Volume: 7. Noise? true.
	db 17	; Noise: 17.

	db 6	; Loop to silence.

Instrument19:
	db 1	; The speed (>0, 0 for 256).
	db 232	; No Soft no Hard. Volume: 13. Noise? true.
	db 25	; Noise: 25.

	db 216	; No Soft no Hard. Volume: 11. Noise? true.
	db 25	; Noise: 25.

	db 208	; No Soft no Hard. Volume: 10. Noise? true.
	db 25	; Noise: 25.

	db 200	; No Soft no Hard. Volume: 9. Noise? true.
	db 25	; Noise: 25.

	db 184	; No Soft no Hard. Volume: 7. Noise? true.
	db 25	; Noise: 25.

	db 6	; Loop to silence.


; The indexes of the effect blocks used by this song.
EffectBlockTable:
DisarkPointerRegionStart21:
	dw EffectBlock_P20P0P32	; Index 0
	dw EffectBlock_P4P3	; Index 1
	dw EffectBlock_P4P0	; Index 2
	dw EffectBlock_P4P2	; Index 3
	dw EffectBlock_P4P1	; Index 4
	dw EffectBlock_P24P26P255P15	; Index 5
	dw EffectBlock_P28P48	; Index 6
	dw EffectBlock_P3P5P21P0P2P6P1	; Index 7
	dw EffectBlock_P0	; Index 8
	dw EffectBlock_P20P0P16	; Index 9
	dw EffectBlock_P28P57	; Index 10
	dw EffectBlock_P28P51	; Index 11
	dw EffectBlock_P4P4	; Index 12
	dw EffectBlock_P3P2P10P0	; Index 13
	dw EffectBlock_P3P2P6P0	; Index 14
	dw EffectBlock_P5P2P10P0	; Index 15
	dw EffectBlock_P28P54	; Index 16
	dw EffectBlock_P28P58	; Index 17
	dw EffectBlock_P4P5	; Index 18
	dw EffectBlock_P14P0P1	; Index 19
	dw EffectBlock_P20P0P80	; Index 20
	dw EffectBlock_P28P55	; Index 21
	dw EffectBlock_P4P6	; Index 22
	dw EffectBlock_P2P4	; Index 23
	dw EffectBlock_P2P2	; Index 24
DisarkPointerRegionEnd21:

EffectBlock_P0:
	db 0
EffectBlock_P2P2:
	db 2, 2
EffectBlock_P2P4:
	db 2, 4
EffectBlock_P4P0:
	db 4, 0
EffectBlock_P4P1:
	db 4, 1
EffectBlock_P4P2:
	db 4, 2
EffectBlock_P4P3:
	db 4, 3
EffectBlock_P4P4:
	db 4, 4
EffectBlock_P4P5:
	db 4, 5
EffectBlock_P4P6:
	db 4, 6
EffectBlock_P28P48:
	db 28, 48
EffectBlock_P28P51:
	db 28, 51
EffectBlock_P28P54:
	db 28, 54
EffectBlock_P28P55:
	db 28, 55
EffectBlock_P28P57:
	db 28, 57
EffectBlock_P28P58:
	db 28, 58
EffectBlock_P14P0P1:
	db 14, 0, 1
EffectBlock_P20P0P16:
	db 20, 0, 16
EffectBlock_P20P0P32:
	db 20, 0, 32
EffectBlock_P20P0P80:
	db 20, 0, 80
EffectBlock_P3P2P6P0:
	db 3, 2, 6, 0
EffectBlock_P3P2P10P0:
	db 3, 2, 10, 0
EffectBlock_P5P2P10P0:
	db 5, 2, 10, 0
EffectBlock_P3P5P21P0P2P6P1:
	db 3, 5, 21, 0, 2, 6, 1
EffectBlock_P24P26P255P15:
	db 24, 26, 255, 15

DisarkByteRegionEnd0:

; Subsong 0
; ----------------------
Subsong0_DisarkByteRegionStart0:
Subsong0_Start:
	db 2	; ReplayFrequency (0=12.5hz, 1=25, 2=50, 3=100, 4=150, 5=300).
	db 0	; Digichannel (0-2).
	db 1	; PSG count (>0).
	db 0	; Loop start index (>=0).
	db 23	; End index (>=0).
	db 6	; Initial speed (>=0).
	db 5	; Base note index (>=0).

Subsong0_Linker:
Subsong0_DisarkPointerRegionStart1:
; Position 0
Subsong0_Linker_Loop:
	dw Subsong0_Track0
	dw Subsong0_Track22
	dw Subsong0_Track22
	dw Subsong0_LinkerBlock0

; Position 1
	dw Subsong0_Track0
	dw Subsong0_Track1
	dw Subsong0_Track1
	dw Subsong0_LinkerBlock0

; Position 2
	dw Subsong0_Track0
	dw Subsong0_Track1
	dw Subsong0_Track2
	dw Subsong0_LinkerBlock0

; Position 3
	dw Subsong0_Track0
	dw Subsong0_Track1
	dw Subsong0_Track2
	dw Subsong0_LinkerBlock0

; Position 4
	dw Subsong0_Track3
	dw Subsong0_Track5
	dw Subsong0_Track4
	dw Subsong0_LinkerBlock0

; Position 5
	dw Subsong0_Track6
	dw Subsong0_Track8
	dw Subsong0_Track7
	dw Subsong0_LinkerBlock1

; Position 6
	dw Subsong0_Track9
	dw Subsong0_Track10
	dw Subsong0_Track11
	dw Subsong0_LinkerBlock2

; Position 7
	dw Subsong0_Track6
	dw Subsong0_Track8
	dw Subsong0_Track7
	dw Subsong0_LinkerBlock1

; Position 8
	dw Subsong0_Track12
	dw Subsong0_Track13
	dw Subsong0_Track14
	dw Subsong0_LinkerBlock2

; Position 9
	dw Subsong0_Track6
	dw Subsong0_Track8
	dw Subsong0_Track7
	dw Subsong0_LinkerBlock1

; Position 10
	dw Subsong0_Track9
	dw Subsong0_Track10
	dw Subsong0_Track11
	dw Subsong0_LinkerBlock2

; Position 11
	dw Subsong0_Track15
	dw Subsong0_Track16
	dw Subsong0_Track17
	dw Subsong0_LinkerBlock0

; Position 12
	dw Subsong0_Track15
	dw Subsong0_Track16
	dw Subsong0_Track20
	dw Subsong0_LinkerBlock0

; Position 13
	dw Subsong0_Track15
	dw Subsong0_Track16
	dw Subsong0_Track17
	dw Subsong0_LinkerBlock3

; Position 14
	dw Subsong0_Track22
	dw Subsong0_Track23
	dw Subsong0_Track22
	dw Subsong0_LinkerBlock4

; Position 15
	dw Subsong0_Track18
	dw Subsong0_Track19
	dw Subsong0_Track21
	dw Subsong0_LinkerBlock0

; Position 16
	dw Subsong0_Track18
	dw Subsong0_Track19
	dw Subsong0_Track21
	dw Subsong0_LinkerBlock0

; Position 17
	dw Subsong0_Track24
	dw Subsong0_Track19
	dw Subsong0_Track21
	dw Subsong0_LinkerBlock0

; Position 18
	dw Subsong0_Track24
	dw Subsong0_Track19
	dw Subsong0_Track21
	dw Subsong0_LinkerBlock0

; Position 19
	dw Subsong0_Track24
	dw Subsong0_Track19
	dw Subsong0_Track21
	dw Subsong0_LinkerBlock5

; Position 20
	dw Subsong0_Track22
	dw Subsong0_Track23
	dw Subsong0_Track25
	dw Subsong0_LinkerBlock6

; Position 21
	dw Subsong0_Track22
	dw Subsong0_Track23
	dw Subsong0_Track25
	dw Subsong0_LinkerBlock7

; Position 22
	dw Subsong0_Track22
	dw Subsong0_Track23
	dw Subsong0_Track25
	dw Subsong0_LinkerBlock8

; Position 23
	dw Subsong0_Track22
	dw Subsong0_Track23
	dw Subsong0_Track25
	dw Subsong0_LinkerBlock9

Subsong0_DisarkPointerRegionEnd1:
	dw 0	; Loop.
Subsong0_DisarkWordForceReference2:
	dw Subsong0_Linker_Loop

Subsong0_LinkerBlock0:
	db 32	; Height.
	db 0	; Transposition 0.
	db 0	; Transposition 1.
	db 0	; Transposition 2.
Subsong0_DisarkWordForceReference3:
	dw Subsong0_SpeedTrack0	; SpeedTrack address.
Subsong0_DisarkWordForceReference4:
	dw Subsong0_EventTrack0	; EventTrack address.
Subsong0_LinkerBlock1:
	db 24	; Height.
	db 0	; Transposition 0.
	db 0	; Transposition 1.
	db 0	; Transposition 2.
Subsong0_DisarkWordForceReference5:
	dw Subsong0_SpeedTrack0	; SpeedTrack address.
Subsong0_DisarkWordForceReference6:
	dw Subsong0_EventTrack0	; EventTrack address.
Subsong0_LinkerBlock2:
	db 8	; Height.
	db 0	; Transposition 0.
	db 0	; Transposition 1.
	db 0	; Transposition 2.
Subsong0_DisarkWordForceReference7:
	dw Subsong0_SpeedTrack0	; SpeedTrack address.
Subsong0_DisarkWordForceReference8:
	dw Subsong0_EventTrack0	; EventTrack address.
Subsong0_LinkerBlock3:
	db 28	; Height.
	db 0	; Transposition 0.
	db 0	; Transposition 1.
	db 0	; Transposition 2.
Subsong0_DisarkWordForceReference9:
	dw Subsong0_SpeedTrack0	; SpeedTrack address.
Subsong0_DisarkWordForceReference10:
	dw Subsong0_EventTrack0	; EventTrack address.
Subsong0_LinkerBlock4:
	db 4	; Height.
	db 0	; Transposition 0.
	db 0	; Transposition 1.
	db 0	; Transposition 2.
Subsong0_DisarkWordForceReference11:
	dw Subsong0_SpeedTrack0	; SpeedTrack address.
Subsong0_DisarkWordForceReference12:
	dw Subsong0_EventTrack0	; EventTrack address.
Subsong0_LinkerBlock5:
	db 16	; Height.
	db 2	; Transposition 0.
	db 0	; Transposition 1.
	db 2	; Transposition 2.
Subsong0_DisarkWordForceReference13:
	dw Subsong0_SpeedTrack0	; SpeedTrack address.
Subsong0_DisarkWordForceReference14:
	dw Subsong0_EventTrack0	; EventTrack address.
Subsong0_LinkerBlock6:
	db 4	; Height.
	db 0	; Transposition 0.
	db 2	; Transposition 1.
	db 0	; Transposition 2.
Subsong0_DisarkWordForceReference15:
	dw Subsong0_SpeedTrack0	; SpeedTrack address.
Subsong0_DisarkWordForceReference16:
	dw Subsong0_EventTrack0	; EventTrack address.
Subsong0_LinkerBlock7:
	db 4	; Height.
	db 0	; Transposition 0.
	db 10	; Transposition 1.
	db 4	; Transposition 2.
Subsong0_DisarkWordForceReference17:
	dw Subsong0_SpeedTrack0	; SpeedTrack address.
Subsong0_DisarkWordForceReference18:
	dw Subsong0_EventTrack0	; EventTrack address.
Subsong0_LinkerBlock8:
	db 4	; Height.
	db 0	; Transposition 0.
	db 20	; Transposition 1.
	db 8	; Transposition 2.
Subsong0_DisarkWordForceReference19:
	dw Subsong0_SpeedTrack0	; SpeedTrack address.
Subsong0_DisarkWordForceReference20:
	dw Subsong0_EventTrack0	; EventTrack address.
Subsong0_LinkerBlock9:
	db 4	; Height.
	db 0	; Transposition 0.
	db 36	; Transposition 1.
	db 14	; Transposition 2.
Subsong0_DisarkWordForceReference21:
	dw Subsong0_SpeedTrack0	; SpeedTrack address.
Subsong0_DisarkWordForceReference22:
	dw Subsong0_EventTrack0	; EventTrack address.

Subsong0_Track0:
	db 146
	db 1	; New Instrument (1).
	db 60	; Waits for 1 line.

	db 18
	db 18
	db 60	; Waits for 1 line.

	db 18
	db 60	; Waits for 1 line.

	db 18
	db 18
	db 60	; Waits for 1 line.

	db 18
	db 60	; Waits for 1 line.

	db 18
	db 60	; Waits for 1 line.

	db 18
	db 60	; Waits for 1 line.

	db 18
	db 60	; Waits for 1 line.

	db 18
	db 18
	db 60	; Waits for 1 line.

	db 18
	db 60	; Waits for 1 line.

	db 18
	db 18
	db 21
	db 24
	db 27
	db 30
	db 24
	db 19
	db 21
	db 61, 127	; Waits for 128 lines.


Subsong0_Track1:
	db 61, 127	; Waits for 128 lines.


Subsong0_Track2:
	db 211
	db 2	; New Instrument (2).
	db 8	; Index to an effect block.
	db 211
	db 3	; New Instrument (3).
	db 1	; Index to an effect block.
	db 83
	db 2	; Index to an effect block.
	db 83
	db 1	; Index to an effect block.
	db 211
	db 2	; New Instrument (2).
	db 2	; Index to an effect block.
	db 211
	db 4	; New Instrument (4).
	db 4	; Index to an effect block.
	db 211
	db 3	; New Instrument (3).
	db 3	; Index to an effect block.
	db 83
	db 1	; Index to an effect block.
	db 211
	db 2	; New Instrument (2).
	db 2	; Index to an effect block.
	db 211
	db 5	; New Instrument (5).
	db 4	; Index to an effect block.
	db 211
	db 3	; New Instrument (3).
	db 3	; Index to an effect block.
	db 211
	db 4	; New Instrument (4).
	db 1	; Index to an effect block.
	db 211
	db 2	; New Instrument (2).
	db 2	; Index to an effect block.
	db 211
	db 6	; New Instrument (6).
	db 1	; Index to an effect block.
	db 211
	db 4	; New Instrument (4).
	db 18	; Index to an effect block.
	db 211
	db 6	; New Instrument (6).
	db 3	; Index to an effect block.
	db 211
	db 2	; New Instrument (2).
	db 2	; Index to an effect block.
	db 211
	db 3	; New Instrument (3).
	db 3	; Index to an effect block.
	db 211
	db 4	; New Instrument (4).
	db 4	; Index to an effect block.
	db 211
	db 3	; New Instrument (3).
	db 1	; Index to an effect block.
	db 211
	db 2	; New Instrument (2).
	db 2	; Index to an effect block.
	db 211
	db 4	; New Instrument (4).
	db 3	; Index to an effect block.
	db 211
	db 5	; New Instrument (5).
	db 1	; Index to an effect block.
	db 211
	db 4	; New Instrument (4).
	db 4	; Index to an effect block.
	db 211
	db 2	; New Instrument (2).
	db 2	; Index to an effect block.
	db 211
	db 3	; New Instrument (3).
	db 4	; Index to an effect block.
	db 211
	db 5	; New Instrument (5).
	db 1	; Index to an effect block.
	db 83
	db 12	; Index to an effect block.
	db 211
	db 2	; New Instrument (2).
	db 2	; Index to an effect block.
	db 211
	db 3	; New Instrument (3).
	db 12	; Index to an effect block.
	db 211
	db 4	; New Instrument (4).
	db 3	; Index to an effect block.
	db 147
	db 6	; New Instrument (6).
	db 61, 127	; Waits for 128 lines.


Subsong0_Track3:
	db 255
	db 79	; Escape note (79).
	db 7	; New Instrument (7).
	db 13	; Index to an effect block.
	db 61, 6	; Waits for 7 lines.

	db 63
	db 77	; Escape note (77).
	db 61, 6	; Waits for 7 lines.

	db 63
	db 72	; Escape note (72).
	db 61, 6	; Waits for 7 lines.

	db 63
	db 76	; Escape note (76).
	db 61, 127	; Waits for 128 lines.


Subsong0_Track4:
	db 211
	db 2	; New Instrument (2).
	db 8	; Index to an effect block.
	db 62 + 1 * 64	; Optimized wait for 3 lines.

	db 255
	db 75	; Escape note (75).
	db 7	; New Instrument (7).
	db 15	; Index to an effect block.
	db 61, 6	; Waits for 7 lines.

	db 63
	db 71	; Escape note (71).
	db 61, 6	; Waits for 7 lines.

	db 63
	db 77	; Escape note (77).
	db 61, 6	; Waits for 7 lines.

	db 63
	db 79	; Escape note (79).
	db 61, 127	; Waits for 128 lines.


Subsong0_Track5:
	db 146
	db 8	; New Instrument (8).
	db 61, 127	; Waits for 128 lines.


Subsong0_Track6:
	db 222
	db 10	; New Instrument (10).
	db 8	; Index to an effect block.
	db 124	; No note, but effects.
	db 0	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 30
	db 124	; No note, but effects.
	db 0	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 30
	db 124	; No note, but effects.
	db 0	; Index to an effect block.
	db 128
	db 0	; New Instrument (0).
	db 61, 5	; Waits for 6 lines.

	db 146
	db 10	; New Instrument (10).
	db 30
	db 124	; No note, but effects.
	db 0	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 30
	db 124	; No note, but effects.
	db 0	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 30
	db 124	; No note, but effects.
	db 0	; Index to an effect block.
	db 61, 127	; Waits for 128 lines.


Subsong0_Track7:
	db 210
	db 12	; New Instrument (12).
	db 8	; Index to an effect block.
	db 124	; No note, but effects.
	db 0	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 18
	db 124	; No note, but effects.
	db 0	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 18
	db 124	; No note, but effects.
	db 0	; Index to an effect block.
	db 128
	db 0	; New Instrument (0).
	db 61, 5	; Waits for 6 lines.

	db 210
	db 12	; New Instrument (12).
	db 19	; Index to an effect block.
	db 82
	db 2	; Index to an effect block.
	db 124	; No note, but effects.
	db 0	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 18
	db 124	; No note, but effects.
	db 0	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 18
	db 124	; No note, but effects.
	db 0	; Index to an effect block.
	db 61, 127	; Waits for 128 lines.


Subsong0_Track8:
	db 211
	db 2	; New Instrument (2).
	db 8	; Index to an effect block.
	db 62 + 0 * 64	; Optimized wait for 2 lines.

	db 19
	db 62 + 0 * 64	; Optimized wait for 2 lines.

	db 19
	db 60	; Waits for 1 line.

	db 163
	db 9	; New Instrument (9).
	db 99
	db 4	; Index to an effect block.
	db 99
	db 3	; Index to an effect block.
	db 99
	db 1	; Index to an effect block.
	db 99
	db 12	; Index to an effect block.
	db 99
	db 18	; Index to an effect block.
	db 99
	db 22	; Index to an effect block.
	db 211
	db 2	; New Instrument (2).
	db 2	; Index to an effect block.
	db 19
	db 62 + 0 * 64	; Optimized wait for 2 lines.

	db 19
	db 62 + 0 * 64	; Optimized wait for 2 lines.

	db 19
	db 61, 127	; Waits for 128 lines.


Subsong0_Track9:
	db 144
	db 10	; New Instrument (10).
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 5	; Index to an effect block.
	db 61, 127	; Waits for 128 lines.


Subsong0_Track10:
	db 159
	db 9	; New Instrument (9).
	db 62 + 1 * 64	; Optimized wait for 3 lines.

	db 147
	db 2	; New Instrument (2).
	db 60	; Waits for 1 line.

	db 159
	db 9	; New Instrument (9).
	db 147
	db 2	; New Instrument (2).
	db 61, 127	; Waits for 128 lines.


Subsong0_Track11:
	db 144
	db 12	; New Instrument (12).
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 5	; Index to an effect block.
	db 61, 127	; Waits for 128 lines.


Subsong0_Track12:
	db 142
	db 10	; New Instrument (10).
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 9	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 11
	db 61, 127	; Waits for 128 lines.


Subsong0_Track13:
	db 211
	db 2	; New Instrument (2).
	db 8	; Index to an effect block.
	db 62 + 1 * 64	; Optimized wait for 3 lines.

	db 19
	db 223
	db 4	; New Instrument (4).
	db 1	; Index to an effect block.
	db 223
	db 6	; New Instrument (6).
	db 4	; Index to an effect block.
	db 223
	db 3	; New Instrument (3).
	db 3	; Index to an effect block.
	db 61, 127	; Waits for 128 lines.


Subsong0_Track14:
	db 142
	db 12	; New Instrument (12).
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 9	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 11
	db 61, 127	; Waits for 128 lines.


Subsong0_Track15:
	db 162
	db 14	; New Instrument (14).
	db 62 + 3 * 64	; Optimized wait for 5 lines.

	db 31
	db 61, 8	; Waits for 9 lines.

	db 153
	db 8	; New Instrument (8).
	db 62 + 3 * 64	; Optimized wait for 5 lines.

	db 22
	db 61, 127	; Waits for 128 lines.


Subsong0_Track16:
	db 147
	db 2	; New Instrument (2).
	db 62 + 0 * 64	; Optimized wait for 2 lines.

	db 19
	db 60	; Waits for 1 line.

	db 19
	db 159
	db 9	; New Instrument (9).
	db 62 + 1 * 64	; Optimized wait for 3 lines.

	db 147
	db 2	; New Instrument (2).
	db 62 + 0 * 64	; Optimized wait for 2 lines.

	db 19
	db 62 + 0 * 64	; Optimized wait for 2 lines.

	db 19
	db 62 + 0 * 64	; Optimized wait for 2 lines.

	db 19
	db 60	; Waits for 1 line.

	db 19
	db 159
	db 9	; New Instrument (9).
	db 62 + 1 * 64	; Optimized wait for 3 lines.

	db 147
	db 2	; New Instrument (2).
	db 60	; Waits for 1 line.

	db 159
	db 9	; New Instrument (9).
	db 147
	db 2	; New Instrument (2).
	db 60	; Waits for 1 line.

	db 19
	db 61, 127	; Waits for 128 lines.


Subsong0_Track17:
	db 235
	db 13	; New Instrument (13).
	db 23	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 46
	db 60	; Waits for 1 line.

	db 50
	db 60	; Waits for 1 line.

	db 53
	db 60	; Waits for 1 line.

	db 52
	db 60	; Waits for 1 line.

	db 107
	db 1	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 43
	db 60	; Waits for 1 line.

	db 46
	db 60	; Waits for 1 line.

	db 49
	db 60	; Waits for 1 line.

	db 53
	db 60	; Waits for 1 line.

	db 116
	db 3	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 43
	db 60	; Waits for 1 line.

	db 43
	db 60	; Waits for 1 line.

	db 46
	db 60	; Waits for 1 line.

	db 49
	db 60	; Waits for 1 line.

	db 52
	db 61, 127	; Waits for 128 lines.


Subsong0_Track18:
	db 150
	db 11	; New Instrument (11).
	db 62 + 3 * 64	; Optimized wait for 5 lines.

	db 19
	db 61, 8	; Waits for 9 lines.

	db 13
	db 62 + 3 * 64	; Optimized wait for 5 lines.

	db 10
	db 61, 127	; Waits for 128 lines.


Subsong0_Track19:
	db 147
	db 2	; New Instrument (2).
	db 171
	db 16	; New Instrument (16).
	db 43
	db 147
	db 2	; New Instrument (2).
	db 171
	db 16	; New Instrument (16).
	db 147
	db 2	; New Instrument (2).
	db 159
	db 9	; New Instrument (9).
	db 171
	db 16	; New Instrument (16).
	db 43
	db 43
	db 147
	db 2	; New Instrument (2).
	db 171
	db 17	; New Instrument (17).
	db 43
	db 147
	db 2	; New Instrument (2).
	db 171
	db 17	; New Instrument (17).
	db 43
	db 147
	db 2	; New Instrument (2).
	db 171
	db 17	; New Instrument (17).
	db 171
	db 18	; New Instrument (18).
	db 147
	db 2	; New Instrument (2).
	db 171
	db 18	; New Instrument (18).
	db 147
	db 2	; New Instrument (2).
	db 159
	db 9	; New Instrument (9).
	db 171
	db 18	; New Instrument (18).
	db 171
	db 19	; New Instrument (19).
	db 43
	db 147
	db 2	; New Instrument (2).
	db 171
	db 19	; New Instrument (19).
	db 159
	db 9	; New Instrument (9).
	db 147
	db 2	; New Instrument (2).
	db 171
	db 19	; New Instrument (19).
	db 147
	db 2	; New Instrument (2).
	db 61, 127	; Waits for 128 lines.


Subsong0_Track20:
	db 235
	db 15	; New Instrument (15).
	db 24	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 11	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 21	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 17	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 10	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 6	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 6	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 11	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 16	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 17	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 10	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 6	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 6	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 11	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 16	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 124	; No note, but effects.
	db 10	; Index to an effect block.
	db 61, 127	; Waits for 128 lines.


Subsong0_Track21:
	db 235
	db 7	; New Instrument (7).
	db 14	; Index to an effect block.
	db 60	; Waits for 1 line.

	db 46
	db 60	; Waits for 1 line.

	db 50
	db 60	; Waits for 1 line.

	db 53
	db 60	; Waits for 1 line.

	db 52
	db 60	; Waits for 1 line.

	db 43
	db 60	; Waits for 1 line.

	db 43
	db 60	; Waits for 1 line.

	db 46
	db 60	; Waits for 1 line.

	db 49
	db 60	; Waits for 1 line.

	db 53
	db 60	; Waits for 1 line.

	db 52
	db 60	; Waits for 1 line.

	db 43
	db 60	; Waits for 1 line.

	db 43
	db 60	; Waits for 1 line.

	db 46
	db 60	; Waits for 1 line.

	db 49
	db 60	; Waits for 1 line.

	db 52
	db 61, 127	; Waits for 128 lines.


Subsong0_Track22:
	db 128
	db 0	; New Instrument (0).
	db 61, 127	; Waits for 128 lines.


Subsong0_Track23:
	db 247
	db 10	; New Instrument (10).
	db 20	; Index to an effect block.
	db 61, 127	; Waits for 128 lines.


Subsong0_Track24:
	db 214
	db 1	; New Instrument (1).
	db 8	; Index to an effect block.
	db 22
	db 23
	db 23
	db 25
	db 26
	db 19
	db 19
	db 19
	db 19
	db 19
	db 19
	db 23
	db 19
	db 26
	db 19
	db 25
	db 25
	db 25
	db 25
	db 27
	db 28
	db 22
	db 22
	db 22
	db 22
	db 22
	db 21
	db 20
	db 19
	db 18
	db 17
	db 61, 127	; Waits for 128 lines.


Subsong0_Track25:
	db 255
	db 72	; Escape note (72).
	db 12	; New Instrument (12).
	db 7	; Index to an effect block.
	db 61, 127	; Waits for 128 lines.


; The speed tracks
Subsong0_SpeedTrack0:
	db 255	; Wait for 128 lines.

; The event tracks
Subsong0_EventTrack0:
	db 255	; Wait for 128 lines.

Subsong0_DisarkByteRegionEnd0:

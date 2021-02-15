// compile: zcc +zx -vn -clib=sdcc_iy fx.c -create-app -o fx.bin

#include <stdio.h>
#include <sound.h>
#include <stdlib.h>

void *e_bit_fx[32] = {
BFX_UNNAMED_1             ,
BFX_LASER_REPEAT          ,
BFX_SQUEAK                ,
BFX_EATING                ,
BFX_SQUELCH               ,
BFX_KLAXON                ,
BFX_BEEP                  ,
BFX_WARP                  ,
BFX_DEEP_SPACE            ,
BFX_DUAL_NOTE_FUZZY       ,
BFX_DUAL_NOTE_FUZZY_2     ,
BFX_KLAXON_2              ,
BFX_TSPACE                ,
BFX_TSPACE_2              ,
BFX_SQUOINK               ,
BFX_EXPLOSION             ,
BFX_BLIRP                 ,
BFX_BLIRP_2               ,
BFX_STEAM_ENGINE          ,
BFX_BLURP                 ,
BFX_BUZZER_DESCEND        ,
BFX_BUZZER_ASCEND         ,
BFX_BUZZER_DESCEND_2      ,
BFX_UNNAMED_2             ,
BFX_SQUEAK_2              ,
BFX_TAPE_REWIND           ,
BFX_UNNAMED_3             ,
BFX_UNNAMED_4             ,
BFX_SQUEAK_DESCEND        ,
BFX_UNNAMED_5             ,
BFX_UNNAMED_6             ,
BFX_UNNAMED_7             
};

void *e_bit_beepfx[58] = {
BEEPFX_SHOT_1             ,
BEEPFX_SHOT_2             ,
BEEPFX_JUMP_1             ,
BEEPFX_JUMP_2             ,
BEEPFX_PICK               ,
BEEPFX_DROP_1             ,
BEEPFX_DROP_2             ,
BEEPFX_GRAB_1             ,
BEEPFX_GRAB_2             ,
BEEPFX_FAT_BEEP_1         ,
BEEPFX_FAT_BEEP_2         ,
BEEPFX_FAT_BEEP_3         ,
BEEPFX_HARSH_BEEP_1       ,
BEEPFX_HARSH_BEEP_2       ,
BEEPFX_HARSH_BEEP_3       ,
BEEPFX_HIT_1              ,
BEEPFX_HIT_2              ,
BEEPFX_HIT_3              ,
BEEPFX_HIT_4              ,
BEEPFX_JET_BURST          ,
BEEPFX_BOOM_1             ,
BEEPFX_BOOM_2             ,
BEEPFX_BOOM_3             ,
BEEPFX_BOOM_4             ,
BEEPFX_BOOM_5             ,
BEEPFX_BOOM_6             ,
BEEPFX_BOOM_7             ,
BEEPFX_BOOM_8             ,
BEEPFX_ITEM_1             ,
BEEPFX_ITEM_2             ,
BEEPFX_ITEM_3             ,
BEEPFX_ITEM_4             ,
BEEPFX_ITEM_5             ,
BEEPFX_ITEM_6             ,
BEEPFX_SWITCH_1           ,
BEEPFX_SWITCH_2           ,
BEEPFX_POWER_OFF          ,
BEEPFX_SCORE              ,
BEEPFX_CLANG              ,
BEEPFX_WATER_TAP          ,
BEEPFX_SELECT_1           ,
BEEPFX_SELECT_2           ,
BEEPFX_SELECT_3           ,
BEEPFX_SELECT_4           ,
BEEPFX_SELECT_5           ,
BEEPFX_SELECT_6           ,
BEEPFX_SELECT_7           ,
BEEPFX_ALARM_1            ,
BEEPFX_ALARM_2            ,
BEEPFX_ALARM_3            ,
BEEPFX_EAT                ,
BEEPFX_GULP               ,
BEEPFX_ROBOBLIP           ,
BEEPFX_NOPE               ,
BEEPFX_UH_HUH             ,
BEEPFX_OLD_COMPUTER       ,
BEEPFX_YEAH               ,
BEEPFX_AWW                ,
};

void main(void) {
    int i;
    char buf[100];
    
    while (1) {
        puts("BIT_FX:");
        while (1) {
            gets(buf);
            if (buf[0] == 'n')
                break;
            i = atoi(buf);
            bit_fx(e_bit_fx[i]);
        }

        puts("BIT_BEEPFX:");
        while (1) {
            gets(buf);
            if (buf[0] == 'n')
                break;
            i = atoi(buf);
            bit_beepfx(e_bit_beepfx[i]);
        }
    }
}

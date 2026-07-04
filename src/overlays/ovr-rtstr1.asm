;=======================================================================================
; ovr-rtstr1.asm -- BASIC65C string runtime emitter overlay, part 1
;=======================================================================================

        .cpu "45gs02"
        .include "../../target/basic65c.lbl"

        * = OVR_WINDOW_ADDR

        jmp rtstr1_overlay_entry

rtstr1_overlay_entry:
        lda #<out_runtime_string_1
        ldy #>out_runtime_string_1
        jsr out_zstr
        rts

out_runtime_string_1:
        .text "; string heap runtime"
        .byte 13
        .text "; bank-1 string heap grows downward from $1f800, last usable byte $1f7ff"
        .byte 13
        .text "strinit:"
        .byte 13
        .text "        lda #<$f800"
        .byte 13
        .text "        sta strheaplo"
        .byte 13
        .text "        lda #>$f800"
        .byte 13
        .text "        sta strheaphi"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "stralloc:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta strgctried"
        .byte 13
        .text "sa1:"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        lda strheaplo"
        .byte 13
        .text "        sbc strlen"
        .byte 13
        .text "        sta strdstlo"
        .byte 13
        .text "        lda strheaphi"
        .byte 13
        .text "        sbc #0"
        .byte 13
        .text "        sta strdsthi"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        lda strdstlo"
        .byte 13
        .text "        sbc #1"
        .byte 13
        .text "        sta strdstlo"
        .byte 13
        .text "        lda strdsthi"
        .byte 13
        .text "        sbc #0"
        .byte 13
        .text "        sta strdsthi"
        .byte 13
        .text "        lda strdsthi"
        .byte 13
        .text "        cmp #>varheapend"
        .byte 13
        .text "        bcs sarh"
        .byte 13
        .text "        jmp sagc"
        .byte 13
        .text "sarh:"
        .byte 13
        .text "        bne saok"
        .byte 13
        .text "        lda strdstlo"
        .byte 13
        .text "        cmp #<varheapend"
        .byte 13
        .text "        bcs saok"
        .byte 13
        .text "        jmp sagc"
        .byte 13
        .text "saok:"
        .byte 13
        .text "        lda strdstlo"
        .byte 13
        .text "        sta strheaplo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        sta varptr"
        .byte 13
        .text "        lda strdsthi"
        .byte 13
        .text "        sta strheaphi"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        sta varptr+1"
        .byte 13
        .text "        lda #$01"
        .byte 13
        .text "        sta varptr+2"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta varptr+3"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        rts"
        .byte 13
        .text "sagc:"
        .byte 13
        .text "        lda strmarksp"
        .byte 13
        .text "        bne saoom"
        .byte 13
        .text "        lda strgctried"
        .byte 13
        .text "        bne saoom"
        .byte 13
        .text "        inc strgctried"
        .byte 13
        .text "        jsr strgc"
        .byte 13
        .text "        jmp sa1"
        .byte 13
        .text "saoom:"
        .byte 13
        .text "        jmp outofstring"
        .byte 13
        .text ""
        .byte 13
        .text "strfromlit:"
        .byte 13
        .text "        ldy #0"
        .byte 13
        .text "strfromlitlen:"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        beq strfromlitalloc"
        .byte 13
        .text "        iny"
        .byte 13
        .text "        bne strfromlitlen"
        .byte 13
        .text "        jmp outofstring"
        .byte 13
        .text "strfromlitalloc:"
        .byte 13
        .text "        sty strlen"
        .byte 13
        .text "        jsr stralloc"
        .byte 13
        .text "        bcs strfromlitdone"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda strlen"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta stridx"
        .byte 13
        .text "strfromlitcopy:"
        .byte 13
        .text "        lda stridx"
        .byte 13
        .text "        cmp strlen"
        .byte 13
        .text "        beq strfromlitdone"
        .byte 13
        .text "        tay"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        pha"
        .byte 13
        .text "        inc stridx"
        .byte 13
        .text "        ldz stridx"
        .byte 13
        .text "        pla"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        jmp strfromlitcopy"
        .byte 13
        .text "strfromlitdone:"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "strcopyexpr:"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        ora exprhi"
        .byte 13
        .text "        bne strcopygo"
        .byte 13
        .text "        rts"
        .byte 13
        .text "strcopygo:"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        sta strsrc1lo"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        sta strsrc1hi"
        .byte 13
        .text "        jsr setstrptrsrc1"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        sta strlen"
        .byte 13
        .text "        jsr stralloc"
        .byte 13
        .text "        bcs strcopydone"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda strlen"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta stridx"
        .byte 13
        .text "strcopyloop:"
        .byte 13
        .text "        lda stridx"
        .byte 13
        .text "        cmp strlen"
        .byte 13
        .text "        beq strcopyfinish"
        .byte 13
        .text "        inc stridx"
        .byte 13
        .text "        jsr setstrptrsrc1"
        .byte 13
        .text "        ldz stridx"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        pha"
        .byte 13
        .text "        jsr setstrptrdst"
        .byte 13
        .text "        ldz stridx"
        .byte 13
        .text "        pla"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        jmp strcopyloop"
        .byte 13
        .text "strcopyfinish:"
        .byte 13
        .text "        lda strdstlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda strdsthi"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "strcopydone:"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "concatstr:"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        sta strsrc1lo"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        sta strsrc1hi"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        sta strsrc2lo"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        sta strsrc2hi"
        .byte 13
        .text "        jsr strlen1load"
        .byte 13
        .text "        jsr strlen2load"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        lda strlen1"
        .byte 13
        .text "        adc strlen2"
        .byte 13
        .text "        sta strlen"
        .byte 13
        .text "        bcc concatlenok"
        .byte 13
        .text "        jmp outofstring"
        .byte 13
        .text "concatlenok:"
        .byte 13
        .text "        jsr stralloc"
        .byte 13
        .text "        bcs concatdone"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda strlen"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta stridx"
        .byte 13
        .text "        lda #1"
        .byte 13
        .text "        sta strdstidx"
        .byte 13
        .text "concatcopy1:"
        .byte 13
        .text "        lda stridx"
        .byte 13
        .text "        cmp strlen1"
        .byte 13
        .text "        beq concatcopy2start"
        .byte 13
        .text "        inc stridx"
        .byte 13
        .text "        jsr setstrptrsrc1"
        .byte 13
        .text "        ldz stridx"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        pha"
        .byte 13
        .text "        jsr setstrptrdst"
        .byte 13
        .text "        ldz strdstidx"
        .byte 13
        .text "        pla"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        inc strdstidx"
        .byte 13
        .text "        jmp concatcopy1"
        .byte 13
        .text "concatcopy2start:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta stridx"
        .byte 13
        .text "concatcopy2:"
        .byte 13
        .text "        lda stridx"
        .byte 13
        .text "        cmp strlen2"
        .byte 13
        .text "        beq concatfinish"
        .byte 13
        .text "        inc stridx"
        .byte 13
        .text "        jsr setstrptrsrc2"
        .byte 13
        .text "        ldz stridx"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        pha"
        .byte 13
        .text "        jsr setstrptrdst"
        .byte 13
        .text "        ldz strdstidx"
        .byte 13
        .text "        pla"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        inc strdstidx"
        .byte 13
        .text "        jmp concatcopy2"
        .byte 13
        .text "concatfinish:"
        .byte 13
        .text "        lda strdstlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda strdsthi"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "concatdone:"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "streq:"
        .byte 13
        .text "        jsr strcmp"
        .byte 13
        .text "        bne streqfalse"
        .byte 13
        .text "        jmp strcmptrue"
        .byte 13
        .text "streqfalse:"
        .byte 13
        .text "        jmp strcmpfalse"
        .byte 13
        .text "strne:"
        .byte 13
        .text "        jsr strcmp"
        .byte 13
        .text "        bne strnetrue"
        .byte 13
        .text "        jmp strcmpfalse"
        .byte 13
        .text "strnetrue:"
        .byte 13
        .text "        jmp strcmptrue"
        .byte 13
        .text "strlt:"
        .byte 13
        .text "        jsr strcmp"
        .byte 13
        .text "        bpl strltfalse"
        .byte 13
        .text "        jmp strcmptrue"
        .byte 13
        .text "strltfalse:"
        .byte 13
        .text "        jmp strcmpfalse"
        .byte 13
        .text "strle:"
        .byte 13
        .text "        jsr strcmp"
        .byte 13
        .text "        beq strletrue"
        .byte 13
        .text "        bpl strlefalse"
        .byte 13
        .text "strletrue:"
        .byte 13
        .text "        jmp strcmptrue"
        .byte 13
        .text "strlefalse:"
        .byte 13
        .text "        jmp strcmpfalse"
        .byte 13
        .text "strgt:"
        .byte 13
        .text "        jsr strcmp"
        .byte 13
        .text "        beq strgtfalse"
        .byte 13
        .text "        bmi strgtfalse"
        .byte 13
        .text "        jmp strcmptrue"
        .byte 13
        .text "strgtfalse:"
        .byte 13
        .text "        jmp strcmpfalse"
        .byte 13
        .text "strge:"
        .byte 13
        .text "        jsr strcmp"
        .byte 13
        .text "        beq strgetrue"
        .byte 13
        .text "        bmi strgefalse"
        .byte 13
        .text "strgetrue:"
        .byte 13
        .text "        jmp strcmptrue"
        .byte 13
        .text "strgefalse:"
        .byte 13
        .text "        jmp strcmpfalse"
        .byte 13
        .text "strcmptrue:"
        .byte 13
        .text "        lda #1"
        .byte 13
        .text "        rts"
        .byte 13
        .text "strcmpfalse:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "strrefeq:"
        .byte 13
        .text "        jsr srcmp"
        .byte 13
        .text "        bne sreqf"
        .byte 13
        .text "        jmp strcmptrue"
        .byte 13
        .text "sreqf:"
        .byte 13
        .text "        jmp strcmpfalse"
        .byte 13
        .text "strrefne:"
        .byte 13
        .text "        jsr srcmp"
        .byte 13
        .text "        bne srnet"
        .byte 13
        .text "        jmp strcmpfalse"
        .byte 13
        .text "srnet:"
        .byte 13
        .text "        jmp strcmptrue"
        .byte 13
        .text "strreflt:"
        .byte 13
        .text "        jsr srcmp"
        .byte 13
        .text "        bpl srltf"
        .byte 13
        .text "        jmp strcmptrue"
        .byte 13
        .text "srltf:"
        .byte 13
        .text "        jmp strcmpfalse"
        .byte 13
        .text "strrefle:"
        .byte 13
        .text "        jsr srcmp"
        .byte 13
        .text "        beq srlet"
        .byte 13
        .text "        bpl srlef"
        .byte 13
        .text "srlet:"
        .byte 13
        .text "        jmp strcmptrue"
        .byte 13
        .text "srlef:"
        .byte 13
        .text "        jmp strcmpfalse"
        .byte 13
        .text "strrefgt:"
        .byte 13
        .text "        jsr srcmp"
        .byte 13
        .text "        beq srgtf"
        .byte 13
        .text "        bmi srgtf"
        .byte 13
        .text "        jmp strcmptrue"
        .byte 13
        .text "srgtf:"
        .byte 13
        .text "        jmp strcmpfalse"
        .byte 13
        .text "strrefge:"
        .byte 13
        .text "        jsr srcmp"
        .byte 13
        .text "        beq srget"
        .byte 13
        .text "        bmi srgef"
        .byte 13
        .text "srget:"
        .byte 13
        .text "        jmp strcmptrue"
        .byte 13
        .text "srgef:"
        .byte 13
        .text "        jmp strcmpfalse"
        .byte 13
        .text "srcmp:"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        sta strsrc1lo"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        sta strsrc1hi"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        sta strsrc2lo"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        sta strsrc2hi"
        .byte 13
        .text "        jsr srlen1"
        .byte 13
        .text "        jsr srlen2"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta stridx"
        .byte 13
        .text "srclp:"
        .byte 13
        .text "        lda stridx"
        .byte 13
        .text "        cmp strlen1"
        .byte 13
        .text "        beq srclhe"
        .byte 13
        .text "        cmp strlen2"
        .byte 13
        .text "        beq srcgt"
        .byte 13
        .text "        inc stridx"
        .byte 13
        .text "        jsr srch1"
        .byte 13
        .text "        sta strcmpchar"
        .byte 13
        .text "        jsr srch2"
        .byte 13
        .text "        sta strdstidx"
        .byte 13
        .text "        lda strcmpchar"
        .byte 13
        .text "        cmp strdstidx"
        .byte 13
        .text "        bcc srclt"
        .byte 13
        .text "        bne srcgt"
        .byte 13
        .text "        jmp srclp"
        .byte 13
        .text "srclhe:"
        .byte 13
        .text "        lda stridx"
        .byte 13
        .text "        cmp strlen2"
        .byte 13
        .text "        beq srceq"
        .byte 13
        .text "srclt:"
        .byte 13
        .text "        lda #$ff"
        .byte 13
        .text "        rts"
        .byte 13
        .text "srcgt:"
        .byte 13
        .text "        lda #1"
        .byte 13
        .text "        rts"
        .byte 13
        .text "srceq:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        rts"
        .byte 13
        .text "srlen1:"
        .byte 13
        .text "        lda strsrc1lo"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda strsrc1hi"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13
        .text "        lda strarg1lo"
        .byte 13
        .text "        jsr srlen"
        .byte 13
        .text "        sta strlen1"
        .byte 13
        .text "        rts"
        .byte 13
        .text "srlen2:"
        .byte 13
        .text "        lda strsrc2lo"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda strsrc2hi"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13
        .text "        lda strarg1hi"
        .byte 13
        .text "        jsr srlen"
        .byte 13
        .text "        sta strlen2"
        .byte 13
        .text "        rts"
        .byte 13
        .text "srlen:"
        .byte 13
        .text "        sta strsrcoff"
        .byte 13
        .text "        lda rtptr"
        .byte 13
        .text "        ora rtptr+1"
        .byte 13
        .text "        bne srlgo"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        rts"
        .byte 13
        .text "srlgo:"
        .byte 13
        .text "        lda strsrcoff"
        .byte 13
        .text "        bne srllit"
        .byte 13
        .text "        lda rtptr"
        .byte 13
        .text "        sta varptr"
        .byte 13
        .text "        lda rtptr+1"
        .byte 13
        .text "        sta varptr+1"
        .byte 13
        .text "        jsr setstrptrbank"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        rts"
        .byte 13
        .text "srllit:"
        .byte 13
        .text "        ldy #0"
        .byte 13
        .text "srllp:"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        beq srldn"
        .byte 13
        .text "        iny"
        .byte 13
        .text "        bne srllp"
        .byte 13
        .text "        jmp outofstring"
        .byte 13
        .text "srldn:"
        .byte 13
        .text "        tya"
        .byte 13
        .text "        rts"
        .byte 13
        .text "srch1:"
        .byte 13
        .text "        lda strsrc1lo"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda strsrc1hi"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13
        .text "        lda strarg1lo"
        .byte 13
        .text "        jmp srch"
        .byte 13
        .text "srch2:"
        .byte 13
        .text "        lda strsrc2lo"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda strsrc2hi"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13
        .text "        lda strarg1hi"
        .byte 13
        .text "srch:"
        .byte 13
        .text "        bne srchlit"
        .byte 13
        .text "        lda rtptr"
        .byte 13
        .text "        sta varptr"
        .byte 13
        .text "        lda rtptr+1"
        .byte 13
        .text "        sta varptr+1"
        .byte 13
        .text "        jsr setstrptrbank"
        .byte 13
        .text "        ldz stridx"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        rts"
        .byte 13
        .text "srchlit:"
        .byte 13
        .text "        ldy stridx"
        .byte 13
        .text "        dey"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "strcmp:"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        sta strsrc1lo"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        sta strsrc1hi"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        sta strsrc2lo"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        sta strsrc2hi"
        .byte 13
        .text "        jsr strlen1load"
        .byte 13
        .text "        jsr strlen2load"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta stridx"
        .byte 13
        .text "strcmploop:"
        .byte 13
        .text "        lda stridx"
        .byte 13
        .text "        cmp strlen1"
        .byte 13
        .text "        beq strcmplhsend"
        .byte 13
        .text "        cmp strlen2"
        .byte 13
        .text "        beq strcmpgreater"
        .byte 13
        .text "        inc stridx"
        .byte 13
        .text "        jsr setstrptrsrc1"
        .byte 13
        .text "        ldz stridx"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        sta strcmpchar"
        .byte 13
        .text "        jsr setstrptrsrc2"
        .byte 13
        .text "        ldz stridx"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        sta strdstidx"
        .byte 13
        .text "        lda strcmpchar"
        .byte 13
        .text "        cmp strdstidx"
        .byte 13
        .text "        bcc strcmpless"
        .byte 13
        .text "        bne strcmpgreater"
        .byte 13
        .text "        jmp strcmploop"
        .byte 13
        .text "strcmplhsend:"
        .byte 13
        .text "        lda stridx"
        .byte 13
        .text "        cmp strlen2"
        .byte 13
        .text "        beq strcmpequal"
        .byte 13
        .text "strcmpless:"
        .byte 13
        .text "        lda #$ff"
        .byte 13
        .text "        rts"
        .byte 13
        .text "strcmpgreater:"
        .byte 13
        .text "        lda #1"
        .byte 13
        .text "        rts"
        .byte 13
        .text "strcmpequal:"
        .byte 13
        .byte 0

        .cerror * > OVR_WINDOW_ADDR + OVR_WINDOW_SIZE, "ovr-rtstr1 exceeds overlay window"
        .fill OVR_WINDOW_ADDR + OVR_WINDOW_SIZE - *, 0

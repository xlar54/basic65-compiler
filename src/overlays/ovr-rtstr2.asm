;=======================================================================================
; ovr-rtstr2.asm -- BASIC65C string runtime emitter overlay, part 2
;=======================================================================================

        .cpu "45gs02"
        .include "../../target/basic65c.lbl"

        * = OVR_WINDOW_ADDR

        jmp rtstr2_overlay_entry

rtstr2_overlay_entry:
        lda #<out_runtime_string_2
        ldy #>out_runtime_string_2
        jsr out_zstr
        rts

out_runtime_string_2:
        .text "        lda #0"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "strlenexpr:"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        ora exprhi"
        .byte 13
        .text "        bne strlenexprgo"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        rts"
        .byte 13
        .text "strlenexprgo:"
        .byte 13
        .text "        jsr setstrptrexpr"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "printheapstr:"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        ora exprhi"
        .byte 13
        .text "        beq printheapdone"
        .byte 13
        .text "        jsr setstrptrexpr"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        sta strlen"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta stridx"
        .byte 13
        .text "printheaploop:"
        .byte 13
        .text "        lda stridx"
        .byte 13
        .text "        cmp strlen"
        .byte 13
        .text "        beq printheapdone"
        .byte 13
        .text "        inc stridx"
        .byte 13
        .text "        ldz stridx"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        jmp printheaploop"
        .byte 13
        .text "printheapdone:"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "strlen1load:"
        .byte 13
        .text "        lda strsrc1lo"
        .byte 13
        .text "        ora strsrc1hi"
        .byte 13
        .text "        bne strlen1go"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta strlen1"
        .byte 13
        .text "        rts"
        .byte 13
        .text "strlen1go:"
        .byte 13
        .text "        jsr setstrptrsrc1"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        sta strlen1"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "strlen2load:"
        .byte 13
        .text "        lda strsrc2lo"
        .byte 13
        .text "        ora strsrc2hi"
        .byte 13
        .text "        bne strlen2go"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta strlen2"
        .byte 13
        .text "        rts"
        .byte 13
        .text "strlen2go:"
        .byte 13
        .text "        jsr setstrptrsrc2"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        sta strlen2"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text ""
        .byte 13
        .text "strright:"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        sta strsrc1lo"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        sta strsrc1hi"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        ora lhshi"
        .byte 13
        .text "        bne srn"
        .byte 13
        .text "        jmp strsubempty"
        .byte 13
        .text "srn:"
        .byte 13
        .text "        jsr strlen1load"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        bpl srcp"
        .byte 13
        .text "        jmp strsubempty"
        .byte 13
        .text "srcp:"
        .byte 13
        .text "        bne strrightall"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        bne srcn"
        .byte 13
        .text "        jmp strsubempty"
        .byte 13
        .text "srcn:"
        .byte 13
        .text "        cmp strlen1"
        .byte 13
        .text "        bcs strrightall"
        .byte 13
        .text "        sta strlen"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        lda strlen1"
        .byte 13
        .text "        sbc strlen"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        adc #1"
        .byte 13
        .text "        sta strarg1lo"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta strarg1hi"
        .byte 13
        .text "        lda strlen"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        jmp strsub"
        .byte 13
        .text "strrightall:"
        .byte 13
        .text "        lda #1"
        .byte 13
        .text "        sta strarg1lo"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta strarg1hi"
        .byte 13
        .text "        lda strlen1"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        jmp strsub"
        .byte 13
        .text ""
        .byte 13
        .text "strsub:"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        sta strsrc1lo"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        sta strsrc1hi"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        ora lhshi"
        .byte 13
        .text "        bne ssn"
        .byte 13
        .text "        jmp strsubempty"
        .byte 13
        .text "ssn:"
        .byte 13
        .text "        jsr strlen1load"
        .byte 13
        .text "        lda strarg1hi"
        .byte 13
        .text "        bmi strsubstartone"
        .byte 13
        .text "        bne strsubempty"
        .byte 13
        .text "        lda strarg1lo"
        .byte 13
        .text "        beq strsubstartone"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        sbc #1"
        .byte 13
        .text "        sta strsrcoff"
        .byte 13
        .text "        jmp strsubhavestart"
        .byte 13
        .text "strsubstartone:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta strsrcoff"
        .byte 13
        .text "strsubhavestart:"
        .byte 13
        .text "        lda strsrcoff"
        .byte 13
        .text "        cmp strlen1"
        .byte 13
        .text "        bcs strsubempty"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        lda strlen1"
        .byte 13
        .text "        sbc strsrcoff"
        .byte 13
        .text "        sta strlen2"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        bmi strsubempty"
        .byte 13
        .text "        bne strsubuseavail"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        beq strsubempty"
        .byte 13
        .text "        cmp strlen2"
        .byte 13
        .text "        bcs strsubuseavail"
        .byte 13
        .text "        sta strlen"
        .byte 13
        .text "        jmp strsuballoc"
        .byte 13
        .text "strsubuseavail:"
        .byte 13
        .text "        lda strlen2"
        .byte 13
        .text "        sta strlen"
        .byte 13
        .text "strsuballoc:"
        .byte 13
        .text "        jsr stralloc"
        .byte 13
        .text "        bcs strsubdone"
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
        .text "strsubcopy:"
        .byte 13
        .text "        lda stridx"
        .byte 13
        .text "        cmp strlen"
        .byte 13
        .text "        beq strsubfinish"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        lda strsrcoff"
        .byte 13
        .text "        adc stridx"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        adc #1"
        .byte 13
        .text "        sta strdstidx"
        .byte 13
        .text "        jsr setstrptrsrc1"
        .byte 13
        .text "        ldz strdstidx"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        pha"
        .byte 13
        .text "        jsr setstrptrdst"
        .byte 13
        .text "        inc stridx"
        .byte 13
        .text "        ldz stridx"
        .byte 13
        .text "        pla"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        jmp strsubcopy"
        .byte 13
        .text "strsubfinish:"
        .byte 13
        .text "        lda strdstlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda strdsthi"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "strsubdone:"
        .byte 13
        .text "        rts"
        .byte 13
        .text "strsubempty:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta strlen"
        .byte 13
        .text "        jsr stralloc"
        .byte 13
        .text "        bcs strsubdone"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        lda strdstlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda strdsthi"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "strfromint:"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        sta lhslo"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        sta lhshi"
        .byte 13
        .text "        lda #6"
        .byte 13
        .text "        sta strlen"
        .byte 13
        .text "        jsr stralloc"
        .byte 13
        .text "        bcs strfromintdone"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta stridx"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        bmi strfromintneg"
        .byte 13
        .text "        lda #' '"
        .byte 13
        .text "        jsr strputchar"
        .byte 13
        .text "        jmp strfromintdigits"
        .byte 13
        .text "strfromintneg:"
        .byte 13
        .text "        lda #'-'"
        .byte 13
        .text "        jsr strputchar"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sbc lhslo"
        .byte 13
        .text "        sta lhslo"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sbc lhshi"
        .byte 13
        .text "        sta lhshi"
        .byte 13
        .text "strfromintdigits:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta printstarted"
        .byte 13
        .text "        lda #<$2710"
        .byte 13
        .text "        ldy #>$2710"
        .byte 13
        .text "        jsr strdigit"
        .byte 13
        .text "        lda #<$03e8"
        .byte 13
        .text "        ldy #>$03e8"
        .byte 13
        .text "        jsr strdigit"
        .byte 13
        .text "        lda #<$0064"
        .byte 13
        .text "        ldy #>$0064"
        .byte 13
        .text "        jsr strdigit"
        .byte 13
        .text "        lda #<$000a"
        .byte 13
        .text "        ldy #>$000a"
        .byte 13
        .text "        jsr strdigit"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        adc #'0'"
        .byte 13
        .text "        jsr strputchar"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda stridx"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        lda strdstlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda strdsthi"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "strfromintdone:"
        .byte 13
        .text "        rts"
        .byte 13
        .text "strputchar:"
        .byte 13
        .text "        inc stridx"
        .byte 13
        .text "        ldz stridx"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        rts"
        .byte 13
        .text "strdigit:"
        .byte 13
        .text "        sta divlo"
        .byte 13
        .text "        sty divhi"
        .byte 13
        .text "        lda #'0'"
        .byte 13
        .text "        sta digit"
        .byte 13
        .text "strdigitloop:"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        cmp divhi"
        .byte 13
        .text "        bcc strdigitdone"
        .byte 13
        .text "        bne strdigitsub"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        cmp divlo"
        .byte 13
        .text "        bcc strdigitdone"
        .byte 13
        .text "strdigitsub:"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        sbc divlo"
        .byte 13
        .text "        sta lhslo"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        sbc divhi"
        .byte 13
        .text "        sta lhshi"
        .byte 13
        .text "        inc digit"
        .byte 13
        .text "        jmp strdigitloop"
        .byte 13
        .text "strdigitdone:"
        .byte 13
        .text "        lda digit"
        .byte 13
        .text "        cmp #'0'"
        .byte 13
        .text "        bne strdigitemit"
        .byte 13
        .text "        lda printstarted"
        .byte 13
        .text "        beq strdigitreturn"
        .byte 13
        .text "        lda digit"
        .byte 13
        .text "strdigitemit:"
        .byte 13
        .text "        sta digit"
        .byte 13
        .text "        lda #1"
        .byte 13
        .text "        sta printstarted"
        .byte 13
        .text "        lda digit"
        .byte 13
        .text "        jsr strputchar"
        .byte 13
        .text "strdigitreturn:"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "valstr:"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        ora exprhi"
        .byte 13
        .text "        bne valstrgo"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        rts"
        .byte 13
        .text "valstrgo:"
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
        .text "        lda #0"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        sta stridx"
        .byte 13
        .text "        sta strdstidx"
        .byte 13
        .text "valskip:"
        .byte 13
        .text "        jsr valreadchar"
        .byte 13
        .text "        bcs valdone"
        .byte 13
        .text "        cmp #$20"
        .byte 13
        .text "        beq valskip"
        .byte 13
        .text "        cmp #'-'"
        .byte 13
        .text "        beq valminus"
        .byte 13
        .text "        cmp #'+'"
        .byte 13
        .text "        beq valdigitloop"
        .byte 13
        .text "        jmp valdigitgot"
        .byte 13
        .text "valminus:"
        .byte 13
        .text "        lda #1"
        .byte 13
        .text "        sta strdstidx"
        .byte 13
        .text "valdigitloop:"
        .byte 13
        .text "        jsr valreadchar"
        .byte 13
        .text "        bcs valapplysign"
        .byte 13
        .text "valdigitgot:"
        .byte 13
        .text "        cmp #'0'"
        .byte 13
        .text "        bcc valapplysign"
        .byte 13
        .text "        cmp #$3a"
        .byte 13
        .text "        bcs valapplysign"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        sbc #'0'"
        .byte 13
        .text "        sta digit"
        .byte 13
        .text "        jsr inputmul10add"
        .byte 13
        .text "        jmp valdigitloop"
        .byte 13
        .text "valreadchar:"
        .byte 13
        .text "        lda stridx"
        .byte 13
        .text "        cmp strlen"
        .byte 13
        .text "        bcc valreadmore"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        rts"
        .byte 13
        .text "valreadmore:"
        .byte 13
        .text "        inc stridx"
        .byte 13
        .text "        jsr setstrptrsrc1"
        .byte 13
        .text "        ldz stridx"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        rts"
        .byte 13
        .text "valapplysign:"
        .byte 13
        .text "        lda strdstidx"
        .byte 13
        .text "        beq valdone"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        ora exprhi"
        .byte 13
        .text "        beq valdone"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sbc exprlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sbc exprhi"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "valdone:"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "setstrptrexpr:"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        sta varptr"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        sta varptr+1"
        .byte 13
        .text "        jmp setstrptrbank"
        .byte 13
        .text "setstrptrsrc1:"
        .byte 13
        .text "        lda strsrc1lo"
        .byte 13
        .text "        sta varptr"
        .byte 13
        .text "        lda strsrc1hi"
        .byte 13
        .text "        sta varptr+1"
        .byte 13
        .text "        jmp setstrptrbank"
        .byte 13
        .text "setstrptrsrc2:"
        .byte 13
        .text "        lda strsrc2lo"
        .byte 13
        .text "        sta varptr"
        .byte 13
        .text "        lda strsrc2hi"
        .byte 13
        .text "        sta varptr+1"
        .byte 13
        .text "        jmp setstrptrbank"
        .byte 13
        .text "setstrptrdst:"
        .byte 13
        .text "        lda strdstlo"
        .byte 13
        .text "        sta varptr"
        .byte 13
        .text "        lda strdsthi"
        .byte 13
        .text "        sta varptr+1"
        .byte 13
        .text "setstrptrbank:"
        .byte 13
        .text "        lda #$01"
        .byte 13
        .text "        sta varptr+2"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta varptr+3"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "outofstring:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        lda #$4f"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$55"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$54"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$20"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$4f"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$46"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$20"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$53"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$54"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$52"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$49"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$4e"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$47"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$0d"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 0

        .cerror * > OVR_WINDOW_ADDR + OVR_WINDOW_SIZE, "ovr-rtstr2 exceeds overlay window"
        .fill OVR_WINDOW_ADDR + OVR_WINDOW_SIZE - *, 0

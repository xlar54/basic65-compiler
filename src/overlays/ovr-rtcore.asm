;=======================================================================================
; ovr-rtcore.asm -- BASIC65C core runtime emitter overlay
;=======================================================================================

        .cpu "45gs02"
        .include "../../target/basic65c.lbl"

        * = OVR_WINDOW_ADDR

        jmp rtcore_overlay_entry

rtcore_overlay_entry:
        lda #<out_runtime_core
        ldy #>out_runtime_core
        jsr out_zstr
        lda runtime_need_math
        beq _rtcore_skip_math
        lda #<out_runtime_math
        ldy #>out_runtime_math
        jsr out_zstr
_rtcore_skip_math:
        lda runtime_need_cmp
        beq _rtcore_skip_cmp
        lda #<out_runtime_cmp
        ldy #>out_runtime_cmp
        jsr out_zstr
_rtcore_skip_cmp:
        lda runtime_need_strtemp
        beq _rtcore_skip_strtemp
        lda #<out_runtime_strtemp
        ldy #>out_runtime_strtemp
        jsr out_zstr
_rtcore_skip_strtemp:
        lda runtime_need_data
        beq _rtcore_skip_data
        lda #<out_runtime_data
        ldy #>out_runtime_data
        jsr out_zstr
_rtcore_skip_data:
        lda runtime_need_array
        beq _rtcore_skip_array
        lda #<out_runtime_array
        ldy #>out_runtime_array
        jsr out_zstr
_rtcore_skip_array:
        lda runtime_need_get
        beq _rtcore_skip_get
        lda #<out_runtime_get
        ldy #>out_runtime_get
        jsr out_zstr
_rtcore_skip_get:
        lda #<out_runtime_storage
        ldy #>out_runtime_storage
        jsr out_zstr
        rts

out_runtime_core:
        .text "; core runtime"
        .byte 13
        .byte 0

out_runtime_math:
        .text "; integer math runtime"
        .byte 13
        .text "mul16:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta resultlo"
        .byte 13
        .text "        sta resulthi"
        .byte 13
        .text "        ldx #16"
        .byte 13
        .text "mul16loop:"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        and #1"
        .byte 13
        .text "        beq mul16skip"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        lda resultlo"
        .byte 13
        .text "        adc lhslo"
        .byte 13
        .text "        sta resultlo"
        .byte 13
        .text "        lda resulthi"
        .byte 13
        .text "        adc lhshi"
        .byte 13
        .text "        sta resulthi"
        .byte 13
        .text "mul16skip:"
        .byte 13
        .text "        asl lhslo"
        .byte 13
        .text "        rol lhshi"
        .byte 13
        .text "        lsr exprhi"
        .byte 13
        .text "        ror exprlo"
        .byte 13
        .text "        dex"
        .byte 13
        .text "        bne mul16loop"
        .byte 13
        .text "        lda resultlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda resulthi"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "div16:"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        ora exprhi"
        .byte 13
        .text "        beq div16zero"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta quotlo"
        .byte 13
        .text "        sta quothi"
        .byte 13
        .text "        sta remlo"
        .byte 13
        .text "        sta remhi"
        .byte 13
        .text "        ldx #16"
        .byte 13
        .text "div16loop:"
        .byte 13
        .text "        asl lhslo"
        .byte 13
        .text "        rol lhshi"
        .byte 13
        .text "        rol remlo"
        .byte 13
        .text "        rol remhi"
        .byte 13
        .text "        asl quotlo"
        .byte 13
        .text "        rol quothi"
        .byte 13
        .text "        lda remhi"
        .byte 13
        .text "        cmp exprhi"
        .byte 13
        .text "        bcc div16next"
        .byte 13
        .text "        bne div16sub"
        .byte 13
        .text "        lda remlo"
        .byte 13
        .text "        cmp exprlo"
        .byte 13
        .text "        bcc div16next"
        .byte 13
        .text "div16sub:"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        lda remlo"
        .byte 13
        .text "        sbc exprlo"
        .byte 13
        .text "        sta remlo"
        .byte 13
        .text "        lda remhi"
        .byte 13
        .text "        sbc exprhi"
        .byte 13
        .text "        sta remhi"
        .byte 13
        .text "        inc quotlo"
        .byte 13
        .text "div16next:"
        .byte 13
        .text "        dex"
        .byte 13
        .text "        bne div16loop"
        .byte 13
        .text "        lda quotlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda quothi"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        rts"
        .byte 13
        .text "div16zero:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .byte 0

out_runtime_cmp:
        .text "; signed integer comparison runtime"
        .byte 13
        .text "cmpeq:"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        cmp exprhi"
        .byte 13
        .text "        bne cmpeqfalse"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        cmp exprlo"
        .byte 13
        .text "        beq cmpeqtrue"
        .byte 13
        .text "cmpeqfalse:"
        .byte 13
        .text "        jmp cmpfalse"
        .byte 13
        .text "cmpeqtrue:"
        .byte 13
        .text "        jmp cmptrue"
        .byte 13
        .text ""
        .byte 13
        .text "cmpne:"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        cmp exprhi"
        .byte 13
        .text "        bne cmpnetrue"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        cmp exprlo"
        .byte 13
        .text "        bne cmpnetrue"
        .byte 13
        .text "        jmp cmpfalse"
        .byte 13
        .text "cmpnetrue:"
        .byte 13
        .text "        jmp cmptrue"
        .byte 13
        .text ""
        .byte 13
        .text "cmplt:"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        eor exprhi"
        .byte 13
        .text "        bpl cmpltsame"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        bmi cmplttrue"
        .byte 13
        .text "        jmp cmpfalse"
        .byte 13
        .text "cmplttrue:"
        .byte 13
        .text "        jmp cmptrue"
        .byte 13
        .text "cmpltsame:"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        cmp exprhi"
        .byte 13
        .text "        bcc cmplttrue2"
        .byte 13
        .text "        bne cmpltfalse"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        cmp exprlo"
        .byte 13
        .text "        bcc cmplttrue2"
        .byte 13
        .text "cmpltfalse:"
        .byte 13
        .text "        jmp cmpfalse"
        .byte 13
        .text "cmplttrue2:"
        .byte 13
        .text "        jmp cmptrue"
        .byte 13
        .text ""
        .byte 13
        .text "cmple:"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        eor exprhi"
        .byte 13
        .text "        bpl cmplesame"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        bmi cmpletrue"
        .byte 13
        .text "        jmp cmpfalse"
        .byte 13
        .text "cmpletrue:"
        .byte 13
        .text "        jmp cmptrue"
        .byte 13
        .text "cmplesame:"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        cmp exprhi"
        .byte 13
        .text "        bcc cmpletrue2"
        .byte 13
        .text "        bne cmplefalse"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        cmp exprlo"
        .byte 13
        .text "        bcc cmpletrue2"
        .byte 13
        .text "        beq cmpletrue2"
        .byte 13
        .text "cmplefalse:"
        .byte 13
        .text "        jmp cmpfalse"
        .byte 13
        .text "cmpletrue2:"
        .byte 13
        .text "        jmp cmptrue"
        .byte 13
        .text ""
        .byte 13
        .text "cmpge:"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        eor exprhi"
        .byte 13
        .text "        bpl cmpgesame"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        bmi cmpgefalse"
        .byte 13
        .text "        jmp cmptrue"
        .byte 13
        .text "cmpgefalse:"
        .byte 13
        .text "        jmp cmpfalse"
        .byte 13
        .text "cmpgesame:"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        cmp exprhi"
        .byte 13
        .text "        bcc cmpgefalse2"
        .byte 13
        .text "        bne cmpgetrue"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        cmp exprlo"
        .byte 13
        .text "        bcs cmpgetrue"
        .byte 13
        .text "cmpgefalse2:"
        .byte 13
        .text "        jmp cmpfalse"
        .byte 13
        .text "cmpgetrue:"
        .byte 13
        .text "        jmp cmptrue"
        .byte 13
        .text ""
        .byte 13
        .text "cmpgt:"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        eor exprhi"
        .byte 13
        .text "        bpl cmpgtsame"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        bmi cmpgtfalse"
        .byte 13
        .text "        jmp cmptrue"
        .byte 13
        .text "cmpgtfalse:"
        .byte 13
        .text "        jmp cmpfalse"
        .byte 13
        .text "cmpgtsame:"
        .byte 13
        .text "        lda lhshi"
        .byte 13
        .text "        cmp exprhi"
        .byte 13
        .text "        bcc cmpgtfalse2"
        .byte 13
        .text "        bne cmpgttrue"
        .byte 13
        .text "        lda lhslo"
        .byte 13
        .text "        cmp exprlo"
        .byte 13
        .text "        bcc cmpgtfalse2"
        .byte 13
        .text "        beq cmpgtfalse2"
        .byte 13
        .text "cmpgttrue:"
        .byte 13
        .text "        jmp cmptrue"
        .byte 13
        .text "cmpgtfalse2:"
        .byte 13
        .text "        jmp cmpfalse"
        .byte 13
        .text ""
        .byte 13
        .text "cmptrue:"
        .byte 13
        .text "        lda #1"
        .byte 13
        .text "        rts"
        .byte 13
        .text "cmpfalse:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .byte 0

out_runtime_strtemp:
        .text "; string temporary heap marks"
        .byte 13
        .text "strmark:"
        .byte 13
        .text "        ldx strmarksp"
        .byte 13
        .text "        cpx #8"
        .byte 13
        .text "        bcc strmarkok"
        .byte 13
        .text "        jmp outofstring"
        .byte 13
        .text "strmarkok:"
        .byte 13
        .text "        lda strheaplo"
        .byte 13
        .text "        sta strmarklo,x"
        .byte 13
        .text "        lda strheaphi"
        .byte 13
        .text "        sta strmarkhi,x"
        .byte 13
        .text "        inc strmarksp"
        .byte 13
        .text "        rts"
        .byte 13
        .text "strrelease:"
        .byte 13
        .text "        lda strmarksp"
        .byte 13
        .text "        beq strreleasedone"
        .byte 13
        .text "        dec strmarksp"
        .byte 13
        .text "        ldx strmarksp"
        .byte 13
        .text "        lda strmarklo,x"
        .byte 13
        .text "        sta strheaplo"
        .byte 13
        .text "        lda strmarkhi,x"
        .byte 13
        .text "        sta strheaphi"
        .byte 13
        .text "strreleasedone:"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .byte 0

out_runtime_data:
        .text "; data/read runtime"
        .byte 13
        .text "datainit:"
        .byte 13
        .text "        lda #<datastart"
        .byte 13
        .text "        sta dataptrlo"
        .byte 13
        .text "        lda #>datastart"
        .byte 13
        .text "        sta dataptrhi"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "readint:"
        .byte 13
        .text "        jsr deof"
        .byte 13
        .text "        bcc riok"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        jmp ood"
        .byte 13
        .text "riok:"
        .byte 13
        .text "        jsr drp"
        .byte 13
        .text "        ldy #0"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        beq rit"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        jmp tm"
        .byte 13
        .text "rit:"
        .byte 13
        .text "        iny"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        iny"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        jsr dadv"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "readstr:"
        .byte 13
        .text "        jsr deof"
        .byte 13
        .text "        bcc rsok"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        jmp ood"
        .byte 13
        .text "rsok:"
        .byte 13
        .text "        jsr drp"
        .byte 13
        .text "        ldy #0"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        cmp #$01"
        .byte 13
        .text "        beq rst"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        jmp tm"
        .byte 13
        .text "rst:"
        .byte 13
        .text "        iny"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        sta strsrc1lo"
        .byte 13
        .text "        iny"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        sta strsrc1hi"
        .byte 13
        .text "        jsr dadv"
        .byte 13
        .text "        lda strsrc1lo"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda strsrc1hi"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13
        .text "        jsr strfromlit"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "deof:"
        .byte 13
        .text "        lda dataptrhi"
        .byte 13
        .text "        cmp #>dataend"
        .byte 13
        .text "        bne dne"
        .byte 13
        .text "        lda dataptrlo"
        .byte 13
        .text "        cmp #<dataend"
        .byte 13
        .text "        bne dne"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        rts"
        .byte 13
        .text "dne:"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "drp:"
        .byte 13
        .text "        lda dataptrlo"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda dataptrhi"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "dadv:"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        lda dataptrlo"
        .byte 13
        .text "        adc #3"
        .byte 13
        .text "        sta dataptrlo"
        .byte 13
        .text "        lda dataptrhi"
        .byte 13
        .text "        adc #0"
        .byte 13
        .text "        sta dataptrhi"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "ood:"
        .byte 13
        .text "        lda #<odm"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda #>odm"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13
        .text "        jsr printstr"
        .byte 13
        .text "        lda #$0d"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "tm:"
        .byte 13
        .text "        lda #<tmm"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda #>tmm"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13
        .text "        jsr printstr"
        .byte 13
        .text "        lda #$0d"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "odm:"
        .byte 13
        .text "        .byte $4f,$55,$54,$20,$4f,$46,$20,$44,$41,$54,$41,$00"
        .byte 13
        .text "tmm:"
        .byte 13
        .text "        .byte $54,$59,$50,$45,$20,$4d,$49,$53,$4d,$41,$54,$43,$48,$00"
        .byte 13
        .text ""
        .byte 13
        .byte 0

out_runtime_array:
        .text "arraybounds:"
        .byte 13
        .text "        lda #$41"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$52"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$52"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$41"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$59"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$20"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$42"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$4f"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$55"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$4e"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$44"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$53"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$0d"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .byte 0

out_runtime_get:
        .text "; get runtime"
        .byte 13
        .text "getkey:"
        .byte 13
        .text "        jsr kernalgetin"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        rts"
        .byte 13
        .text "getstr:"
        .byte 13
        .text "        jsr kernalgetin"
        .byte 13
        .text "        sta digit"
        .byte 13
        .text "        bne getstrgot"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        rts"
        .byte 13
        .text "getstrgot:"
        .byte 13
        .text "        lda #1"
        .byte 13
        .text "        sta strlen"
        .byte 13
        .text "        jsr stralloc"
        .byte 13
        .text "        bcs getstrdone"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda #1"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        ldz #1"
        .byte 13
        .text "        lda digit"
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
        .text "getstrdone:"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .byte 0

out_runtime_storage:
        .text "; integer runtime storage"
        .byte 13
        .text "exprlo:       .byte 0"
        .byte 13
        .text "exprhi:       .byte 0"
        .byte 13
        .text "lhslo:        .byte 0"
        .byte 13
        .text "lhshi:        .byte 0"
        .byte 13
        .text "resultlo:     .byte 0"
        .byte 13
        .text "resulthi:     .byte 0"
        .byte 13
        .text "quotlo:       .byte 0"
        .byte 13
        .text "quothi:       .byte 0"
        .byte 13
        .text "remlo:        .byte 0"
        .byte 13
        .text "remhi:        .byte 0"
        .byte 13
        .text "divlo:        .byte 0"
        .byte 13
        .text "divhi:        .byte 0"
        .byte 13
        .text "digit:        .byte 0"
        .byte 13
        .text "printstarted: .byte 0"
        .byte 13
        .text "printcol:     .byte 0"
        .byte 13
        .text "arrptrlo:     .byte 0"
        .byte 13
        .text "arrptrhi:     .byte 0"
        .byte 13
        .text "dataptrlo:    .byte 0"
        .byte 13
        .text "dataptrhi:    .byte 0"
        .byte 13
        .text "strheaplo:    .byte 0"
        .byte 13
        .text "strheaphi:    .byte 0"
        .byte 13
        .text "strmarksp:    .byte 0"
        .byte 13
        .text "strgctried:   .byte 0"
        .byte 13
        .text "strmarklo:    .fill 8,0"
        .byte 13
        .text "strmarkhi:    .fill 8,0"
        .byte 13
        .text "gcrootlo:     .byte 0"
        .byte 13
        .text "gcroothi:     .byte 0"
        .byte 13
        .text "gcbyteslo:    .byte 0"
        .byte 13
        .text "gcbyteshi:    .byte 0"
        .byte 13
        .text "gcslotlo:     .byte 0"
        .byte 13
        .text "gcslothi:     .byte 0"
        .byte 13
        .text "gcoldlo:      .byte 0"
        .byte 13
        .text "gcoldhi:      .byte 0"
        .byte 13
        .text "strlen:       .byte 0"
        .byte 13
        .text "strlen1:      .byte 0"
        .byte 13
        .text "strlen2:      .byte 0"
        .byte 13
        .text "stridx:       .byte 0"
        .byte 13
        .text "strdstidx:    .byte 0"
        .byte 13
        .text "strcmpchar:   .byte 0"
        .byte 13
        .text "strsrcoff:    .byte 0"
        .byte 13
        .text "strarg1lo:    .byte 0"
        .byte 13
        .text "strarg1hi:    .byte 0"
        .byte 13
        .text "strsrc1lo:    .byte 0"
        .byte 13
        .text "strsrc1hi:    .byte 0"
        .byte 13
        .text "strsrc2lo:    .byte 0"
        .byte 13
        .text "strsrc2hi:    .byte 0"
        .byte 13
        .text "strdstlo:     .byte 0"
        .byte 13
        .text "strdsthi:     .byte 0"
        .byte 13
        .byte 0

        .cerror * > OVR_WINDOW_ADDR + OVR_WINDOW_SIZE, "ovr-rtcore exceeds overlay window"
        .fill OVR_WINDOW_ADDR + OVR_WINDOW_SIZE - *, 0

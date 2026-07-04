;=======================================================================================
; ovr-rtio.asm -- BASIC65C input/runtime I/O emitter overlay
;=======================================================================================

        .cpu "45gs02"
        .include "../../target/basic65c.lbl"

        * = OVR_WINDOW_ADDR

        jmp rtio_overlay_entry

rtio_overlay_entry:
        lda runtime_need_print
        beq _rtio_skip_print
        lda #<out_runtime_print
        ldy #>out_runtime_print
        jsr out_zstr
        lda #<out_runtime_print_storage
        ldy #>out_runtime_print_storage
        jsr out_zstr
_rtio_skip_print:
        lda runtime_need_input
        beq _rtio_skip_input
        lda #<out_runtime_input
        ldy #>out_runtime_input
        jsr out_zstr
        lda #<out_runtime_input_storage
        ldy #>out_runtime_input_storage
        jsr out_zstr
_rtio_skip_input:
        lda runtime_need_decparse
        beq _rtio_skip_decparse
        lda #<out_runtime_decparse
        ldy #>out_runtime_decparse
        jsr out_zstr
_rtio_skip_decparse:
        rts

out_runtime_print:
        .text "; integer print runtime"
        .byte 13
        .text "printch:"
        .byte 13
        .text "        cmp #$0d"
        .byte 13
        .text "        beq printchcr"
        .byte 13
        .text "        pha"
        .byte 13
        .text "        jsr kernalchrout"
        .byte 13
        .text "        pla"
        .byte 13
        .text "        inc printcol"
        .byte 13
        .text "        lda printcol"
        .byte 13
        .text "        cmp #10"
        .byte 13
        .text "        bcc printchdone"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta printcol"
        .byte 13
        .text "printchdone:"
        .byte 13
        .text "        rts"
        .byte 13
        .text "printchcr:"
        .byte 13
        .text "        phx"
        .byte 13
        .text "        phy"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        jsr kernalplot"
        .byte 13
        .text "        stx sr"
        .byte 13
        .text "        jsr kernalscreen"
        .byte 13
        .text "        dey"
        .byte 13
        .text "        cpy sr"
        .byte 13
        .text "        beq pccs"
        .byte 13
        .text "        lda #$0d"
        .byte 13
        .text "        jsr kernalchrout"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta printcol"
        .byte 13
        .text "        ply"
        .byte 13
        .text "        plx"
        .byte 13
        .text "        rts"
        .byte 13
        .text "pccs:"
        .byte 13
        .text "        jsr printscroll"
        .byte 13
        .text "        ldx sr"
        .byte 13
        .text "        ldy #0"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        jsr kernalplot"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta printcol"
        .byte 13
        .text "        ply"
        .byte 13
        .text "        plx"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "printstr:"
        .byte 13
        .text "        lda rtptr"
        .byte 13
        .text "        ora rtptr+1"
        .byte 13
        .text "        beq printstrdone"
        .byte 13
        .text "        ldy #0"
        .byte 13
        .text "printstrloop:"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        beq printstrdone"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        iny"
        .byte 13
        .text "        bne printstrloop"
        .byte 13
        .text "printstrdone:"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "printcomma:"
        .byte 13
        .text "        lda #$20"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda printcol"
        .byte 13
        .text "        bne printcomma"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "printuint:"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        bpl printpos"
        .byte 13
        .text "        lda #'-'"
        .byte 13
        .text "        jsr printch"
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
        .text "        jmp printdigits"
        .byte 13
        .text "printpos:"
        .byte 13
        .text "        lda #' '"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "printdigits:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta printstarted"
        .byte 13
        .text "        lda #<$2710"
        .byte 13
        .text "        ldy #>$2710"
        .byte 13
        .text "        jsr printdigit"
        .byte 13
        .text "        lda #<$03e8"
        .byte 13
        .text "        ldy #>$03e8"
        .byte 13
        .text "        jsr printdigit"
        .byte 13
        .text "        lda #<$0064"
        .byte 13
        .text "        ldy #>$0064"
        .byte 13
        .text "        jsr printdigit"
        .byte 13
        .text "        lda #<$000a"
        .byte 13
        .text "        ldy #>$000a"
        .byte 13
        .text "        jsr printdigit"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        adc #'0'"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #' '"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "printdigit:"
        .byte 13
        .text "        sta divlo"
        .byte 13
        .text "        sty divhi"
        .byte 13
        .text "        lda #'0'"
        .byte 13
        .text "        sta digit"
        .byte 13
        .text "pdloop:"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        cmp divhi"
        .byte 13
        .text "        bcc pddone"
        .byte 13
        .text "        bne pdsub"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        cmp divlo"
        .byte 13
        .text "        bcc pddone"
        .byte 13
        .text "pdsub:"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        sbc divlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        sbc divhi"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        inc digit"
        .byte 13
        .text "        jmp pdloop"
        .byte 13
        .text "pddone:"
        .byte 13
        .text "        lda digit"
        .byte 13
        .text "        cmp #'0'"
        .byte 13
        .text "        bne pdemit"
        .byte 13
        .text "        lda printstarted"
        .byte 13
        .text "        beq pdreturn"
        .byte 13
        .text "        lda digit"
        .byte 13
        .text "pdemit:"
        .byte 13
        .text "        sta digit"
        .byte 13
        .text "        lda #1"
        .byte 13
        .text "        sta printstarted"
        .byte 13
        .text "        lda digit"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "pdreturn:"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .text "printscroll:"
        .byte 13
        .text "        lda varptr"
        .byte 13
        .text "        pha"
        .byte 13
        .text "        lda varptr+1"
        .byte 13
        .text "        pha"
        .byte 13
        .text "        lda varptr+2"
        .byte 13
        .text "        pha"
        .byte 13
        .text "        lda varptr+3"
        .byte 13
        .text "        pha"
        .byte 13
        .text "        lda rtptr"
        .byte 13
        .text "        pha"
        .byte 13
        .text "        lda rtptr+1"
        .byte 13
        .text "        pha"
        .byte 13
        .text "        lda rtptr+2"
        .byte 13
        .text "        pha"
        .byte 13
        .text "        lda rtptr+3"
        .byte 13
        .text "        pha"
        .byte 13
        .text "        lda #<$0800"
        .byte 13
        .text "        sta varptr"
        .byte 13
        .text "        lda #>$0800"
        .byte 13
        .text "        sta varptr+1"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta varptr+2"
        .byte 13
        .text "        sta varptr+3"
        .byte 13
        .text "        lda #<$0850"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda #>$0850"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta rtptr+2"
        .byte 13
        .text "        sta rtptr+3"
        .byte 13
        .text "        jsr psc"
        .byte 13
        .text "        lda #<$0f80"
        .byte 13
        .text "        sta varptr"
        .byte 13
        .text "        lda #>$0f80"
        .byte 13
        .text "        sta varptr+1"
        .byte 13
        .text "        lda #$20"
        .byte 13
        .text "        jsr psf"
        .byte 13
        .text "        lda #<$f800"
        .byte 13
        .text "        sta varptr"
        .byte 13
        .text "        lda #>$f800"
        .byte 13
        .text "        sta varptr+1"
        .byte 13
        .text "        lda #1"
        .byte 13
        .text "        sta varptr+2"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta varptr+3"
        .byte 13
        .text "        lda #<$f850"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda #>$f850"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13
        .text "        lda #1"
        .byte 13
        .text "        sta rtptr+2"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta rtptr+3"
        .byte 13
        .text "        jsr psc"
        .byte 13
        .text "        lda #<$ff80"
        .byte 13
        .text "        sta varptr"
        .byte 13
        .text "        lda #>$ff80"
        .byte 13
        .text "        sta varptr+1"
        .byte 13
        .text "        lda #1"
        .byte 13
        .text "        sta varptr+2"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta varptr+3"
        .byte 13
        .text "        lda #$01"
        .byte 13
        .text "        jsr psf"
        .byte 13
        .text "        pla"
        .byte 13
        .text "        sta rtptr+3"
        .byte 13
        .text "        pla"
        .byte 13
        .text "        sta rtptr+2"
        .byte 13
        .text "        pla"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13
        .text "        pla"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        pla"
        .byte 13
        .text "        sta varptr+3"
        .byte 13
        .text "        pla"
        .byte 13
        .text "        sta varptr+2"
        .byte 13
        .text "        pla"
        .byte 13
        .text "        sta varptr+1"
        .byte 13
        .text "        pla"
        .byte 13
        .text "        sta varptr"
        .byte 13
        .text "        rts"
        .byte 13
        .text "psc:"
        .byte 13
        .text "        lda #<$0780"
        .byte 13
        .text "        sta scl"
        .byte 13
        .text "        lda #>$0780"
        .byte 13
        .text "        sta sch"
        .byte 13
        .text "pcl:"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda [rtptr],z"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        jsr pib"
        .byte 13
        .text "        jsr pdc"
        .byte 13
        .text "        bne pcl"
        .byte 13
        .text "        rts"
        .byte 13
        .text "psf:"
        .byte 13
        .text "        sta sf"
        .byte 13
        .text "        lda #<$0050"
        .byte 13
        .text "        sta scl"
        .byte 13
        .text "        lda #>$0050"
        .byte 13
        .text "        sta sch"
        .byte 13
        .text "pfl:"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda sf"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        jsr pid"
        .byte 13
        .text "        jsr pdc"
        .byte 13
        .text "        bne pfl"
        .byte 13
        .text "        rts"
        .byte 13
        .text "pib:"
        .byte 13
        .text "        inc rtptr"
        .byte 13
        .text "        bne pid"
        .byte 13
        .text "        inc rtptr+1"
        .byte 13
        .text "pid:"
        .byte 13
        .text "        inc varptr"
        .byte 13
        .text "        bne pir"
        .byte 13
        .text "        inc varptr+1"
        .byte 13
        .text "pir:"
        .byte 13
        .text "        rts"
        .byte 13
        .text "pdc:"
        .byte 13
        .text "        lda scl"
        .byte 13
        .text "        bne pdl"
        .byte 13
        .text "        dec sch"
        .byte 13
        .text "pdl:"
        .byte 13
        .text "        dec scl"
        .byte 13
        .text "        lda scl"
        .byte 13
        .text "        ora sch"
        .byte 13
        .text "        rts"
        .byte 13
        .text ""
        .byte 13
        .byte 0

out_runtime_input:
        .text "; input runtime"
        .byte 13
        .text "inputline:"
        .byte 13
        .text "        lda #$3f"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #$20"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta inputpos"
        .byte 13
        .text "        sta inputlen"
        .byte 13
        .text "inputlineloop:"
        .byte 13
        .text "        jsr kernalchrin"
        .byte 13
        .text "        cmp #$0d"
        .byte 13
        .text "        beq inputlinedone"
        .byte 13
        .text "        ldx inputlen"
        .byte 13
        .text "        cpx #80"
        .byte 13
        .text "        bcs inputlineloop"
        .byte 13
        .text "        sta inputbuf,x"
        .byte 13
        .text "        inc inputlen"
        .byte 13
        .text "        jmp inputlineloop"
        .byte 13
        .text "inputlinedone:"
        .byte 13
        .text "        ldx inputlen"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta inputbuf,x"
        .byte 13
        .text "        lda #$0d"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta printcol"
        .byte 13
        .text "        sta inputpos"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .text "inputskipspaces:"
        .byte 13
        .text "        ldx inputpos"
        .byte 13
        .text "        lda inputbuf,x"
        .byte 13
        .text "        cmp #$20"
        .byte 13
        .text "        bne inputskipdone"
        .byte 13
        .text "        inc inputpos"
        .byte 13
        .text "        jmp inputskipspaces"
        .byte 13
        .text "inputskipdone:"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .text "inputint:"
        .byte 13
        .text "        jsr inputskipspaces"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        sta inputneg"
        .byte 13
        .text "        sta inputdigits"
        .byte 13
        .text "inputloop:"
        .byte 13
        .text "        ldx inputpos"
        .byte 13
        .text "        lda inputbuf,x"
        .byte 13
        .text "        beq inputdone"
        .byte 13
        .text "        cmp #$2c"
        .byte 13
        .text "        beq inputcomma"
        .byte 13
        .text "        cmp #$20"
        .byte 13
        .text "        beq inputadvance"
        .byte 13
        .text "        cmp #$2d"
        .byte 13
        .text "        beq inputminus"
        .byte 13
        .text "        cmp #$2b"
        .byte 13
        .text "        beq inputplus"
        .byte 13
        .text "        cmp #$30"
        .byte 13
        .text "        bcc inputadvance"
        .byte 13
        .text "        cmp #$3a"
        .byte 13
        .text "        bcs inputadvance"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        sbc #$30"
        .byte 13
        .text "        sta digit"
        .byte 13
        .text "        jsr inputmul10add"
        .byte 13
        .text "        inc inputdigits"
        .byte 13
        .text "        inc inputpos"
        .byte 13
        .text "        jmp inputloop"
        .byte 13
        .text "inputadvance:"
        .byte 13
        .text "        inc inputpos"
        .byte 13
        .text "        jmp inputloop"
        .byte 13
        .text "inputcomma:"
        .byte 13
        .text "        inc inputpos"
        .byte 13
        .text "        jmp inputdone"
        .byte 13
        .text "inputminus:"
        .byte 13
        .text "        lda inputdigits"
        .byte 13
        .text "        bne inputadvance"
        .byte 13
        .text "        lda #1"
        .byte 13
        .text "        sta inputneg"
        .byte 13
        .text "        inc inputpos"
        .byte 13
        .text "        jmp inputloop"
        .byte 13
        .text "inputplus:"
        .byte 13
        .text "        lda inputdigits"
        .byte 13
        .text "        bne inputadvance"
        .byte 13
        .text "        inc inputpos"
        .byte 13
        .text "        jmp inputloop"
        .byte 13
        .text "inputdone:"
        .byte 13
        .text "        lda inputneg"
        .byte 13
        .text "        beq inputreturn"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        ora exprhi"
        .byte 13
        .text "        beq inputreturn"
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
        .text "inputreturn:"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .text "inputstr:"
        .byte 13
        .text "        jsr inputskipspaces"
        .byte 13
        .text "        lda inputpos"
        .byte 13
        .text "        sta inputfieldstart"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta strlen"
        .byte 13
        .text "inputstrlenloop:"
        .byte 13
        .text "        ldx inputpos"
        .byte 13
        .text "        lda inputbuf,x"
        .byte 13
        .text "        beq inputstralloc"
        .byte 13
        .text "        cmp #$2c"
        .byte 13
        .text "        beq inputstrcomma"
        .byte 13
        .text "        inc inputpos"
        .byte 13
        .text "        inc strlen"
        .byte 13
        .text "        jmp inputstrlenloop"
        .byte 13
        .text "inputstrcomma:"
        .byte 13
        .text "        inc inputpos"
        .byte 13
        .text "inputstralloc:"
        .byte 13
        .text "        jsr stralloc"
        .byte 13
        .text "        bcs inputstrdone"
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
        .text "inputstrcopy:"
        .byte 13
        .text "        lda stridx"
        .byte 13
        .text "        cmp strlen"
        .byte 13
        .text "        beq inputstrfinish"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        lda inputfieldstart"
        .byte 13
        .text "        adc stridx"
        .byte 13
        .text "        tax"
        .byte 13
        .text "        lda inputbuf,x"
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
        .text "        jmp inputstrcopy"
        .byte 13
        .text "inputstrfinish:"
        .byte 13
        .text "        lda strdstlo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda strdsthi"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "inputstrdone:"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .byte 0

out_runtime_decparse:
        .text "; decimal parse helper"
        .byte 13
        .text "inputmul10add:"
        .byte 13
        .text "        asl exprlo"
        .byte 13
        .text "        rol exprhi"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        sta lhslo"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        sta lhshi"
        .byte 13
        .text "        asl exprlo"
        .byte 13
        .text "        rol exprhi"
        .byte 13
        .text "        asl exprlo"
        .byte 13
        .text "        rol exprhi"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        adc lhslo"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        adc lhshi"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        adc digit"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        adc #0"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .byte 0

out_runtime_print_storage:
        .text "; print runtime storage"
        .byte 13
        .text "sr: .byte 0"
        .byte 13
        .text "scl:.byte 0"
        .byte 13
        .text "sch:.byte 0"
        .byte 13
        .text "sf: .byte 0"
        .byte 13
        .byte 0

out_runtime_input_storage:
        .text "; input runtime storage"
        .byte 13
        .text "inputpos:     .byte 0"
        .byte 13
        .text "inputlen:     .byte 0"
        .byte 13
        .text "inputfieldstart: .byte 0"
        .byte 13
        .text "inputneg:     .byte 0"
        .byte 13
        .text "inputdigits:  .byte 0"
        .byte 13
        .text "inputbuf:     .fill 81,0"
        .byte 13
        .byte 0

        .cerror * > OVR_WINDOW_ADDR + OVR_WINDOW_SIZE, "ovr-rtio exceeds overlay window"
        .fill OVR_WINDOW_ADDR + OVR_WINDOW_SIZE - *, 0

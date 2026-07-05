;=======================================================================================
; ovr-rtnum.asm -- BASIC65C tagged numeric variable runtime emitter overlay
;=======================================================================================

        .cpu "45gs02"
        .include "../../target/basic65c.lbl"

        * = OVR_WINDOW_ADDR

        jmp rtnum_overlay_entry

rtnum_overlay_entry:
        lda #<out_runtime_numvar
        ldy #>out_runtime_numvar
        jsr out_zstr
        rts

out_runtime_numvar:
        .text "; tagged numeric variable runtime"
        .byte 13
        .text "loadnumvar:"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        beq loadnumint"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        rts"
        .byte 13
        .text "loadnumint:"
        .byte 13
        .text "        ldz #1"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        sta exprlo"
        .byte 13
        .text "        ldz #2"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        sta exprhi"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .text "storenumvar:"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        ldz #1"
        .byte 13
        .text "        lda exprlo"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        ldz #2"
        .byte 13
        .text "        lda exprhi"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .text "storefloatref:"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda #1"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        ldz #1"
        .byte 13
        .text "        lda rtptr"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        ldz #2"
        .byte 13
        .text "        lda rtptr+1"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .text "printnumvar:"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        beq printnumint"
        .byte 13
        .text "        ldz #1"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        ldz #2"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13
        .text "        jmp printfloatref"
        .byte 13
        .text "printnumint:"
        .byte 13
        .text "        jsr loadnumvar"
        .byte 13
        .text "        jmp printuint"
        .byte 13
        .byte 13
        .text "printfloatref:"
        .byte 13
        .text "        lda rtptr"
        .byte 13
        .text "        ora rtptr+1"
        .byte 13
        .text "        beq printfloatdone"
        .byte 13
        .text "        ldy #0"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        cmp #'-'"
        .byte 13
        .text "        beq printfloatbody"
        .byte 13
        .text "        lda #' '"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "printfloatbody:"
        .byte 13
        .text "        jsr printstr"
        .byte 13
        .text "        lda #' '"
        .byte 13
        .text "        jsr printch"
        .byte 13
        .text "printfloatdone:"
        .byte 13
        .text "        rts"
        .byte 13
        .byte 13
        .byte 0

        .cerror * > OVR_WINDOW_ADDR + OVR_WINDOW_SIZE, "ovr-rtnum exceeds overlay window"
        .fill OVR_WINDOW_ADDR + OVR_WINDOW_SIZE - *, 0

;=======================================================================================
; ovr-rtgc.asm -- BASIC65C string garbage collector runtime emitter overlay
;=======================================================================================

        .cpu "45gs02"
        .include "../../target/basic65c.lbl"

        * = OVR_WINDOW_ADDR

        jmp rtgc_overlay_entry

rtgc_overlay_entry:
        lda #<out_runtime_gc
        ldy #>out_runtime_gc
        jsr out_zstr
        rts

out_runtime_gc:
        .text "; string garbage collector runtime"
        .byte 13
        .text "strgc:"
        .byte 13
        .text "        lda #<$f800"
        .byte 13
        .text "        sta strdstlo"
        .byte 13
        .text "        lda #>$f800"
        .byte 13
        .text "        sta strdsthi"
        .byte 13
        .text "        lda #<strroots"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda #>strroots"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13
        .text "strgcroot:"
        .byte 13
        .text "        ldy #0"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        sta gcrootlo"
        .byte 13
        .text "        iny"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        sta gcroothi"
        .byte 13
        .text "        iny"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        sta gcbyteslo"
        .byte 13
        .text "        iny"
        .byte 13
        .text "        lda (rtptr),y"
        .byte 13
        .text "        sta gcbyteshi"
        .byte 13
        .text "        lda gcrootlo"
        .byte 13
        .text "        ora gcroothi"
        .byte 13
        .text "        ora gcbyteslo"
        .byte 13
        .text "        ora gcbyteshi"
        .byte 13
        .text "        beq strgcdone"
        .byte 13
        .text "        lda gcrootlo"
        .byte 13
        .text "        sta gcslotlo"
        .byte 13
        .text "        lda gcroothi"
        .byte 13
        .text "        sta gcslothi"
        .byte 13
        .text "strgcslot:"
        .byte 13
        .text "        lda gcbyteslo"
        .byte 13
        .text "        ora gcbyteshi"
        .byte 13
        .text "        beq strgcnextroot"
        .byte 13
        .text "        jsr strgcloadroot"
        .byte 13
        .text "        lda gcoldlo"
        .byte 13
        .text "        ora gcoldhi"
        .byte 13
        .text "        beq strgcslotnext"
        .byte 13
        .text "        lda gcoldlo"
        .byte 13
        .text "        sta strsrc1lo"
        .byte 13
        .text "        lda gcoldhi"
        .byte 13
        .text "        sta strsrc1hi"
        .byte 13
        .text "        jsr setstrptrsrc1"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        sta strlen1"
        .byte 13
        .text "        jsr strgcallocdst"
        .byte 13
        .text "        lda strdsthi"
        .byte 13
        .text "        cmp strsrc1hi"
        .byte 13
        .text "        bcc strgccopyfwd"
        .byte 13
        .text "        bne strgccopyback"
        .byte 13
        .text "        lda strdstlo"
        .byte 13
        .text "        cmp strsrc1lo"
        .byte 13
        .text "        bcc strgccopyfwd"
        .byte 13
        .text "        beq strgcupdateroot"
        .byte 13
        .text "strgccopyback:"
        .byte 13
        .text "        lda strlen1"
        .byte 13
        .text "        sta stridx"
        .byte 13
        .text "strgccopybackloop:"
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
        .text "        lda stridx"
        .byte 13
        .text "        beq strgcupdateroot"
        .byte 13
        .text "        dec stridx"
        .byte 13
        .text "        jmp strgccopybackloop"
        .byte 13
        .text "strgccopyfwd:"
        .byte 13
        .text "        lda #0"
        .byte 13
        .text "        sta stridx"
        .byte 13
        .text "strgccopyfwdloop:"
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
        .text "        lda stridx"
        .byte 13
        .text "        cmp strlen1"
        .byte 13
        .text "        beq strgcupdateroot"
        .byte 13
        .text "        inc stridx"
        .byte 13
        .text "        jmp strgccopyfwdloop"
        .byte 13
        .text "strgcupdateroot:"
        .byte 13
        .text "        lda gcslotlo"
        .byte 13
        .text "        sta varptr"
        .byte 13
        .text "        lda gcslothi"
        .byte 13
        .text "        sta varptr+1"
        .byte 13
        .text "        jsr setstrptrbank"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda strdstlo"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "        ldz #1"
        .byte 13
        .text "        lda strdsthi"
        .byte 13
        .text "        sta [varptr],z"
        .byte 13
        .text "strgcslotnext:"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        lda gcslotlo"
        .byte 13
        .text "        adc #2"
        .byte 13
        .text "        sta gcslotlo"
        .byte 13
        .text "        lda gcslothi"
        .byte 13
        .text "        adc #0"
        .byte 13
        .text "        sta gcslothi"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        lda gcbyteslo"
        .byte 13
        .text "        sbc #2"
        .byte 13
        .text "        sta gcbyteslo"
        .byte 13
        .text "        lda gcbyteshi"
        .byte 13
        .text "        sbc #0"
        .byte 13
        .text "        sta gcbyteshi"
        .byte 13
        .text "        jmp strgcslot"
        .byte 13
        .text "strgcnextroot:"
        .byte 13
        .text "        clc"
        .byte 13
        .text "        lda rtptr"
        .byte 13
        .text "        adc #4"
        .byte 13
        .text "        sta rtptr"
        .byte 13
        .text "        lda rtptr+1"
        .byte 13
        .text "        adc #0"
        .byte 13
        .text "        sta rtptr+1"
        .byte 13
        .text "        jmp strgcroot"
        .byte 13
        .text "strgcdone:"
        .byte 13
        .text "        lda strdstlo"
        .byte 13
        .text "        sta strheaplo"
        .byte 13
        .text "        lda strdsthi"
        .byte 13
        .text "        sta strheaphi"
        .byte 13
        .text "        rts"
        .byte 13
        .text "strgcloadroot:"
        .byte 13
        .text "        lda gcslotlo"
        .byte 13
        .text "        sta varptr"
        .byte 13
        .text "        lda gcslothi"
        .byte 13
        .text "        sta varptr+1"
        .byte 13
        .text "        jsr setstrptrbank"
        .byte 13
        .text "        ldz #0"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        sta gcoldlo"
        .byte 13
        .text "        ldz #1"
        .byte 13
        .text "        lda [varptr],z"
        .byte 13
        .text "        sta gcoldhi"
        .byte 13
        .text "        rts"
        .byte 13
        .text "strgcallocdst:"
        .byte 13
        .text "        sec"
        .byte 13
        .text "        lda strdstlo"
        .byte 13
        .text "        sbc strlen1"
        .byte 13
        .text "        sta strdstlo"
        .byte 13
        .text "        lda strdsthi"
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
        .text "        rts"
        .byte 13
        .byte 0

        .cerror * > OVR_WINDOW_ADDR + OVR_WINDOW_SIZE, "ovr-rtgc exceeds overlay window"
        .fill OVR_WINDOW_ADDR + OVR_WINDOW_SIZE - *, 0

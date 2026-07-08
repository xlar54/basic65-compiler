;=======================================================================================
; draw_rect - Draw rectangle (outline or filled)
; Input: rect_x (16-bit), rect_y (8-bit), rect_w (16-bit), rect_h (8-bit)
;        rect_col (8-bit): color for flat fill or outline
;        rect_grad (8-bit): 0 = flat color, nonzero = use gradient lookup
;        Carry: clear=outline, set=filled
;
; Gradient-aware: when rect_grad != 0, uses grad_get_color per scanline.
; Set up gradient palette with grad_build_palette before calling.
;=======================================================================================
rect_x:     .word 0
rect_y:     .byte 0
rect_w:     .word 0
rect_h:     .byte 0
rect_col:   .byte 0
rect_grad:  .byte 0             ; 0=flat, nonzero=gradient

draw_rect:
        lda #0
        rol
        sta _rc_fill

        clc
        lda rect_x
        adc rect_w
        sta _rc_x1
        lda rect_x+1
        adc rect_w+1
        sta _rc_x1+1
        
        lda _rc_x1
        bne +
        dec _rc_x1+1
+       dec _rc_x1

        clc
        lda rect_y
        adc rect_h
        sec
        sbc #1
        sta _rc_y1

        lda rect_col
        sta line_col

        lda _rc_fill
        bne _rc_do_fill

        ; Top line
        lda rect_x
        sta line_x0
        lda rect_x+1
        sta line_x0+1
        lda rect_y
        sta line_y0
        lda _rc_x1
        sta line_x1
        lda _rc_x1+1
        sta line_x1+1
        lda rect_y
        sta line_y1
        jsr draw_line

        ; Bottom line
        lda rect_x
        sta line_x0
        lda rect_x+1
        sta line_x0+1
        lda _rc_y1
        sta line_y0
        lda _rc_x1
        sta line_x1
        lda _rc_x1+1
        sta line_x1+1
        lda _rc_y1
        sta line_y1
        jsr draw_line

        ; Left line
        lda rect_x
        sta line_x0
        sta line_x1
        lda rect_x+1
        sta line_x0+1
        sta line_x1+1
        lda rect_y
        sta line_y0
        lda _rc_y1
        sta line_y1
        jsr draw_line

        ; Right line
        lda _rc_x1
        sta line_x0
        sta line_x1
        lda _rc_x1+1
        sta line_x0+1
        sta line_x1+1
        lda rect_y
        sta line_y0
        lda _rc_y1
        sta line_y1
        jsr draw_line

        rts

_rc_do_fill:
        lda rect_x
        sta line_x0
        lda rect_x+1
        sta line_x0+1
        lda _rc_x1
        sta line_x1
        lda _rc_x1+1
        sta line_x1+1

        lda rect_y
        sta _rc_cur_y

_rc_fill_loop:
        lda _rc_cur_y
        sta line_y0
        sta line_y1
        jsr _rc_set_line_col
        jsr fill_hline

        inc _rc_cur_y
        lda _rc_cur_y
        cmp _rc_y1
        beq _rc_fill_last
        bcc _rc_fill_loop
        rts

_rc_fill_last:
        lda _rc_cur_y
        sta line_y0
        sta line_y1
        jsr _rc_set_line_col
        jsr fill_hline
        rts

;---------------------------------------------------------------------------------------
; _rc_set_line_col - Set line_col from gradient or flat color
; Input: line_y0 already set to the scanline Y
;---------------------------------------------------------------------------------------
_rc_set_line_col:
        lda rect_grad
        beq +
        lda line_y0
        jsr grad_get_color
        sta line_col
        rts
+       lda rect_col
        sta line_col
        rts

_rc_x1:     .word 0
_rc_y1:     .byte 0
_rc_fill:   .byte 0
_rc_cur_y:  .byte 0
;=======================================================================================
; Gradient-aware fill support for circle, ellipse, and polygon
;
; To use gradient fill on any shape:
;   1. Set grad_r1/g1/b1, grad_r2/g2/b2, grad_pal, grad_y_top, grad_y_bot
;   2. Call grad_build_palette
;   3. Set shape_grad to nonzero (circ_grad, elip_grad, or poly_grad)
;   4. Call the shape's draw routine with SEC (filled)
;
; When shape_grad is 0 (default), shapes work exactly as before.
; The gradient is always vertical (top-to-bottom).
;=======================================================================================


;=======================================================================================
; draw_circle - Draw circle (outline or filled) using midpoint algorithm
; Input: circ_cx (16-bit), circ_cy (8-bit), circ_r (8-bit), circ_col (8-bit)
;        circ_grad (8-bit): 0 = flat color, nonzero = use gradient lookup
;        Carry: clear=outline, set=filled
; Automatically doubles x offsets in 80-col mode for correct aspect ratio
;=======================================================================================
circ_cx:    .word 0
circ_cy:    .byte 0
circ_r:     .byte 0
circ_col:   .byte 0
circ_grad:  .byte 0             ; 0=flat, nonzero=gradient

draw_circle:
        lda #0
        rol
        sta _cr_fill

        lda #0
        sta _cr_x
        lda circ_r
        sta _cr_y

        sec
        lda #1
        sbc circ_r
        sta _cr_d
        lda #0
        sbc #0
        sta _cr_d+1

_cr_loop:
        lda _cr_x
        cmp _cr_y
        beq +
        bcs _cr_done
+
        ; Compute aspect-corrected horizontal offsets
        lda _cr_x
        sta _cr_xh
        lda #0
        sta _cr_xh+1
        lda _cr_y
        sta _cr_yh
        lda #0
        sta _cr_yh+1

        lda screen_mode
        cmp #80
        bne _cr_no_scale
        asl _cr_xh
        rol _cr_xh+1
        asl _cr_yh
        rol _cr_yh+1
_cr_no_scale:

        lda _cr_fill
        bne _cr_do_fill
        jsr _cr_plot_8
        jmp _cr_update

_cr_do_fill:
        jsr _cr_fill_lines

_cr_update:
        lda _cr_d+1
        bmi _cr_d_neg

        lda _cr_x
        sec
        sbc _cr_y
        sta _cr_tmp
        lda #0
        sbc #0
        sta _cr_tmp+1
        asl _cr_tmp
        rol _cr_tmp+1
        clc
        lda _cr_tmp
        adc #5
        sta _cr_tmp
        lda _cr_tmp+1
        adc #0
        sta _cr_tmp+1
        clc
        lda _cr_d
        adc _cr_tmp
        sta _cr_d
        lda _cr_d+1
        adc _cr_tmp+1
        sta _cr_d+1
        dec _cr_y
        jmp _cr_inc_x

_cr_d_neg:
        lda _cr_x
        asl
        clc
        adc #3
        sta _cr_tmp
        lda #0
        adc #0
        sta _cr_tmp+1
        clc
        lda _cr_d
        adc _cr_tmp
        sta _cr_d
        lda _cr_d+1
        adc _cr_tmp+1
        sta _cr_d+1

_cr_inc_x:
        inc _cr_x
        jmp _cr_loop

_cr_done:
        rts

;---------------------------------------------------------------------------------------
; _cr_plot_8 - Plot 8 symmetric points (outline mode, unchanged)
;---------------------------------------------------------------------------------------
_cr_plot_8:
        lda circ_col
        sta plot_col

        ; Point 1: (cx+xh, cy+y)
        clc
        lda circ_cx
        adc _cr_xh
        sta plot_x
        lda circ_cx+1
        adc _cr_xh+1
        sta plot_x+1
        bmi +
        clc
        lda circ_cy
        adc _cr_y
        bcs +
        cmp #200
        bcs +
        sta plot_y
        jsr plot_pixel
+
        ; Point 2: (cx-xh, cy+y)
        sec
        lda circ_cx
        sbc _cr_xh
        sta plot_x
        lda circ_cx+1
        sbc _cr_xh+1
        sta plot_x+1
        bmi +
        clc
        lda circ_cy
        adc _cr_y
        bcs +
        cmp #200
        bcs +
        sta plot_y
        jsr plot_pixel
+
        ; Point 3: (cx+xh, cy-y)
        clc
        lda circ_cx
        adc _cr_xh
        sta plot_x
        lda circ_cx+1
        adc _cr_xh+1
        sta plot_x+1
        bmi +
        sec
        lda circ_cy
        sbc _cr_y
        bcc +
        cmp #200
        bcs +
        sta plot_y
        jsr plot_pixel
+
        ; Point 4: (cx-xh, cy-y)
        sec
        lda circ_cx
        sbc _cr_xh
        sta plot_x
        lda circ_cx+1
        sbc _cr_xh+1
        sta plot_x+1
        bmi +
        sec
        lda circ_cy
        sbc _cr_y
        bcc +
        cmp #200
        bcs +
        sta plot_y
        jsr plot_pixel
+
        ; Point 5: (cx+yh, cy+x)
        clc
        lda circ_cx
        adc _cr_yh
        sta plot_x
        lda circ_cx+1
        adc _cr_yh+1
        sta plot_x+1
        bmi +
        clc
        lda circ_cy
        adc _cr_x
        bcs +
        cmp #200
        bcs +
        sta plot_y
        jsr plot_pixel
+
        ; Point 6: (cx-yh, cy+x)
        sec
        lda circ_cx
        sbc _cr_yh
        sta plot_x
        lda circ_cx+1
        sbc _cr_yh+1
        sta plot_x+1
        bmi +
        clc
        lda circ_cy
        adc _cr_x
        bcs +
        cmp #200
        bcs +
        sta plot_y
        jsr plot_pixel
+
        ; Point 7: (cx+yh, cy-x)
        clc
        lda circ_cx
        adc _cr_yh
        sta plot_x
        lda circ_cx+1
        adc _cr_yh+1
        sta plot_x+1
        bmi +
        sec
        lda circ_cy
        sbc _cr_x
        bcc +
        cmp #200
        bcs +
        sta plot_y
        jsr plot_pixel
+
        ; Point 8: (cx-yh, cy-x)
        sec
        lda circ_cx
        sbc _cr_yh
        sta plot_x
        lda circ_cx+1
        sbc _cr_yh+1
        sta plot_x+1
        bmi +
        sec
        lda circ_cy
        sbc _cr_x
        bcc +
        cmp #200
        bcs +
        sta plot_y
        jsr plot_pixel
+
        rts

;---------------------------------------------------------------------------------------
; _cr_fill_lines - Draw 4 horizontal lines for filled circle
; Gradient-aware: when circ_grad != 0, uses grad_get_color per scanline
;---------------------------------------------------------------------------------------
_cr_fill_lines:
        ; Line 1: cy+y from cx-xh to cx+xh
        clc
        lda circ_cy
        adc _cr_y
        bcs _cr_fl_skip1
        cmp #200
        bcs _cr_fl_skip1
        sta line_y0
        sta line_y1
        jsr _cr_set_line_col    ; sets line_col based on line_y0
        sec
        lda circ_cx
        sbc _cr_xh
        sta line_x0
        lda circ_cx+1
        sbc _cr_xh+1
        sta line_x0+1
        bpl +
        lda #0
        sta line_x0
        sta line_x0+1
+       clc
        lda circ_cx
        adc _cr_xh
        sta line_x1
        lda circ_cx+1
        adc _cr_xh+1
        sta line_x1+1
        bmi _cr_fl_skip1
        jsr fill_hline
_cr_fl_skip1:

        ; Line 2: cy-y from cx-xh to cx+xh
        sec
        lda circ_cy
        sbc _cr_y
        bcc _cr_fl_skip2
        cmp #200
        bcs _cr_fl_skip2
        sta line_y0
        sta line_y1
        jsr _cr_set_line_col
        sec
        lda circ_cx
        sbc _cr_xh
        sta line_x0
        lda circ_cx+1
        sbc _cr_xh+1
        sta line_x0+1
        bpl +
        lda #0
        sta line_x0
        sta line_x0+1
+       clc
        lda circ_cx
        adc _cr_xh
        sta line_x1
        lda circ_cx+1
        adc _cr_xh+1
        sta line_x1+1
        bmi _cr_fl_skip2
        jsr fill_hline
_cr_fl_skip2:

        ; Line 3: cy+x from cx-yh to cx+yh
        clc
        lda circ_cy
        adc _cr_x
        bcs _cr_fl_skip3
        cmp #200
        bcs _cr_fl_skip3
        sta line_y0
        sta line_y1
        jsr _cr_set_line_col
        sec
        lda circ_cx
        sbc _cr_yh
        sta line_x0
        lda circ_cx+1
        sbc _cr_yh+1
        sta line_x0+1
        bpl +
        lda #0
        sta line_x0
        sta line_x0+1
+       clc
        lda circ_cx
        adc _cr_yh
        sta line_x1
        lda circ_cx+1
        adc _cr_yh+1
        sta line_x1+1
        bmi _cr_fl_skip3
        jsr fill_hline
_cr_fl_skip3:

        ; Line 4: cy-x from cx-yh to cx+yh
        sec
        lda circ_cy
        sbc _cr_x
        bcc _cr_fl_skip4
        cmp #200
        bcs _cr_fl_skip4
        sta line_y0
        sta line_y1
        jsr _cr_set_line_col
        sec
        lda circ_cx
        sbc _cr_yh
        sta line_x0
        lda circ_cx+1
        sbc _cr_yh+1
        sta line_x0+1
        bpl +
        lda #0
        sta line_x0
        sta line_x0+1
+       clc
        lda circ_cx
        adc _cr_yh
        sta line_x1
        lda circ_cx+1
        adc _cr_yh+1
        sta line_x1+1
        bmi _cr_fl_skip4
        jsr fill_hline
_cr_fl_skip4:
        rts

;---------------------------------------------------------------------------------------
; _cr_set_line_col - Set line_col from gradient or flat color
; Input: line_y0 already set to the scanline Y
;---------------------------------------------------------------------------------------
_cr_set_line_col:
        lda circ_grad
        beq +
        lda line_y0
        jsr grad_get_color
        sta line_col
        rts
+       lda circ_col
        sta line_col
        rts

;---------------------------------------------------------------------------------------
; Circle working variables
;---------------------------------------------------------------------------------------
_cr_fill:   .byte 0
_cr_x:      .byte 0
_cr_y:      .byte 0
_cr_d:      .word 0
_cr_tmp:    .word 0
_cr_xh:     .word 0
_cr_yh:     .word 0
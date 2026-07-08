;=======================================================================================
; draw_ellipse - Draw an ellipse (outline or filled)
; Input: elip_cx (16-bit), elip_cy (8-bit), elip_rx (8-bit), elip_ry (8-bit)
;        elip_col (8-bit)
;        elip_grad (8-bit): 0 = flat color, nonzero = use gradient lookup
;        Carry: clear=outline, set=filled
; Automatically doubles x offsets in 80-col mode for correct aspect ratio
; Outline: 128 parametric line segments via sine table
; Filled:  scanline fill using integer square root
;=======================================================================================
elip_cx:    .word 0
elip_cy:    .byte 0
elip_rx:    .byte 0
elip_ry:    .byte 0
elip_col:   .byte 0
elip_grad:  .byte 0             ; 0=flat, nonzero=gradient

draw_ellipse:
        ; Save fill flag from carry FIRST
        lda #0
        rol
        sta _el_fill

        lda _el_fill
        bne _el_do_fill
        jsr _el_draw_outline
        rts

_el_do_fill:
        lda elip_ry
        beq _el_exit
        jsr _el_draw_filled
_el_exit:
        rts


;---------------------------------------------------------------------------------------
; _el_draw_outline - 128 parametric line segments (unchanged)
;---------------------------------------------------------------------------------------
_el_draw_outline:
        lda elip_col
        sta line_col

        ; Compute first point at angle 0
        lda #0
        sta _el_angle
        jsr _el_compute_point

        lda _el_px
        sta _el_first_x
        lda _el_px+1
        sta _el_first_x+1
        lda _el_py
        sta _el_first_y

        lda _el_px
        sta _el_prev_x
        lda _el_px+1
        sta _el_prev_x+1
        lda _el_py
        sta _el_prev_y

        lda #2
        sta _el_angle

_el_ol_loop:
        jsr _el_compute_point

        lda _el_prev_x
        sta line_x0
        lda _el_prev_x+1
        sta line_x0+1
        lda _el_prev_y
        sta line_y0
        lda _el_px
        sta line_x1
        lda _el_px+1
        sta line_x1+1
        lda _el_py
        sta line_y1
        jsr draw_line

        lda _el_px
        sta _el_prev_x
        lda _el_px+1
        sta _el_prev_x+1
        lda _el_py
        sta _el_prev_y

        clc
        lda _el_angle
        adc #2
        sta _el_angle
        bne _el_ol_loop

        ; Close loop
        lda _el_prev_x
        sta line_x0
        lda _el_prev_x+1
        sta line_x0+1
        lda _el_prev_y
        sta line_y0
        lda _el_first_x
        sta line_x1
        lda _el_first_x+1
        sta line_x1+1
        lda _el_first_y
        sta line_y1
        jsr draw_line
        rts


;---------------------------------------------------------------------------------------
; _el_compute_point (unchanged)
;---------------------------------------------------------------------------------------
_el_compute_point:
        clc
        lda _el_angle
        adc #64
        jsr _el_get_sin

        ldx elip_rx
        jsr _el_mul8x8_hw

        lda _el_mul_result+1
        sta _el_offset
        lda #0
        sta _el_offset+1

        lda screen_mode
        cmp #80
        bne +
        asl _el_offset
        rol _el_offset+1
+
        lda _el_sin_neg
        bne _el_cp_x_sub

        clc
        lda elip_cx
        adc _el_offset
        sta _el_px
        lda elip_cx+1
        adc _el_offset+1
        sta _el_px+1
        jmp _el_cp_do_y

_el_cp_x_sub:
        sec
        lda elip_cx
        sbc _el_offset
        sta _el_px
        lda elip_cx+1
        sbc _el_offset+1
        sta _el_px+1
        bpl _el_cp_do_y
        lda #0
        sta _el_px
        sta _el_px+1

_el_cp_do_y:
        lda _el_angle
        jsr _el_get_sin

        ldx elip_ry
        jsr _el_mul8x8_hw

        lda _el_sin_neg
        bne _el_cp_y_sub

        clc
        lda elip_cy
        adc _el_mul_result+1
        bcs _el_cp_y_clamp_hi
        cmp #200
        bcc _el_cp_y_store
_el_cp_y_clamp_hi:
        lda #199
        jmp _el_cp_y_store

_el_cp_y_sub:
        sec
        lda elip_cy
        sbc _el_mul_result+1
        bcs _el_cp_y_store
        lda #0

_el_cp_y_store:
        sta _el_py
        rts


;---------------------------------------------------------------------------------------
; _el_draw_filled - Scanline fill with gradient support
;---------------------------------------------------------------------------------------
_el_draw_filled:
        ; Precompute ry^2
        lda elip_ry
        ldx elip_ry
        jsr _el_mul8x8_hw
        lda _el_mul_result
        sta _el_ry2
        lda _el_mul_result+1
        sta _el_ry2+1

        lda #0
        sta _el_dy

_el_fill_loop:
        ; Compute dy^2
        lda _el_dy
        ldx _el_dy
        jsr _el_mul8x8_hw

        ; remainder = ry^2 - dy^2
        sec
        lda _el_ry2
        sbc _el_mul_result
        sta _el_sqrt_in
        lda _el_ry2+1
        sbc _el_mul_result+1
        sta _el_sqrt_in+1

        jsr _el_isqrt

        ldx elip_rx
        jsr _el_mul8x8_hw

        lda _el_mul_result
        sta _el_div_num
        lda _el_mul_result+1
        sta _el_div_num+1
        lda elip_ry
        sta _el_divisor
        jsr _el_div16x8

        ; Apply 80-col aspect ratio doubling
        lda screen_mode
        cmp #80
        bne +
        asl _el_div_num
        rol _el_div_num+1
+
        lda _el_div_num
        sta _el_half_w
        lda _el_div_num+1
        sta _el_half_w+1

        ; Precompute x0 = cx - half_w
        sec
        lda elip_cx
        sbc _el_half_w
        sta _el_x0
        lda elip_cx+1
        sbc _el_half_w+1
        sta _el_x0+1
        bpl +
        lda #0
        sta _el_x0
        sta _el_x0+1
+
        ; Precompute x1 = cx + half_w
        clc
        lda elip_cx
        adc _el_half_w
        sta _el_x1
        lda elip_cx+1
        adc _el_half_w+1
        sta _el_x1+1

        ; --- Top half: hline at cy - dy ---
        sec
        lda elip_cy
        sbc _el_dy
        bcc _el_skip_top
        cmp #200
        bcs _el_skip_top
        sta line_y0
        sta line_y1
        jsr _el_set_line_col
        lda _el_x0
        sta line_x0
        lda _el_x0+1
        sta line_x0+1
        lda _el_x1
        sta line_x1
        lda _el_x1+1
        sta line_x1+1
        jsr fill_hline

_el_skip_top:
        ; --- Bottom half: hline at cy + dy (skip if dy=0) ---
        lda _el_dy
        beq _el_next_dy

        clc
        lda elip_cy
        adc _el_dy
        bcs _el_next_dy
        cmp #200
        bcs _el_next_dy
        sta line_y0
        sta line_y1
        jsr _el_set_line_col
        lda _el_x0
        sta line_x0
        lda _el_x0+1
        sta line_x0+1
        lda _el_x1
        sta line_x1
        lda _el_x1+1
        sta line_x1+1
        jsr fill_hline

_el_next_dy:
        inc _el_dy
        lda _el_dy
        cmp elip_ry
        bcc _el_fill_loop
        beq _el_fill_loop
        rts

;---------------------------------------------------------------------------------------
; _el_set_line_col - Set line_col from gradient or flat color
; Input: line_y0 already set
;---------------------------------------------------------------------------------------
_el_set_line_col:
        lda elip_grad
        beq +
        lda line_y0
        jsr grad_get_color
        sta line_col
        rts
+       lda elip_col
        sta line_col
        rts


;---------------------------------------------------------------------------------------
; _el_get_sin (unchanged)
;---------------------------------------------------------------------------------------
_el_get_sin:
        sta _el_sin_angle
        lda #0
        sta _el_sin_neg

        lda _el_sin_angle
        cmp #128
        bcc _el_sin_pos_half

        lda #$FF
        sta _el_sin_neg
        lda _el_sin_angle
        and #$7F
        sta _el_sin_angle

_el_sin_pos_half:
        lda _el_sin_angle
        cmp #64
        bcc _el_sin_q1

        lda #128
        sec
        sbc _el_sin_angle
        tax
        lda _el_sin_table,x
        rts

_el_sin_q1:
        tax
        lda _el_sin_table,x
        rts


;---------------------------------------------------------------------------------------
; _el_isqrt (unchanged)
;---------------------------------------------------------------------------------------
_el_isqrt:
        lda #0
        sta _el_sqrt_root
        sta _el_sqrt_rem
        sta _el_sqrt_rem+1
        ldx #8

_el_sq_loop:
        asl _el_sqrt_in
        rol _el_sqrt_in+1
        rol _el_sqrt_rem
        rol _el_sqrt_rem+1
        asl _el_sqrt_in
        rol _el_sqrt_in+1
        rol _el_sqrt_rem
        rol _el_sqrt_rem+1

        asl _el_sqrt_root

        lda _el_sqrt_root
        asl
        clc
        adc #1
        sta _el_sqrt_test
        lda #0
        adc #0
        sta _el_sqrt_test+1

        lda _el_sqrt_rem+1
        cmp _el_sqrt_test+1
        bcc _el_sq_skip
        bne _el_sq_sub
        lda _el_sqrt_rem
        cmp _el_sqrt_test
        bcc _el_sq_skip

_el_sq_sub:
        sec
        lda _el_sqrt_rem
        sbc _el_sqrt_test
        sta _el_sqrt_rem
        lda _el_sqrt_rem+1
        sbc _el_sqrt_test+1
        sta _el_sqrt_rem+1
        inc _el_sqrt_root

_el_sq_skip:
        dex
        bne _el_sq_loop

        ; Round to nearest
        lda _el_sqrt_rem+1
        bne _el_sq_round
        lda _el_sqrt_rem
        cmp _el_sqrt_root
        bcc _el_sq_done
        beq _el_sq_done

_el_sq_round:
        inc _el_sqrt_root

_el_sq_done:
        lda _el_sqrt_root
        rts


;---------------------------------------------------------------------------------------
; _el_mul8x8 (unchanged)
;---------------------------------------------------------------------------------------
_el_mul8x8:
        sta _el_mul_a
        stx _el_mul_b
        lda #0
        sta _el_mul_result
        sta _el_mul_result+1
        ldx #8
-       lsr _el_mul_b
        bcc +
        clc
        lda _el_mul_result+1
        adc _el_mul_a
        sta _el_mul_result+1
+       ror _el_mul_result+1
        ror _el_mul_result
        dex
        bne -
        rts

;---- hardware accelerated
_el_mul8x8_hw:
        ; Input: A = multiplicand, X = multiplier
        sta MULTINA
        lda #0
        sta MULTINA+1
        sta MULTINA+2
        sta MULTINA+3
        
        stx MULTINB
        lda #0
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3
        
        ; No wait needed - multiplier is instant!
        ; (MULBUSY never sets according to docs)
        
        lda MULTOUT               ; Result low byte
        sta _el_mul_result
        lda MULTOUT+1               ; Result high byte
        sta _el_mul_result+1
        rts

;---------------------------------------------------------------------------------------
; _el_div16x8 (unchanged)
;---------------------------------------------------------------------------------------
_el_div16x8:
        lda #0
        sta _el_div_rem
        ldx #16
-       asl _el_div_num
        rol _el_div_num+1
        rol _el_div_rem
        lda _el_div_rem
        cmp _el_divisor
        bcc +
        sbc _el_divisor
        sta _el_div_rem
        inc _el_div_num
+       dex
        bne -
        rts

;---------------------------------------------------------------------------------------
; Sine table (unchanged)
;---------------------------------------------------------------------------------------
_el_sin_table:
        .byte   0,   6,  13,  19,  25,  31,  37,  44
        .byte  50,  56,  62,  68,  74,  80,  86,  92
        .byte  98, 103, 109, 115, 120, 126, 131, 136
        .byte 142, 147, 152, 157, 162, 167, 171, 176
        .byte 180, 185, 189, 193, 197, 201, 205, 208
        .byte 212, 215, 219, 222, 225, 228, 231, 233
        .byte 236, 238, 240, 242, 244, 246, 247, 249
        .byte 250, 251, 252, 253, 254, 254, 255, 255
        .byte 255

;---------------------------------------------------------------------------------------
; Working variables
;---------------------------------------------------------------------------------------
_el_fill:       .byte 0
_el_angle:      .byte 0
_el_sin_angle:  .byte 0
_el_sin_neg:    .byte 0
_el_offset:     .word 0
_el_px:         .word 0
_el_py:         .byte 0
_el_prev_x:     .word 0
_el_prev_y:     .byte 0
_el_first_x:    .word 0
_el_first_y:    .byte 0
_el_dy:         .byte 0
_el_ry2:        .word 0
_el_half_w:     .word 0
_el_x0:         .word 0
_el_x1:         .word 0
_el_mul_a:      .byte 0
_el_mul_b:      .byte 0
_el_mul_result: .word 0
_el_div_num:    .word 0
_el_div_rem:    .byte 0
_el_divisor:    .byte 0
_el_sqrt_in:    .word 0
_el_sqrt_root:  .byte 0
_el_sqrt_rem:   .word 0
_el_sqrt_test:  .word 0
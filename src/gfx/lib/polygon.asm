;=======================================================================================
; draw_polygon - Draw a regular polygon (outline or filled)
; Input: poly_cx (16-bit), poly_cy (8-bit), poly_r (8-bit), poly_col (8-bit)
;        poly_sides (8-bit, must be 3-32)
;        poly_grad (8-bit): 0 = flat color, nonzero = use gradient lookup
;        Carry: clear=outline, set=filled
; Automatically doubles x offsets in 80-col mode for correct aspect ratio
; First vertex points up (12 o'clock position)
;=======================================================================================
poly_cx:    .word 0
poly_cy:    .byte 0
poly_r:     .byte 0
poly_col:   .byte 0
poly_sides: .byte 0
poly_grad:  .byte 0             ; 0=flat, nonzero=gradient
poly_angle: .byte 0   ; 0-255, where 0=up, 64=right, 128=down, 192=left

draw_polygon:
        ; Save fill flag from carry FIRST
        lda #0
        rol
        sta _pg_fill

        ; Validate sides (3-32)
        lda poly_sides
        cmp #3
        bcc _pg_exit
        cmp #33
        bcs _pg_exit

        jsr _pg_calc_vertices

        lda _pg_fill
        bne +
        jsr _pg_draw_outline
        rts
+       jsr _pg_draw_filled
_pg_exit:
        rts


;---------------------------------------------------------------------------------------
; _pg_calc_vertices (unchanged)
;---------------------------------------------------------------------------------------
_pg_calc_vertices:
        lda #0
        sta _pg_cur_vertex

_pg_vert_loop:
        lda _pg_cur_vertex
        sta _pg_div_num+1
        lda #0
        sta _pg_div_num
        lda poly_sides
        sta _pg_divisor
        jsr _pg_div16x8
        lda _pg_div_num
        sec
        sbc poly_angle
        sta _pg_cur_angle

        ; X offset: r * cos(angle)
        clc
        lda _pg_cur_angle
        adc #64
        jsr _pg_get_sin

        ldx poly_r
        jsr _pg_mul8x8_hw

        lda _pg_mul_result+1
        sta _pg_offset
        lda #0
        sta _pg_offset+1

        lda screen_mode
        cmp #80
        bne +
        asl _pg_offset
        rol _pg_offset+1
+
        lda _pg_sin_neg
        bne _pg_vx_sub

        clc
        lda poly_cx
        adc _pg_offset
        sta _pg_tmp_vx
        lda poly_cx+1
        adc _pg_offset+1
        sta _pg_tmp_vx+1
        jmp _pg_do_vy

_pg_vx_sub:
        sec
        lda poly_cx
        sbc _pg_offset
        sta _pg_tmp_vx
        lda poly_cx+1
        sbc _pg_offset+1
        sta _pg_tmp_vx+1
        bpl _pg_do_vy
        lda #0
        sta _pg_tmp_vx
        sta _pg_tmp_vx+1

_pg_do_vy:
        lda _pg_cur_angle
        jsr _pg_get_sin

        ldx poly_r
        jsr _pg_mul8x8_hw

        lda _pg_sin_neg
        bne _pg_vy_sub

        clc
        lda poly_cy
        adc _pg_mul_result+1
        bcs _pg_vy_clamp_hi
        cmp #200
        bcc _pg_store_vert
_pg_vy_clamp_hi:
        lda #199
        jmp _pg_store_vert

_pg_vy_sub:
        sec
        lda poly_cy
        sbc _pg_mul_result+1
        bcs _pg_store_vert
        lda #0

_pg_store_vert:
        ldx _pg_cur_vertex
        sta _pg_vy,x
        txa
        asl
        tax
        lda _pg_tmp_vx
        sta _pg_vx,x
        lda _pg_tmp_vx+1
        sta _pg_vx+1,x

        inc _pg_cur_vertex
        lda _pg_cur_vertex
        cmp poly_sides
        bne _pg_vert_loop
        rts


;---------------------------------------------------------------------------------------
; _pg_get_sin (unchanged)
;---------------------------------------------------------------------------------------
_pg_get_sin:
        sta _pg_sin_angle
        lda #0
        sta _pg_sin_neg

        lda _pg_sin_angle
        cmp #128
        bcc _pg_sin_pos_half

        lda #$FF
        sta _pg_sin_neg
        lda _pg_sin_angle
        and #$7F
        sta _pg_sin_angle

_pg_sin_pos_half:
        lda _pg_sin_angle
        cmp #64
        bcc _pg_sin_q1

        lda #128
        sec
        sbc _pg_sin_angle
        tax
        lda _pg_sin_table,x
        rts

_pg_sin_q1:
        tax
        lda _pg_sin_table,x
        rts


;---------------------------------------------------------------------------------------
; _pg_draw_outline (unchanged)
;---------------------------------------------------------------------------------------
_pg_draw_outline:
        lda poly_col
        sta line_col

        lda #0
        sta _pg_edge_idx

_pg_ol_loop:
        ldx _pg_edge_idx
        lda _pg_vy,x
        sta line_y0
        txa
        asl
        tax
        lda _pg_vx,x
        sta line_x0
        lda _pg_vx+1,x
        sta line_x0+1

        ldx _pg_edge_idx
        inx
        cpx poly_sides
        bne +
        ldx #0
+       lda _pg_vy,x
        sta line_y1
        txa
        asl
        tax
        lda _pg_vx,x
        sta line_x1
        lda _pg_vx+1,x
        sta line_x1+1

        jsr draw_line

        inc _pg_edge_idx
        lda _pg_edge_idx
        cmp poly_sides
        bne _pg_ol_loop
        rts


;---------------------------------------------------------------------------------------
; _pg_draw_filled - Scanline fill with gradient support
;---------------------------------------------------------------------------------------
_pg_draw_filled:
        ; Find min_y and max_y
        lda #199
        sta _pg_min_y
        lda #0
        sta _pg_max_y
        ldx #0

_pg_find_yrange:
        lda _pg_vy,x
        cmp _pg_min_y
        bcs +
        sta _pg_min_y
+       cmp _pg_max_y
        bcc +
        beq +
        sta _pg_max_y
+       inx
        cpx poly_sides
        bne _pg_find_yrange

        lda _pg_max_y
        cmp #200
        bcc +
        lda #199
        sta _pg_max_y
+
        lda _pg_min_y
        sta _pg_scan_y

_pg_scan_loop:
        lda #$FF
        sta _pg_min_sx
        sta _pg_min_sx+1
        lda #0
        sta _pg_max_sx
        sta _pg_max_sx+1

        lda #0
        sta _pg_edge_idx

_pg_edge_test:
        ldx _pg_edge_idx
        lda _pg_vy,x
        sta _pg_vy0
        txa
        asl
        tax
        lda _pg_vx,x
        sta _pg_vx0
        lda _pg_vx+1,x
        sta _pg_vx0+1

        ldx _pg_edge_idx
        inx
        cpx poly_sides
        bne +
        ldx #0
+       lda _pg_vy,x
        sta _pg_vy1
        txa
        asl
        tax
        lda _pg_vx,x
        sta _pg_vx1
        lda _pg_vx+1,x
        sta _pg_vx1+1

        lda _pg_vy0
        cmp _pg_vy1
        bcc _pg_edge_oriented
        beq _pg_edge_next

        ; Swap
        lda _pg_vx0
        ldy _pg_vx1
        sty _pg_vx0
        sta _pg_vx1
        lda _pg_vx0+1
        ldy _pg_vx1+1
        sty _pg_vx0+1
        sta _pg_vx1+1
        lda _pg_vy0
        ldy _pg_vy1
        sty _pg_vy0
        sta _pg_vy1

_pg_edge_oriented:
        lda _pg_scan_y
        cmp _pg_vy0
        bcc _pg_edge_next
        lda _pg_vy1
        cmp _pg_scan_y
        bcc _pg_edge_next

        jsr _pg_calc_intersect

        lda _pg_ix+1
        bpl _pg_ix_nonneg
        lda #0
        sta _pg_ix
        sta _pg_ix+1
_pg_ix_nonneg:

        lda _pg_ix+1
        cmp _pg_min_sx+1
        bcc _pg_do_update_min
        bne _pg_check_max
        lda _pg_ix
        cmp _pg_min_sx
        bcs _pg_check_max

_pg_do_update_min:
        lda _pg_ix
        sta _pg_min_sx
        lda _pg_ix+1
        sta _pg_min_sx+1

_pg_check_max:
        lda _pg_ix+1
        cmp _pg_max_sx+1
        bcc _pg_edge_next
        bne _pg_do_update_max
        lda _pg_ix
        cmp _pg_max_sx
        bcc _pg_edge_next
        beq _pg_edge_next

_pg_do_update_max:
        lda _pg_ix
        sta _pg_max_sx
        lda _pg_ix+1
        sta _pg_max_sx+1

_pg_edge_next:
        inc _pg_edge_idx
        lda _pg_edge_idx
        cmp poly_sides
        bne _pg_edge_test

        ; Draw hline if valid
        lda _pg_min_sx+1
        cmp _pg_max_sx+1
        bcc _pg_do_hline
        bne _pg_scan_next
        lda _pg_min_sx
        cmp _pg_max_sx
        beq _pg_do_hline
        bcs _pg_scan_next

_pg_do_hline:
        ; --- Gradient-aware color selection ---
        lda poly_grad
        beq _pg_flat_col
        lda _pg_scan_y
        jsr grad_get_color
        sta line_col
        jmp _pg_do_draw
_pg_flat_col:
        lda poly_col
        sta line_col
_pg_do_draw:
        lda _pg_min_sx
        sta line_x0
        lda _pg_min_sx+1
        sta line_x0+1
        lda _pg_max_sx
        sta line_x1
        lda _pg_max_sx+1
        sta line_x1+1
        lda _pg_scan_y
        sta line_y0
        sta line_y1
        jsr fill_hline

_pg_scan_next:
        lda _pg_scan_y
        cmp _pg_max_y
        bcs _pg_fill_done
        inc _pg_scan_y
        jmp _pg_scan_loop

_pg_fill_done:
        rts


;---------------------------------------------------------------------------------------
; _pg_calc_intersect (unchanged)
;---------------------------------------------------------------------------------------
_pg_calc_intersect:
        sec
        lda _pg_scan_y
        sbc _pg_vy0
        sta _pg_t
        beq _pg_ix_v0

        sec
        lda _pg_vy1
        sbc _pg_vy0
        sta _pg_dy
        cmp _pg_t
        beq _pg_ix_v1

        lda _pg_t
        sta _pg_div_num+1
        lda #0
        sta _pg_div_num
        lda _pg_dy
        sta _pg_divisor
        jsr _pg_div16x8
        lda _pg_div_num
        sta _pg_frac

        sec
        lda _pg_vx1
        sbc _pg_vx0
        sta _pg_dx
        lda _pg_vx1+1
        sbc _pg_vx0+1
        sta _pg_dx+1

        lda #0
        sta _pg_dx_neg
        lda _pg_dx+1
        bpl _pg_dx_pos

        lda #$FF
        sta _pg_dx_neg
        sec
        lda #0
        sbc _pg_dx
        sta _pg_dx
        lda #0
        sbc _pg_dx+1
        sta _pg_dx+1

_pg_dx_pos:
        lda _pg_dx
        ldx _pg_frac
        jsr _pg_mul8x8_hw
        lda _pg_mul_result+1
        sta _pg_offset

        lda _pg_dx+1
        ldx _pg_frac
        jsr _pg_mul8x8_hw

        clc
        lda _pg_offset
        adc _pg_mul_result
        sta _pg_offset
        lda _pg_mul_result+1
        adc #0
        sta _pg_offset+1

        lda _pg_dx_neg
        bne _pg_ix_sub

        clc
        lda _pg_vx0
        adc _pg_offset
        sta _pg_ix
        lda _pg_vx0+1
        adc _pg_offset+1
        sta _pg_ix+1
        rts

_pg_ix_sub:
        sec
        lda _pg_vx0
        sbc _pg_offset
        sta _pg_ix
        lda _pg_vx0+1
        sbc _pg_offset+1
        sta _pg_ix+1
        rts

_pg_ix_v0:
        lda _pg_vx0
        sta _pg_ix
        lda _pg_vx0+1
        sta _pg_ix+1
        rts

_pg_ix_v1:
        lda _pg_vx1
        sta _pg_ix
        lda _pg_vx1+1
        sta _pg_ix+1
        rts


;---------------------------------------------------------------------------------------
; _pg_mul8x8 (unchanged)
;---------------------------------------------------------------------------------------
_pg_mul8x8:
        sta _pg_mul_a
        stx _pg_mul_b
        lda #0
        sta _pg_mul_result
        sta _pg_mul_result+1
        ldx #8
-       lsr _pg_mul_b
        bcc +
        clc
        lda _pg_mul_result+1
        adc _pg_mul_a
        sta _pg_mul_result+1
+       ror _pg_mul_result+1
        ror _pg_mul_result
        dex
        bne -
        rts

; --- hardware accelerated
_pg_mul8x8_hw:
        ; Input: A = multiplicand, X = multiplier
        sta $D770
        lda #0
        sta $D771
        sta $D772
        sta $D773
        
        stx $D774
        lda #0
        sta $D775
        sta $D776
        sta $D777
        
        ; No wait needed - multiplier is instant!
        ; (MULBUSY never sets according to docs)
        
        lda $D778               ; Result low byte
        sta _pg_mul_result
        lda $D779               ; Result high byte
        sta _pg_mul_result+1
        rts
;---------------------------------------------------------------------------------------
; _pg_div16x8 (unchanged)
;---------------------------------------------------------------------------------------
_pg_div16x8:
        lda #0
        sta _pg_div_rem
        ldx #16
-       asl _pg_div_num
        rol _pg_div_num+1
        rol _pg_div_rem
        lda _pg_div_rem
        cmp _pg_divisor
        bcc +
        sbc _pg_divisor
        sta _pg_div_rem
        inc _pg_div_num
+       dex
        bne -
        rts


;---------------------------------------------------------------------------------------
; Sine table
;---------------------------------------------------------------------------------------
_pg_sin_table:
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
_pg_fill:       .byte 0
_pg_cur_angle:  .byte 0
_pg_cur_vertex: .byte 0
_pg_sin_angle:  .byte 0
_pg_sin_neg:    .byte 0
_pg_offset:     .word 0
_pg_tmp_vx:     .word 0
_pg_edge_idx:   .byte 0
_pg_scan_y:     .byte 0
_pg_min_y:      .byte 0
_pg_max_y:      .byte 0
_pg_min_sx:     .word 0
_pg_max_sx:     .word 0
_pg_vx0:        .word 0
_pg_vy0:        .byte 0
_pg_vx1:        .word 0
_pg_vy1:        .byte 0
_pg_ix:         .word 0
_pg_t:          .byte 0
_pg_dy:         .byte 0
_pg_dx:         .word 0
_pg_dx_neg:     .byte 0
_pg_frac:       .byte 0
_pg_mul_a:      .byte 0
_pg_mul_b:      .byte 0
_pg_mul_result: .word 0
_pg_div_num:    .word 0
_pg_div_rem:    .byte 0
_pg_divisor:    .byte 0

; Vertex buffers (max 32 vertices)
_pg_vx:
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
_pg_vy:
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
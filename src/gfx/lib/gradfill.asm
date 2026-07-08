;=======================================================================================
; gradfill.asm - Angular gradient fill system for MEGA65 FCM bitmap mode
;
; Provides a gradient fill that works at any angle (0-255 representing 0-360 degrees).
; Each pixel's color is determined by projecting its (dx,dy) from a center point
; onto the gradient axis defined by the angle.
;
; Angle convention (matches polygon/ellipse sine table, 256 steps = 360 degrees):
;   0 = up (12 o'clock)     -> gradient runs top to bottom
;  64 = right (3 o'clock)   -> gradient runs left to right
; 128 = down (6 o'clock)    -> gradient runs bottom to top
; 192 = left (9 o'clock)    -> gradient runs right to left
;  32 = upper-right          -> diagonal TL to BR
; 224 = lower-left           -> diagonal TR to BL
;
; Usage:
;   1. Set grad_r1/g1/b1, grad_r2/g2/b2, grad_pal (same as existing gradient system)
;   2. Set gf_cx/gf_cy (shape center), gf_radius (max extent), gf_angle
;   3. Call gf_setup (builds palette and precomputes trig constants)
;   4. Draw shapes normally with SEC (filled) - the fill_hline dispatcher
;      automatically routes through gf_fill_hline for per-pixel gradient
;   5. Set gf_mode = 0 when done to restore normal fill behavior
;
; Integration:
;   Replace every `jsr draw_line` in shape fill loops with `jsr fill_hline`.
;   fill_hline checks gf_mode: if 0, calls draw_line; if nonzero, calls gf_fill_hline.
;   This is a drop-in replacement that preserves all existing behavior when gf_mode=0.
;=======================================================================================

;=======================================================================================
; gradfill - Parent scope: all _gf_ local labels live under this
;=======================================================================================
gradfill:

;---------------------------------------------------------------------------------------
; Parameters (global equates below for external access)
;---------------------------------------------------------------------------------------
_gf_cx:      .word 0         ; shape center X (16-bit)
_gf_cy:      .byte 0         ; shape center Y (8-bit)
_gf_radius:  .byte 0         ; max extent from center (for normalization)
_gf_angle:   .byte 0         ; gradient angle (0-255)
_gf_mode:    .byte 0         ; 0=disabled (use draw_line), 1=angular gradient active

;---------------------------------------------------------------------------------------
; Precomputed constants (set by _gf_do_setup)
;---------------------------------------------------------------------------------------
_gf_cos:     .byte 0        ; |cos(angle)| (0-255 from sine table)
_gf_sin:     .byte 0        ; |sin(angle)| (0-255 from sine table)
_gf_cos_neg: .byte 0        ; $FF if cos is negative, $00 if positive
_gf_sin_neg: .byte 0        ; $FF if sin is negative, $00 if positive


;=======================================================================================
; _gf_dispatch (fill_hline) - Dispatcher: routes to draw_line or gradient fill
;
; Input: line_x0 (16-bit), line_x1 (16-bit), line_y0 (8-bit), line_y1 (8-bit)
;        line_col (8-bit) - used by draw_line if gf_mode=0
;
; When gf_mode=0: calls draw_line (original behavior, line_col used as-is)
; When gf_mode=1: calls _gf_fill_hline (per-pixel angular gradient)
;=======================================================================================
_gf_dispatch:
        lda _gf_mode
        bne _gf_go_grad
        jmp draw_line           ; tail call to normal line drawing
_gf_go_grad:
        jmp _gf_fill_hline     ; tail call to gradient fill


;=======================================================================================
; _gf_do_setup (gf_setup) - Precompute gradient projection constants and build palette
;
; Must set: gf_cx, gf_cy, gf_radius, gf_angle
;           grad_r1/g1/b1, grad_r2/g2/b2, grad_pal
; Destroys: A, X, Y, Z
;=======================================================================================
_gf_do_setup:
        lda #1
        sta _gf_mode

        ; --- Compute cos(angle) = sin(angle + 64) ---
        clc
        lda _gf_angle
        adc #64
        jsr _gf_get_sin
        sta _gf_cos
        lda _gf_sin_tmp
        sta _gf_cos_neg

        ; --- Compute sin(angle) ---
        lda _gf_angle
        jsr _gf_get_sin
        sta _gf_sin
        lda _gf_sin_tmp
        sta _gf_sin_neg

        ; --- Build palette ramp ---
        ; Span covers [0 .. 2*radius], used as indices into gb_y_table
        lda #0
        sta grad_y_top
        lda _gf_radius
        asl                     ; diameter = 2 * radius
        bcc +
        lda #199                ; overflow clamp
+       cmp #200
        bcc +
        lda #199
+       sta grad_y_bot
        jsr grad_build_palette

        rts


;=======================================================================================
; _gf_fill_hline - Draw a horizontal span with per-pixel angular gradient color
;
; Input: line_x0 (16-bit), line_x1 (16-bit), line_y0 (8-bit)
;        gf_* params must be set via gf_setup
;
; Algorithm:
;   For the first pixel, compute full projection:
;     proj = dx*cos(angle) + dy*sin(angle)
;   Then step by cos(angle) per pixel (since dy is constant across hline).
;   Map proj from [-radius..+radius] to [0..2*radius] as palette table index.
;=======================================================================================
_gf_fill_hline:
        ; --- Compute dy = line_y0 - gf_cy (signed) ---
        sec
        lda line_y0
        sbc _gf_cy
        sta _gf_dy

        ; --- Compute dy_proj = |dy| * |sin| ---
        lda _gf_dy
        bpl _gf_dy_pos
        eor #$FF
        clc
        adc #1
_gf_dy_pos:
        ; A = |dy|
        ldx _gf_sin
        jsr _gf_mul8x8_hw          ; _gf_mul_res = |dy| * |sin| (16-bit)

        ; Sign of product: negative if dy sign differs from sin sign
        lda _gf_dy
        eor _gf_sin_neg
        sta _gf_dyp_neg         ; bit 7 = sign
        lda _gf_mul_res+1
        sta _gf_dyp_int         ; integer part of |dy*sin/256|
        lda _gf_mul_res
        sta _gf_dyp_frac

        ; --- Compute dx = line_x0 - gf_cx (signed 16-bit) ---
        sec
        lda line_x0
        sbc _gf_cx
        sta _gf_dx
        lda line_x0+1
        sbc _gf_cx+1
        sta _gf_dx+1

        ; Get |dx| and sign
        lda _gf_dx+1
        bpl _gf_dx_ispos
        ; Negate
        sec
        lda #0
        sbc _gf_dx
        sta _gf_absdx
        lda #0
        sbc _gf_dx+1
        sta _gf_absdx+1
        lda #$FF
        sta _gf_dx_sign
        jmp _gf_dx_ready
_gf_dx_ispos:
        lda _gf_dx
        sta _gf_absdx
        lda _gf_dx+1
        sta _gf_absdx+1
        lda #$00
        sta _gf_dx_sign
_gf_dx_ready:

        ; Clamp |dx| to 8 bits for multiply
        lda _gf_absdx+1
        beq _gf_dx_ok
        lda #255
        sta _gf_absdx
_gf_dx_ok:

        ; dx_proj = |dx| * |cos|
        lda _gf_absdx
        ldx _gf_cos
        jsr _gf_mul8x8_hw

        ; Sign of dx*cos
        lda _gf_dx_sign
        eor _gf_cos_neg
        sta _gf_dxp_neg
        lda _gf_mul_res+1
        sta _gf_dxp_int
        lda _gf_mul_res
        sta _gf_dxp_frac

        ; --- Combine: proj_acc = dx_proj + dy_proj (signed 8.8) ---
        ; Convert dx_proj to signed and store as initial accumulator
        lda _gf_dxp_neg
        bmi _gf_dxn
        ; Positive dx_proj
        lda _gf_dxp_frac
        sta _gf_proj_acc
        lda _gf_dxp_int
        sta _gf_proj_acc+1
        jmp _gf_add_dy
_gf_dxn:
        ; Negative dx_proj
        sec
        lda #0
        sbc _gf_dxp_frac
        sta _gf_proj_acc
        lda #0
        sbc _gf_dxp_int
        sta _gf_proj_acc+1

_gf_add_dy:
        ; Add dy_proj (signed)
        lda _gf_dyp_neg
        bmi _gf_dyn
        ; Positive dy_proj: add
        clc
        lda _gf_proj_acc
        adc _gf_dyp_frac
        sta _gf_proj_acc
        lda _gf_proj_acc+1
        adc _gf_dyp_int
        sta _gf_proj_acc+1
        jmp _gf_proj_ok
_gf_dyn:
        ; Negative dy_proj: subtract
        sec
        lda _gf_proj_acc
        sbc _gf_dyp_frac
        sta _gf_proj_acc
        lda _gf_proj_acc+1
        sbc _gf_dyp_int
        sta _gf_proj_acc+1

_gf_proj_ok:
        ; --- Compute per-pixel step = cos(angle) with sign ---
        ; cos is 0-255, representing the change in projection per pixel step in X
        ; As 8.8 fixed point: integer=0, fraction=cos_value
        lda _gf_cos_neg
        bmi _gf_step_neg
        lda _gf_cos
        sta _gf_step_lo
        lda #0
        sta _gf_step_hi
        jmp _gf_calc_span
_gf_step_neg:
        ; Negate: step = -(0.cos)
        sec
        lda #0
        sbc _gf_cos
        sta _gf_step_lo
        lda #$FF
        sta _gf_step_hi

_gf_calc_span:
        ; --- Compute span = line_x1 - line_x0 + 1 ---
        sec
        lda line_x1
        sbc line_x0
        sta _gf_span
        lda line_x1+1
        sbc line_x0+1
        sta _gf_span+1
        ; If negative, bail
        bmi _gf_hl_done
        ; +1 for inclusive
        inc _gf_span
        bne +
        inc _gf_span+1
+
        ; --- Set up current X ---
        lda line_x0
        sta _gf_cur_x
        lda line_x0+1
        sta _gf_cur_x+1

        ; Cache grad_y_bot for clamping
        lda grad_y_bot
        sta _gf_clamp_max

        ; --- Main pixel loop ---
_gf_pix_loop:
        ; Map signed projection to palette table index
        ; index = proj_int + radius, clamped to [0..2*radius]
        lda _gf_proj_acc+1      ; signed integer part
        clc
        adc _gf_radius          ; shift to unsigned [0..2*r]
        bmi _gf_clamp_lo        ; still negative after add -> clamp to 0
        cmp _gf_clamp_max
        bcc _gf_idx_ok
        beq _gf_idx_ok
        lda _gf_clamp_max       ; clamp high
        jmp _gf_idx_ok
_gf_clamp_lo:
        lda #0
_gf_idx_ok:
        ; Look up palette color
        tax
        lda gb_y_table,x
        sta plot_col

        ; Plot pixel
        lda _gf_cur_x
        sta plot_x
        lda _gf_cur_x+1
        sta plot_x+1
        lda line_y0
        sta plot_y
        jsr plot_pixel

        ; Advance projection by per-pixel step
        clc
        lda _gf_proj_acc
        adc _gf_step_lo
        sta _gf_proj_acc
        lda _gf_proj_acc+1
        adc _gf_step_hi
        sta _gf_proj_acc+1

        ; Advance X
        inc _gf_cur_x
        bne +
        inc _gf_cur_x+1
+
        ; Decrement span
        lda _gf_span
        bne +
        dec _gf_span+1
+       dec _gf_span
        lda _gf_span
        ora _gf_span+1
        bne _gf_pix_loop

_gf_hl_done:
        rts


;=======================================================================================
; _gf_get_sin - Get |sin(angle)| with sign tracking
; Input: A = angle (0-255)
; Output: A = |sin(angle)| (0-255), _gf_sin_tmp = $00 if positive, $FF if negative
;=======================================================================================
_gf_get_sin:
        sta _gf_s_angle
        lda #$00
        sta _gf_sin_tmp

        lda _gf_s_angle
        cmp #128
        bcc _gf_s_pos
        lda #$FF
        sta _gf_sin_tmp
        lda _gf_s_angle
        and #$7F
        sta _gf_s_angle

_gf_s_pos:
        lda _gf_s_angle
        cmp #64
        bcc _gf_s_q1
        lda #128
        sec
        sbc _gf_s_angle
        tax
        lda _gf_sin_tbl,x
        rts
_gf_s_q1:
        tax
        lda _gf_sin_tbl,x
        rts

_gf_s_angle: .byte 0
_gf_sin_tmp: .byte 0


;=======================================================================================
; _gf_mul8x8 - 8x8 unsigned multiply -> 16-bit result
; Input: A = multiplicand, X = multiplier
; Output: _gf_mul_res (16-bit, low byte = fractional, high byte = integer)
;=======================================================================================
_gf_mul8x8:
        sta _gf_mul_a
        stx _gf_mul_b
        lda #0
        sta _gf_mul_res
        sta _gf_mul_res+1
        ldx #8
-       lsr _gf_mul_b
        bcc +
        clc
        lda _gf_mul_res+1
        adc _gf_mul_a
        sta _gf_mul_res+1
+       ror _gf_mul_res+1
        ror _gf_mul_res
        dex
        bne -
        rts

;---- hardware accelerated
_gf_mul8x8_hw:
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
        sta _gf_mul_res
        lda MULTOUT+1               ; Result high byte
        sta _gf_mul_res+1
        rts

;=======================================================================================
; Sine table (identical to ellipse/polygon)
;=======================================================================================
_gf_sin_tbl:
        .byte   0,   6,  13,  19,  25,  31,  37,  44
        .byte  50,  56,  62,  68,  74,  80,  86,  92
        .byte  98, 103, 109, 115, 120, 126, 131, 136
        .byte 142, 147, 152, 157, 162, 167, 171, 176
        .byte 180, 185, 189, 193, 197, 201, 205, 208
        .byte 212, 215, 219, 222, 225, 228, 231, 233
        .byte 236, 238, 240, 242, 244, 246, 247, 249
        .byte 250, 251, 252, 253, 254, 254, 255, 255
        .byte 255


;=======================================================================================
; Working variables
;=======================================================================================
_gf_dy:          .byte 0
_gf_dx:          .word 0
_gf_absdx:       .word 0
_gf_dx_sign:     .byte 0
_gf_dxp_int:     .byte 0
_gf_dxp_frac:    .byte 0
_gf_dxp_neg:     .byte 0
_gf_dyp_int:     .byte 0
_gf_dyp_frac:    .byte 0
_gf_dyp_neg:     .byte 0
_gf_proj_acc:    .word 0     ; 8.8 signed projection accumulator
_gf_step_lo:     .byte 0     ; per-pixel step (8.8 fractional part)
_gf_step_hi:     .byte 0     ; per-pixel step (8.8 integer part)
_gf_span:        .word 0     ; pixels remaining
_gf_cur_x:       .word 0     ; current X
_gf_clamp_max:   .byte 0     ; cached grad_y_bot
_gf_mul_a:       .byte 0
_gf_mul_b:       .byte 0
_gf_mul_res:     .word 0


;=======================================================================================
; Global equates - public API names pointing into the local scope
;=======================================================================================
gf_cx      = _gf_cx
gf_cy      = _gf_cy
gf_radius  = _gf_radius
gf_angle   = _gf_angle
gf_mode    = _gf_mode
fill_hline = _gf_dispatch
gf_setup   = _gf_do_setup
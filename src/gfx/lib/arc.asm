;=======================================================================================
; arc.asm - [basic65c] elliptic arcs for CIRCLE/ELLIPSE per the BASIC65 book
;
; ELLIPSE xc,yc,xr,yr[,flags,start,stop] -- start/stop in degrees,
; 0 at 3 o'clock moving clockwise; flags bit0 fill (pie), bit1
; suppress legs, bit2 zero-radian at 12 o'clock (combs). Full
; ellipses (both angles 0) keep the fast midpoint path elsewhere.
;
; Rendering is parametric: chords between successive sine-table
; points (256 steps/circle = 1.4 degrees; sagitta well under a pixel
; at these radii). Legs are centre->endpoint lines; a filled arc is a
; fan of centre->rim lines at half-index density plus the rim chords.
; Uses the polygon module's quadrant sine and hardware multiply.
;=======================================================================================

arc_cx:     .word 0
arc_cy:     .byte 0
arc_xr:     .byte 0
arc_yr:     .byte 0
arc_col:    .byte 0
arc_flags:  .byte 0
arc_start:  .word 0             ; degrees 0-360
arc_stop:   .word 0

arc_u:      .byte 0             ; current table index
arc_u0:     .byte 0
arc_sweep:  .byte 0             ; index count (0 = degenerate point)
arc_px:     .word 0             ; last computed point
arc_py:     .word 0
arc_qx:     .word 0             ; previous point (chord start)
arc_qy:     .byte 0
arc_lx:     .word 0             ; first point (for legs)
arc_ly:     .byte 0
arc_t:      .byte 0

; degrees (16-bit in A/X = lo/hi) -> table index (deg * 182 / 256)
arc_d2i:
        sta MULTINA
        stx MULTINA+1
        lda #0
        sta MULTINA+2
        sta MULTINA+3
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3
        lda #182
        sta MULTINB
        lda MULTOUT+1
        rts

; A = table index -> arc_px/arc_py (16-bit, y clamped 0-199 like the
; polygon module does; x is left signed for the plot clip)
arcpoint:
        sta arc_u
        clc
        adc #64                 ; x = cx + xr*cos
        jsr pgsin
        ldx arc_xr
        jsr pgmul
        lda pgsinneg
        bne _apt_xsub
        clc
        lda arc_cx
        adc pgmulres+1
        sta arc_px
        lda arc_cx+1
        adc #0
        sta arc_px+1
        bra _apt_y
_apt_xsub:
        sec
        lda arc_cx
        sbc pgmulres+1
        sta arc_px
        lda arc_cx+1
        sbc #0
        sta arc_px+1
_apt_y:
        lda arc_u               ; y = cy + yr*sin
        jsr pgsin
        ldx arc_yr
        jsr pgmul
        lda pgsinneg
        bne _apt_ysub
        clc
        lda arc_cy
        adc pgmulres+1
        bcs _apt_yhi
        cmp #200
        bcc _apt_ystore
_apt_yhi:
        lda #199
        bra _apt_ystore
_apt_ysub:
        sec
        lda arc_cy
        sbc pgmulres+1
        bcs _apt_ystore
        lda #0
_apt_ystore:
        sta arc_py
        lda #0
        sta arc_py+1
        rts

; chord from the previous point (arc_qx/qy) to arc_px/py
arc_chord:
        lda arc_qx
        sta line_x0
        lda arc_qx+1
        sta line_x0+1
        lda arc_qy
        sta line_y0
        lda arc_px
        sta line_x1
        lda arc_px+1
        sta line_x1+1
        lda arc_py
        sta line_y1
        lda arc_col
        sta line_col
        jmp draw_line

; centre to arc_px/py (legs and fill fan)
arc_spoke:
        lda arc_cx
        sta line_x0
        lda arc_cx+1
        sta line_x0+1
        lda arc_cy
        sta line_y0
        lda arc_px
        sta line_x1
        lda arc_px+1
        sta line_x1+1
        lda arc_py
        sta line_y1
        lda arc_col
        sta line_col
        jmp draw_line

draw_arc:
        lda arc_start           ; start index
        ldx arc_start+1
        jsr arc_d2i
        sta arc_u0
        lda arc_stop            ; sweep = stop index - start index
        ldx arc_stop+1
        jsr arc_d2i
        sec
        sbc arc_u0
        sta arc_sweep
        lda arc_flags           ; combs (bit2): zero radian at 12
        and #4                  ; o'clock = shift the start back a
        bne _da_go              ; quarter turn
        clc
        lda arc_u0
        adc #0                  ; default zero radian is 3 o'clock:
        sta arc_u0              ; the point formula already starts
_da_go:                         ; there
        lda arc_flags
        and #4
        beq _da_start
        sec
        lda arc_u0
        sbc #64
        sta arc_u0
_da_start:
        lda arc_u0
        jsr arcpoint
        lda arc_px              ; remember the first point for legs
        sta arc_lx
        lda arc_px+1
        sta arc_lx+1
        lda arc_py
        sta arc_ly
        lda arc_flags
        and #1
        beq _da_notfan0
        jsr arc_spoke           ; fill: fan every point
_da_notfan0:
        lda arc_sweep
        beq _da_legs            ; degenerate: a point + legs
        lda #0
        sta arc_t
_da_loop:
        lda arc_px              ; previous point becomes chord start
        sta arc_qx
        lda arc_px+1
        sta arc_qx+1
        lda arc_py
        sta arc_qy
        inc arc_t
        clc
        lda arc_u0
        adc arc_t
        jsr arcpoint
        jsr arc_chord
        lda arc_flags
        and #1
        beq _da_nofan
        jsr arc_spoke           ; fan the new rim point
        lda arc_px              ; and the chord midpoint, so thin
        pha                     ; slivers at the rim stay covered
        lda arc_px+1
        pha
        lda arc_py
        pha
        clc
        lda arc_qx
        adc arc_px
        sta arc_px
        lda arc_qx+1
        adc arc_px+1
        sta arc_px+1
        ror arc_px+1
        ror arc_px
        clc
        lda arc_qy
        adc arc_py
        sta arc_py
        lda #0
        adc #0
        lsr a
        ror arc_py
        jsr arc_spoke
        pla
        sta arc_py
        pla
        sta arc_px+1
        pla
        sta arc_px
_da_nofan:
        lda arc_t
        cmp arc_sweep
        bne _da_loop
_da_legs:
        lda arc_flags           ; legs: bit1 suppresses, fill already
        and #3                  ; drew them as fan spokes
        bne _da_done
        jsr arc_spoke           ; centre -> end point (current)
        lda arc_lx              ; centre -> start point
        sta arc_px
        lda arc_lx+1
        sta arc_px+1
        lda arc_ly
        sta arc_py
        jsr arc_spoke
_da_done:
        rts


;=======================================================================================
; init_bitmap - Fill screen RAM with sequential codes for bitmap mode
; 40-col: 1000 positions (40×25), 80-col: 2750 positions (80×25 + TEXTYPOS overflow)
;=======================================================================================
init_bitmap:
        lda scrn_base
        sta PTR
        lda scrn_base+1
        sta PTR+1
        lda scrn_base+2
        sta PTR+2
        lda #0
        sta PTR+3
        
        lda #<CHAR_CODE_BASE
        sta _ib_code
        lda #>CHAR_CODE_BASE
        sta _ib_code+1
        
        ; Set count based on screen mode
        ldx #0
        lda screen_mode
        cmp #80
        bne +
        ldx #2
+       lda _ib_counts,x
        sta _ib_cnt
        lda _ib_counts+1,x
        sta _ib_cnt+1
        
_ib_loop:
        ldz #0
        lda _ib_code
        sta [PTR],z
        inz
        lda _ib_code+1
        sta [PTR],z
        
        inc _ib_code
        bne +
        inc _ib_code+1
+
        clc
        lda PTR
        adc #2
        sta PTR
        bcc +
        inc PTR+1
        bne +
        inc PTR+2
+
        lda _ib_cnt
        bne +
        dec _ib_cnt+1
+       dec _ib_cnt
        lda _ib_cnt
        ora _ib_cnt+1
        bne _ib_loop
        
        rts

_ib_code:   .word 0
_ib_cnt:    .word 0
_ib_counts: .word 1000, 2000    ; 40-col, 80-col ([basic65c] 80x25)

;=======================================================================================
; clear_bitmap - Clear all pixel data to a single color
; 40-col: 250×256 bytes, 80-col: 500×256 bytes
;=======================================================================================
clear_bitmap:
        ; [basic65c] rewritten as a static parameterized list: one
        ; 64000-byte fill from the draw base (gfx_base), run twice
        ; (second at base+$fa00) for a 640x200 canvas
        sta _cb_fill
        sta _cb_val
        lda gfx_base
        sta _cb_dst
        lda gfx_base+1
        sta _cb_dst+1
        lda gfx_base+2
        and #$0f
        sta _cb_dst+2
        lda gfx_base+2
        lsr
        lsr
        lsr
        lsr
        sta _cb_tmp
        lda gfx_base+3
        asl
        asl
        asl
        asl
        ora _cb_tmp
        sta _cb_dmb
        jsr _cb_go
        lda screen_mode
        cmp #80
        bne _cb_done
        clc                     ; second half (base lo/hi are 0, so no
        lda _cb_dst+1           ; carry past the hi byte)
        adc #$fa
        sta _cb_dst+1
        jsr _cb_go
_cb_done:
        rts

_cb_go:
        lda #0
        sta $d702
        sta $d704
        lda #>_cb_list
        sta $d701
        lda #<_cb_list
        sta $d705
        rts

_cb_list:
        .byte $0b
        .byte $80, $00          ; source MB
        .byte $81               ; dest MB option
_cb_dmb:
        .byte $00
        .byte $00               ; end options
        .byte $03               ; fill
        .word 64000
_cb_val:
        .byte $00, $00
        .byte $00
_cb_dst:
        .word $0000
        .byte $04
        .byte $00
        .word $0000
_cb_tmp:
        .byte 0
_cb_fill: .byte 0


;=======================================================================================
; clear_color_ram - Clear color RAM for bitmap mode
;=======================================================================================
clear_color_ram:

        ; Self-modify counts based on mode
        ldx #0
        lda screen_mode
        cmp #80
        bne +
        ldx #2
+       lda _ccr_byte_counts,x
        sta _ccr_dma1_cnt
        lda _ccr_byte_counts+1,x
        sta _ccr_dma1_cnt+1
        lda _ccr_pos_counts,x
        sta _ccr_dma2_cnt
        lda _ccr_pos_counts+1,x
        sta _ccr_dma2_cnt+1

        ; DMA 1: Fill all bytes with $00 (clears NCM/GOTO bits)
        lda #$00
        sta $D707
        .byte $81, $FF          ; dest MB
        .byte $00               ; end options
        .byte $03               ; fill command
_ccr_dma1_cnt:
        .word 5500              ; count (self-modified)
        .byte $00, $00          ; fill value = $00
        .byte $00               ; src bank
        .word $0000             ; dest = $FF80000
        .byte $08               ; dest bank
        .byte $00               ; cmd high
        .word $0000             ; modulo

        ; DMA 2: Fill odd bytes with $01 (foreground), step=2
        lda #$00
        sta $D707
        .byte $81, $FF          ; dest MB
        .byte $85, $02          ; dest step integer = 2
        .byte $84, $00          ; dest step fraction = 0
        .byte $00               ; end options
        .byte $03               ; fill command
_ccr_dma2_cnt:
        .word 2750              ; count (self-modified)
        .byte $01, $00          ; fill value = $01
        .byte $00               ; src bank
        .word $0001             ; dest = $FF80001 (odd bytes)
        .byte $08               ; dest bank
        .byte $00               ; cmd high
        .word $0000             ; modulo
        rts

_ccr_byte_counts: .word 2000, 5500     ; total bytes: 40-col, 80-col
_ccr_pos_counts:  .word 1000, 2750     ; positions: 40-col, 80-col


;=======================================================================================
; plot_pixel - Draw a pixel at x,y with color
; Input:  plot_x (16-bit), plot_y (8-bit), plot_col (8-bit)
;
; Uses MEGA65 hardware multiplier at $D770-$D77F for fast address calculation.
;
; Address = CHAR_DATA + (char_row * columns + char_col) * 64 + pixel_y * 8 + pixel_x
;
; Where: char_col = x / 8,  char_row = y / 8
;        pixel_x  = x & 7,  pixel_y  = y & 7
;        columns  = 40 (or 80)
;
; Optimization: use hardware multiply for (char_row * columns) and (char_index * 64)
;=======================================================================================
plot_x:     .word 0
plot_y:     .byte 0
plot_col:   .byte 0

plot_pixel:
        ; [basic65c] clip guard against the viewport (vp_* default to
        ; the full screen and reset on every mode switch; VIEWPORT DEF
        ; narrows them). Every shape routine funnels through here, so
        ; this bounds all drawing; negative wraps read as large
        ; unsigned values and clip.
        lda plot_y
        cmp vp_y0
        bcc _pp_clip
        cmp vp_y1
        beq _pp_ylo_ok
        bcs _pp_clip
_pp_ylo_ok:
        lda plot_x+1            ; x >= vp_x0 (16-bit)
        cmp vp_x0+1
        bcc _pp_clip
        bne _pp_xlo_ok
        lda plot_x
        cmp vp_x0
        bcc _pp_clip
_pp_xlo_ok:
        lda plot_x+1            ; x <= vp_x1 (16-bit)
        cmp vp_x1+1
        bcc _pp_clip_xok
        bne _pp_clip
        lda plot_x
        cmp vp_x1
        beq _pp_clip_xok
        bcs _pp_clip
_pp_clip_xok:
        ; char_col = x / 8
        lda plot_x
        sta _pp_char_col
        lda plot_x+1
        sta _pp_char_col+1
        
        lsr _pp_char_col+1
        ror _pp_char_col
        lsr _pp_char_col+1
        ror _pp_char_col
        lsr _pp_char_col+1
        ror _pp_char_col
        
        ; char_row = y / 8
        lda plot_y
        lsr
        lsr
        lsr
        sta _pp_char_row
        
        ; pixel_x = x AND 7
        lda plot_x
        and #$07
        sta _pp_pixel_x
        
        ; pixel_y = y AND 7
        lda plot_y
        and #$07
        sta _pp_pixel_y

        ; --- Hardware multiply: char_row * columns ---
        ; MULTINA = char_row (32-bit, only low byte used)
        lda _pp_char_row
        sta MULTINA           ; MULTINA byte 0
        lda #0
        sta MULTINA+1           ; MULTINA byte 1
        sta MULTINA+2           ; MULTINA byte 2
        sta MULTINA+3           ; MULTINA byte 3

        ; MULTINB = columns (40 or 80)
        lda screen_mode         ; 40 or 80
        sta MULTINB             ; MULTINB byte 0
        lda #0
        sta MULTINB+1           ; MULTINB byte 1
        sta MULTINB+2           ; MULTINB byte 2
        sta MULTINB+3           ; MULTINB byte 3

        ; Result available in 1 cycle - read MULTOUT (only need low 16 bits)
        ; char_index = MULTOUT + char_col
        clc
        lda MULTOUT           ; MULTOUT byte 0
        adc _pp_char_col
        sta _pp_char_idx
        lda MULTOUT+1           ; MULTOUT byte 1
        adc _pp_char_col+1
        sta _pp_char_idx+1

        ; --- Hardware multiply: char_index * 64 ---
        lda _pp_char_idx
        sta MULTINA           ; MULTINA byte 0
        lda _pp_char_idx+1
        sta MULTINA+1           ; MULTINA byte 1
        lda #0
        sta MULTINA+2
        sta MULTINA+3

        lda #64
        sta MULTINB           ; MULTINB byte 0
        lda #0
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3

        ; Result = 24-bit address offset, read MULTOUT
        ; char_base = CHAR_DATA + MULTOUT
        clc                     ; [basic65c] base = gfx_base (bank-4
        lda MULTOUT             ; canvas or an attic screen buffer)
        adc gfx_base
        sta PTR
        lda MULTOUT+1
        adc gfx_base+1
        sta PTR+1
        lda MULTOUT+2
        adc gfx_base+2
        sta PTR+2
        lda gfx_base+3
        adc #0
        sta PTR+3
        
        ; pixel_offset = pixel_y * 8 + pixel_x
        lda _pp_pixel_y
        asl
        asl
        asl
        clc
        adc _pp_pixel_x
        taz
        
        ; Write pixel
        lda plot_col
        sta [PTR],z
        
        rts

_pp_clip:
        rts
_pp_clip_t:
        .byte 0
_pp_clip_t2:
        .byte 0

_pp_char_col:   .word 0
_pp_char_row:   .byte 0
_pp_pixel_x:    .byte 0
_pp_pixel_y:    .byte 0
_pp_char_idx:   .word 0
_pp_tmp:        .byte 0, 0, 0
_pp_tmp2:       .word 0


;=======================================================================================
; get_pixel - Read pixel color at x,y
; Input:  plot_x (16-bit), plot_y (8-bit)
; Output: A = color
;
; Uses hardware multiplier for fast address calculation.
;=======================================================================================
get_pixel:
        ; [basic65c] clip guard: out-of-range reads return colour 0
        lda plot_y
        cmp #200
        bcs _gp_clip
        ldy #$40                ; x bound: 320 or 640, per mode
        ldx #1
        lda screen_mode
        cmp #80
        bne _gp_clip_b
        ldy #$80
        ldx #2
_gp_clip_b:
        stx _gp_clip_t
        sty _gp_clip_t2
        lda plot_x+1
        cmp _gp_clip_t
        bcc _gp_clip_xok
        bne _gp_clip
        lda plot_x
        cmp _gp_clip_t2
        bcs _gp_clip
_gp_clip_xok:
        lda plot_x
        sta _gp_char_col
        lda plot_x+1
        sta _gp_char_col+1
        
        lsr _gp_char_col+1
        ror _gp_char_col
        lsr _gp_char_col+1
        ror _gp_char_col
        lsr _gp_char_col+1
        ror _gp_char_col
        
        lda plot_y
        lsr
        lsr
        lsr
        sta _gp_char_row
        
        lda plot_x
        and #$07
        sta _gp_pixel_x
        
        lda plot_y
        and #$07
        sta _gp_pixel_y

        ; Hardware multiply: char_row * columns
        lda _gp_char_row
        sta MULTINA
        lda #0
        sta MULTINA+1
        sta MULTINA+2
        sta MULTINA+3
        lda screen_mode
        sta MULTINB
        lda #0
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3

        clc
        lda MULTOUT
        adc _gp_char_col
        sta _gp_char_idx
        lda MULTOUT+1
        adc _gp_char_col+1
        sta _gp_char_idx+1

        ; Hardware multiply: char_index * 64
        lda _gp_char_idx
        sta MULTINA
        lda _gp_char_idx+1
        sta MULTINA+1
        lda #0
        sta MULTINA+2
        sta MULTINA+3
        lda #64
        sta MULTINB
        lda #0
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3

        clc                     ; [basic65c] base = gfx_base
        lda MULTOUT
        adc gfx_base
        sta PTR
        lda MULTOUT+1
        adc gfx_base+1
        sta PTR+1
        lda MULTOUT+2
        adc gfx_base+2
        sta PTR+2
        lda gfx_base+3
        adc #0
        sta PTR+3
        
        lda _gp_pixel_y
        asl
        asl
        asl
        clc
        adc _gp_pixel_x
        taz
        
        lda [PTR],z
        rts

_gp_clip:
        lda #0
        rts
_gp_clip_t:
        .byte 0
_gp_clip_t2:
        .byte 0

_gp_char_col:   .word 0
_gp_char_row:   .byte 0
_gp_pixel_x:    .byte 0
_gp_pixel_y:    .byte 0
_gp_char_idx:   .word 0
_gp_tmp:        .byte 0, 0, 0
_gp_tmp2:       .word 0


;=======================================================================================
; draw_line - Bresenham line drawing (same for both modes)
;=======================================================================================
line_x0:    .word 0
line_y0:    .byte 0
line_x1:    .word 0
line_y1:    .byte 0
line_col:   .byte 0

draw_line:
        lda line_y0             ; [basic65c] horizontal spans take the
        cmp line_y1             ; one-address walk below instead of
        bne _dl_slow            ; Bresenham + full addressing per pixel
        jmp fill_hline_fast
_dl_slow:
        sec
        lda line_x1
        sbc line_x0
        sta _ln_dx
        lda line_x1+1
        sbc line_x0+1
        sta _ln_dx+1
        bpl _ln_dx_pos
        
        lda #$FF
        sta _ln_sx
        sec
        lda #0
        sbc _ln_dx
        sta _ln_dx
        lda #0
        sbc _ln_dx+1
        sta _ln_dx+1
        jmp _ln_do_dy
        
_ln_dx_pos:
        lda #1
        sta _ln_sx

_ln_do_dy:
        lda #0
        sta _ln_dy+1
        
        lda line_y1
        cmp line_y0
        bcs _ln_dy_pos
        
        lda #$FF
        sta _ln_sy
        sec
        lda line_y0
        sbc line_y1
        sta _ln_dy
        jmp _ln_setup
        
_ln_dy_pos:
        lda #1
        sta _ln_sy
        sec
        lda line_y1
        sbc line_y0
        sta _ln_dy

_ln_setup:
        lda line_x0
        sta _ln_x
        lda line_x0+1
        sta _ln_x+1
        lda line_y0
        sta _ln_y
        
        ; steps = max(dx, dy) + 1
        lda _ln_dx+1
        bne _ln_dx_bigger
        lda _ln_dy
        cmp _ln_dx
        bcc _ln_dx_bigger
        beq _ln_dx_bigger
        
        lda _ln_dy
        sta _ln_steps
        lda #0
        sta _ln_steps+1
        jmp _ln_init_err
        
_ln_dx_bigger:
        lda _ln_dx
        sta _ln_steps
        lda _ln_dx+1
        sta _ln_steps+1

_ln_init_err:
        inc _ln_steps
        bne _ln_err_setup
        inc _ln_steps+1

_ln_err_setup:
        sec
        lda _ln_dx
        sbc _ln_dy
        sta _ln_err
        lda _ln_dx+1
        sbc _ln_dy+1
        sta _ln_err+1

_ln_loop:
        lda _ln_x
        sta plot_x
        lda _ln_x+1
        sta plot_x+1
        lda _ln_y
        sta plot_y
        lda line_col
        sta plot_col
        jsr plot_pixel

        lda _ln_steps
        bne _ln_dec_steps
        dec _ln_steps+1
_ln_dec_steps:
        dec _ln_steps
        
        lda _ln_steps
        ora _ln_steps+1
        beq _ln_done

        lda _ln_err
        asl
        sta _ln_e2
        lda _ln_err+1
        rol
        sta _ln_e2+1

        clc
        lda _ln_e2
        adc _ln_dy
        sta _ln_tmp
        lda _ln_e2+1
        adc _ln_dy+1
        bmi _ln_skip_x
        ora _ln_tmp
        beq _ln_skip_x
        
        sec
        lda _ln_err
        sbc _ln_dy
        sta _ln_err
        lda _ln_err+1
        sbc _ln_dy+1
        sta _ln_err+1
        
        lda _ln_sx
        bmi _ln_x_dec
        inc _ln_x
        bne _ln_skip_x
        inc _ln_x+1
        jmp _ln_skip_x
_ln_x_dec:
        lda _ln_x
        bne _ln_x_dec2
        dec _ln_x+1
_ln_x_dec2:
        dec _ln_x

_ln_skip_x:
        sec
        lda _ln_dx
        sbc _ln_e2
        sta _ln_tmp
        lda _ln_dx+1
        sbc _ln_e2+1
        bmi _ln_loop
        ora _ln_tmp
        beq _ln_loop
        
        clc
        lda _ln_err
        adc _ln_dx
        sta _ln_err
        lda _ln_err+1
        adc _ln_dx+1
        sta _ln_err+1
        
        lda _ln_sy
        bmi _ln_y_dec
        inc _ln_y
        jmp _ln_loop
_ln_y_dec:
        dec _ln_y
        jmp _ln_loop

_ln_done:
        rts

_ln_e2:     .word 0
_ln_tmp:    .word 0
_ln_dx:     .word 0
_ln_dy:     .word 0
_ln_sx:     .byte 0
_ln_sy:     .byte 0
_ln_err:    .word 0
_ln_x:      .word 0
_ln_y:      .byte 0
_ln_steps:  .word 0

;=======================================================================================
; fill_hline_fast - horizontal span with the cell address computed once
; Input: line_x0/line_x1 (16-bit signed, either order), line_y0, line_col
;
; FCM layout: the 8 pixels of a cell row are consecutive bytes and
; the next cell is +64, so after one plot_pixel-style address
; computation the walk is sta [PTR],z / inz with a +64 PTR hop at
; each cell boundary (~10 cycles/pixel vs ~200 through plot_pixel).
; Every horizontal reaches this via draw_line's entry check: BOX and
; shape fills (fill_hline), outlines' top/bottom edges, horizontal
; LINE statements, polygon edges. Clipped against the viewport here
; (span-clamped once, not per pixel).
;=======================================================================================
fill_hline_fast:
        lda line_y0             ; y inside the viewport rows
        cmp vp_y0
        bcc _hf_done
        cmp vp_y1
        beq _hf_yok
        bcs _hf_done
_hf_yok:
        lda line_x0             ; order the endpoints (signed):
        sta hf_x0               ; hf_x0 <= hf_x1
        lda line_x0+1
        sta hf_x0+1
        lda line_x1
        sta hf_x1
        lda line_x1+1
        sta hf_x1+1
        lda hf_x0+1
        eor #$80
        sta hf_t
        lda hf_x1+1
        eor #$80
        cmp hf_t
        bcc _hf_swap
        bne _hf_ordered
        lda hf_x1
        cmp hf_x0
        bcs _hf_ordered
_hf_swap:
        ldx hf_x0
        lda hf_x1
        sta hf_x0
        stx hf_x1
        ldx hf_x0+1
        lda hf_x1+1
        sta hf_x0+1
        stx hf_x1+1
_hf_ordered:
        lda hf_x1+1             ; span entirely left of the viewport?
        bmi _hf_done            ; (x1 negative)
        cmp vp_x1+1             ; clamp x1 to the right edge
        bcc _hf_x1ok
        bne _hf_x1clamp
        lda hf_x1
        cmp vp_x1
        bcc _hf_x1ok
        beq _hf_x1ok
_hf_x1clamp:
        lda vp_x1
        sta hf_x1
        lda vp_x1+1
        sta hf_x1+1
_hf_x1ok:
        lda hf_x0+1             ; clamp x0 to the left edge (negative
        bmi _hf_x0clamp         ; x0 clamps too)
        cmp vp_x0+1
        bcc _hf_x0clamp
        bne _hf_x0ok
        lda hf_x0
        cmp vp_x0
        bcs _hf_x0ok
_hf_x0clamp:
        lda vp_x0
        sta hf_x0
        lda vp_x0+1
        sta hf_x0+1
_hf_x0ok:
        sec                     ; count = x1 - x0 + 1; empty when the
        lda hf_x1               ; clamped span inverted
        sbc hf_x0
        sta hf_cnt
        lda hf_x1+1
        sbc hf_x0+1
        sta hf_cnt+1
        bcc _hf_done
        inc hf_cnt
        bne +
        inc hf_cnt+1
+
        ; --- address of (hf_x0, line_y0), as plot_pixel computes it ---
        lda hf_x0
        and #$07
        sta hf_off              ; pixel offset in the first cell
        lda hf_x0
        sta hf_col
        lda hf_x0+1
        sta hf_col+1
        lsr hf_col+1
        ror hf_col
        lsr hf_col+1
        ror hf_col
        lsr hf_col+1
        ror hf_col              ; char column
        lda line_y0
        lsr a
        lsr a
        lsr a
        sta MULTINA             ; char row * columns
        lda #0
        sta MULTINA+1
        sta MULTINA+2
        sta MULTINA+3
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3
        lda screen_mode
        sta MULTINB
        clc
        lda MULTOUT
        adc hf_col
        sta hf_col
        lda MULTOUT+1
        adc hf_col+1
        sta hf_col+1            ; cell index
        lda hf_col
        sta MULTINA             ; * 64
        lda hf_col+1
        sta MULTINA+1
        lda #0
        sta MULTINA+2
        sta MULTINA+3
        lda #64
        sta MULTINB
        clc
        lda MULTOUT
        adc gfx_base
        sta PTR
        lda MULTOUT+1
        adc gfx_base+1
        sta PTR+1
        lda MULTOUT+2
        adc gfx_base+2
        sta PTR+2
        lda gfx_base+3
        adc #0
        sta PTR+3
        lda line_y0
        and #$07
        asl a
        asl a
        asl a
        sta hf_zbase            ; (y & 7) * 8
        clc
        adc hf_off
        taz                     ; z = start pixel in the first cell
        lda #8
        sec
        sbc hf_off
        sta hf_cell             ; pixels left in the first cell

_hf_cellloop:
        lda hf_cell             ; n = min(count, pixels in this cell)
        ldx hf_cnt+1
        bne _hf_full
        cmp hf_cnt
        bcc _hf_full
        lda hf_cnt
_hf_full:
        sta hf_n
        sec                     ; count -= n
        lda hf_cnt
        sbc hf_n
        sta hf_cnt
        bcs +
        dec hf_cnt+1
+       ldx hf_n
        lda line_col
_hf_store:
        sta [PTR],z
        inz
        dex
        bne _hf_store
        lda hf_cnt
        ora hf_cnt+1
        beq _hf_done
        clc                     ; next cell: +64, back to the row base
        lda PTR
        adc #64
        sta PTR
        bcc +
        inc PTR+1
        bne +
        inc PTR+2
+       lda hf_zbase
        taz
        lda #8
        sta hf_cell
        bra _hf_cellloop
_hf_done:
        rts

hf_x0:      .word 0
hf_x1:      .word 0
hf_cnt:     .word 0
hf_col:     .word 0
hf_cell:    .byte 0
hf_n:       .byte 0
hf_off:     .byte 0
hf_zbase:   .byte 0
hf_t:       .byte 0


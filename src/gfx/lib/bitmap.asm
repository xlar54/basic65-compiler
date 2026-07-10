
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
        ; [basic65c] cell address without the hardware multiplier:
        ; gfx_base + rowtab[y/8] + (x/8)*64, with (x/8)*64 split into
        ; high = col/4 and low = (col & 3) * 64 from a 4-entry table
        jsr pixcelladdr
        lda plot_col
        sta [PTR],z
_pp_clip:
        rts

; PTR/Z = cell address + pixel offset for plot_x/plot_y (in range).
; Shared by plot_pixel and get_pixel.
pixcelladdr:
        lda plot_x
        sta _pca_col
        lda plot_x+1
        sta _pca_col+1
        lsr _pca_col+1
        ror _pca_col
        lsr _pca_col+1
        ror _pca_col
        lsr _pca_col+1
        ror _pca_col        ; char column 0-79
        lda plot_y
        lsr a
        lsr a
        lsr a
        tax                     ; char row 0-24
        lda _pca_col
        and #$03
        tay
        lda _pca_col        ; col/4 = high byte of col*64, staged
        lsr a                   ; before the adds (lsr clobbers carry)
        lsr a
        sta _pca_hi6
        lda screen_mode
        cmp #80
        beq _pca_80
        clc                     ; offset = rowtab + col/4 : (col&3)*64
        lda t64lo,y
        adc rowtab40_lo,x
        sta _pca_idx
        lda _pca_hi6
        adc rowtab40_hi,x
        sta _pca_idx+1
        lda #0
        adc rowtab40_bk,x
        bra _pca_base
_pca_80:
        clc
        lda t64lo,y
        adc rowtab80_lo,x
        sta _pca_idx
        lda _pca_hi6
        adc rowtab80_hi,x
        sta _pca_idx+1
        lda #0
        adc rowtab80_bk,x
_pca_base:
        tax                     ; offset bank byte
        clc
        lda _pca_idx
        adc gfx_base
        sta PTR
        lda _pca_idx+1
        adc gfx_base+1
        sta PTR+1
        txa
        adc gfx_base+2
        sta PTR+2
        lda gfx_base+3
        adc #0
        sta PTR+3
        lda plot_y              ; z = (y & 7) * 8 + (x & 7)
        and #$07
        asl a
        asl a
        asl a
        sta _pca_z
        lda plot_x
        and #$07
        clc
        adc _pca_z
        taz
        rts
_pca_col:   .word 0
_pca_idx:   .word 0
_pca_hi6:   .byte 0
_pca_z:     .byte 0

t64lo:
        .byte 0, 64, 128, 192
rowtab40_lo:
        .for _r := 0, _r < 32, _r += 1
        .byte <(_r * 2560)
        .next
rowtab40_hi:
        .for _r := 0, _r < 32, _r += 1
        .byte >(_r * 2560)
        .next
rowtab40_bk:
        .for _r := 0, _r < 32, _r += 1
        .byte (_r * 2560) >> 16
        .next
rowtab80_lo:
        .for _r := 0, _r < 32, _r += 1
        .byte <(_r * 5120)
        .next
rowtab80_hi:
        .for _r := 0, _r < 32, _r += 1
        .byte >(_r * 5120)
        .next
rowtab80_bk:
        .for _r := 0, _r < 32, _r += 1
        .byte (_r * 5120) >> 16
        .next

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
        jsr pixcelladdr         ; [basic65c] shared table-based address
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
        jsr _ln_addrinit
        
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
        lda _ln_xok             ; store through the maintained cell
        and _ln_yok             ; address; off-viewport steps keep the
        beq +                   ; walk consistent but write nothing
        lda line_col
        sta [PTR],z
+

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
        jsr _ln_xinc
        jmp _ln_skip_x
_ln_x_dec:
        jsr _ln_xdec

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
        jsr _ln_yinc
        jmp _ln_loop
_ln_y_dec:
        jsr _ln_ydec
        jmp _ln_loop

_ln_done:
        rts

; ---- incremental address walk: PTR/Z track (_ln_x,_ln_y) on the
; linear FCM cell grid (consistent even off-canvas; rowtab has 32
; entries so rows 25-31 stay linear); _ln_xok/_ln_yok gate stores
_ln_addrinit:
        ldx #<2560              ; row stride = columns * 64
        ldy #>2560
        lda screen_mode
        cmp #80
        bne +
        ldx #<5120
        ldy #>5120
+       stx _ln_stride
        sty _ln_stride+1
        lda _ln_x
        and #$07
        sta _ln_xm
        lda _ln_y
        and #$07
        sta _ln_ym
        asl a
        asl a
        asl a
        clc
        adc _ln_xm
        taz                     ; z = (y & 7) * 8 + (x & 7)
        lda _ln_x               ; col = x >> 3, arithmetic (x signed)
        sta _ln_col
        lda _ln_x+1
        sta _ln_col+1
        ldx #3
-       lda _ln_col+1
        asr a
        sta _ln_col+1
        ror _ln_col
        dex
        bne -
        lda _ln_col             ; off = col * 64, sign-extended 24-bit
        sta _ln_off
        lda _ln_col+1
        sta _ln_off+1
        and #$80
        beq +
        lda #$ff
+       sta _ln_off+2
        ldx #6
-       asl _ln_off
        rol _ln_off+1
        rol _ln_off+2
        dex
        bne -
        lda _ln_y               ; + rowtab[y >> 3]
        lsr a
        lsr a
        lsr a
        tax
        lda screen_mode
        cmp #80
        beq _ln_ai80
        clc
        lda _ln_off
        adc rowtab40_lo,x
        sta _ln_off
        lda _ln_off+1
        adc rowtab40_hi,x
        sta _ln_off+1
        lda _ln_off+2
        adc rowtab40_bk,x
        sta _ln_off+2
        bra _ln_aibase
_ln_ai80:
        clc
        lda _ln_off
        adc rowtab80_lo,x
        sta _ln_off
        lda _ln_off+1
        adc rowtab80_hi,x
        sta _ln_off+1
        lda _ln_off+2
        adc rowtab80_bk,x
        sta _ln_off+2
_ln_aibase:
        lda _ln_off+2           ; sign byte for the 32-bit base add
        and #$80
        beq +
        lda #$ff
+       tax
        clc
        lda _ln_off
        adc gfx_base
        sta PTR
        lda _ln_off+1
        adc gfx_base+1
        sta PTR+1
        lda _ln_off+2
        adc gfx_base+2
        sta PTR+2
        txa
        adc gfx_base+3
        sta PTR+3
        jsr _ln_xflag
        jmp _ln_yflag

_ln_xinc:
        inc _ln_x
        bne +
        inc _ln_x+1
+       inz
        inc _ln_xm
        lda _ln_xm
        cmp #8
        bne _ln_xflag
        lda #0
        sta _ln_xm
        tza
        sec
        sbc #8
        taz
        clc                     ; next cell right
        lda PTR
        adc #64
        sta PTR
        lda PTR+1
        adc #0
        sta PTR+1
        lda PTR+2
        adc #0
        sta PTR+2
        bra _ln_xflag

_ln_xdec:
        lda _ln_x
        bne +
        dec _ln_x+1
+       dec _ln_x
        dez
        dec _ln_xm
        bpl _ln_xflag
        lda #7
        sta _ln_xm
        tza
        clc
        adc #8
        taz
        sec                     ; previous cell
        lda PTR
        sbc #64
        sta PTR
        lda PTR+1
        sbc #0
        sta PTR+1
        lda PTR+2
        sbc #0
        sta PTR+2
_ln_xflag:
        lda #0
        sta _ln_xok
        lda _ln_x+1
        bmi _ln_xf_done         ; negative x: outside
        cmp vp_x0+1
        bcc _ln_xf_done
        bne _ln_xf_hiok
        lda _ln_x
        cmp vp_x0
        bcc _ln_xf_done
_ln_xf_hiok:
        lda _ln_x+1
        cmp vp_x1+1
        bcc _ln_xf_in
        bne _ln_xf_done
        lda _ln_x
        cmp vp_x1
        beq _ln_xf_in
        bcs _ln_xf_done
_ln_xf_in:
        lda #1
        sta _ln_xok
_ln_xf_done:
        rts

_ln_yinc:
        inc _ln_y
        tza
        clc
        adc #8
        taz
        inc _ln_ym
        lda _ln_ym
        cmp #8
        bne _ln_yflag
        lda #0
        sta _ln_ym
        tza
        sec
        sbc #64
        taz
        clc                     ; next cell row down
        lda PTR
        adc _ln_stride
        sta PTR
        lda PTR+1
        adc _ln_stride+1
        sta PTR+1
        lda PTR+2
        adc #0
        sta PTR+2
        bra _ln_yflag

_ln_ydec:
        dec _ln_y
        tza
        sec
        sbc #8
        taz
        dec _ln_ym
        bpl _ln_yflag
        lda #7
        sta _ln_ym
        tza
        clc
        adc #64
        taz
        sec                     ; previous cell row
        lda PTR
        sbc _ln_stride
        sta PTR
        lda PTR+1
        sbc _ln_stride+1
        sta PTR+1
        lda PTR+2
        sbc #0
        sta PTR+2
_ln_yflag:
        lda #0
        sta _ln_yok
        lda _ln_y
        cmp vp_y0
        bcc _ln_yf_done
        cmp vp_y1
        beq _ln_yf_in
        bcs _ln_yf_done
_ln_yf_in:
        lda #1
        sta _ln_yok
_ln_yf_done:
        rts

_ln_xm:     .byte 0
_ln_ym:     .byte 0
_ln_xok:    .byte 0
_ln_yok:    .byte 0
_ln_stride: .word 0
_ln_col:    .word 0
_ln_off:    .byte 0, 0, 0

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


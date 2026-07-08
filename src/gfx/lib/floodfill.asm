;=======================================================================================
; floodfill.asm - Flood fill (paint bucket) for MEGA65 FCM bitmap mode
;=======================================================================================
; Fills a region starting from a seed point until it hits pixels of a different color
; (boundary fill) or fills all pixels of the same color (color replace fill).
;
; Two modes:
;   1. BOUNDARY FILL: Fill until hitting any pixel != fill_color
;   2. REPLACE FILL: Replace all pixels matching target color with fill color
;
; Uses scanline flood fill algorithm (faster and more memory efficient than
; recursive approach). Maintains a stack of scanline segments to process.
;
; Memory usage: ~2KB stack space for pending scanlines
;
; Usage:
;   ; Boundary fill example (fill enclosed area)
;   lda #<320
;   sta flood_x
;   lda #>320
;   sta flood_x+1
;   lda #100
;   sta flood_y
;   lda #$0E        ; Fill with light blue
;   sta flood_color
;   lda #0          ; Mode 0 = boundary fill
;   sta flood_mode
;   jsr flood_fill
;
;   ; Replace fill example (replace all red pixels with green)
;   lda #1          ; Mode 1 = replace fill
;   sta flood_mode
;   lda #$0A        ; Replace red
;   sta flood_target
;   lda #$05        ; With green
;   sta flood_color
;   jsr flood_fill
;
;=======================================================================================

;=======================================================================================
; Public parameters
;=======================================================================================
flood_x:        .word 0         ; Seed point X (16-bit)
flood_y:        .byte 0         ; Seed point Y (8-bit)
flood_color:    .byte 0         ; Color to fill with
flood_mode:     .byte 0         ; 0 = boundary fill, 1 = replace fill
flood_target:   .byte 0         ; Target color to replace (mode 1 only)

;=======================================================================================
; flood_fill - Main flood fill entry point
; Returns: Carry clear = success, Carry set = error (invalid params or stack overflow)
;=======================================================================================
flood_fill:
        ; Validate coordinates
        lda flood_x+1
        bne _ff_error           ; X > 255 means X >= 256, check against screen width
        
        lda screen_mode
        cmp #80
        beq _ff_check_640
        
        ; 40-col mode: width = 320
        lda flood_x+1
        cmp #1
        bcc _ff_y_check         ; X < 256, OK
        bne _ff_error           ; X >= 512, error
        lda flood_x
        cmp #64                 ; Check if X < 320
        bcs _ff_error
        jmp _ff_y_check

_ff_check_640:
        ; 80-col mode: width = 640
        lda flood_x+1
        cmp #2
        bcc _ff_y_check         ; X < 512, OK
        bne _ff_error           ; X >= 768, error
        lda flood_x
        cmp #128                ; Check if X < 640
        bcs _ff_error

_ff_y_check:
        lda flood_y
        cmp #200
        bcs _ff_error           ; Y >= 200, error

        ; Get pixel at seed point
        lda flood_x
        sta plot_x
        lda flood_x+1
        sta plot_x+1
        lda flood_y
        sta plot_y
        jsr get_pixel           ; Returns color in A
        sta _ff_seed_color

        ; Determine target color based on mode
        lda flood_mode
        beq _ff_boundary_mode
        
        ; Replace mode: target is flood_target
        lda flood_target
        sta _ff_target_color
        jmp _ff_check_same

_ff_boundary_mode:
        ; Boundary mode: target is seed color, don't fill if seed == fill_color
        lda _ff_seed_color
        sta _ff_target_color
        cmp flood_color
        beq _ff_error           ; Already the fill color, nothing to do

_ff_check_same:
        ; Don't fill if target == fill_color
        lda _ff_target_color
        cmp flood_color
        beq _ff_error

        ; Initialize stack
        jsr _ff_stack_init

        ; Push initial seed point
        lda flood_x
        sta _ff_push_x
        lda flood_x+1
        sta _ff_push_x+1
        lda flood_y
        sta _ff_push_y
        jsr _ff_stack_push
        bcs _ff_error

        ; Main processing loop
_ff_main_loop:
        ; Pop a scanline seed point
        jsr _ff_stack_pop
        bcs _ff_done            ; Stack empty = done

        ; Process this scanline
        jsr _ff_process_scanline
        bcs _ff_error           ; Stack overflow

        jmp _ff_main_loop

_ff_done:
        clc
        rts

_ff_error:
        sec
        rts

;=======================================================================================
; _ff_process_scanline - Fill a scanline and push adjacent scanlines
;=======================================================================================
_ff_process_scanline:
        ; Start from the popped point
        lda _ff_pop_x
        sta _ff_scan_x
        lda _ff_pop_x+1
        sta _ff_scan_x+1
        lda _ff_pop_y
        sta _ff_scan_y

        ; Check if this pixel should be filled
        lda _ff_scan_x
        sta plot_x
        lda _ff_scan_x+1
        sta plot_x+1
        lda _ff_scan_y
        sta plot_y
        jsr get_pixel
        cmp _ff_target_color
        bne _ff_ps_skip         ; Not target color, skip

        ; Scan left to find span start
        jsr _ff_scan_left
        
        ; Now scan right, filling as we go
        jsr _ff_scan_right

        ; Check scanline above for new seeds
        lda _ff_scan_y
        beq _ff_ps_no_above     ; Y=0, no line above
        dec _ff_scan_y
        jsr _ff_check_adjacent
        inc _ff_scan_y

_ff_ps_no_above:
        ; Check scanline below for new seeds
        lda _ff_scan_y
        cmp #199
        beq _ff_ps_no_below     ; Y=199, no line below
        inc _ff_scan_y
        jsr _ff_check_adjacent
        dec _ff_scan_y

_ff_ps_no_below:
_ff_ps_skip:
        clc
        rts

;=======================================================================================
; _ff_scan_left - Scan left from current position to find span start
; Updates _ff_left_x to leftmost fillable pixel
;=======================================================================================
_ff_scan_left:
        lda _ff_scan_x
        sta _ff_left_x
        lda _ff_scan_x+1
        sta _ff_left_x+1

_ff_sl_loop:
        ; Check if we can go further left
        lda _ff_left_x
        bne _ff_sl_check_pixel
        lda _ff_left_x+1
        beq _ff_sl_done         ; Hit X=0

_ff_sl_check_pixel:
        ; Move left
        lda _ff_left_x
        bne _ff_sl_dec
        dec _ff_left_x+1
_ff_sl_dec:
        dec _ff_left_x

        ; Check pixel
        lda _ff_left_x
        sta plot_x
        lda _ff_left_x+1
        sta plot_x+1
        lda _ff_scan_y
        sta plot_y
        jsr get_pixel
        cmp _ff_target_color
        beq _ff_sl_loop         ; Keep going left

        ; Hit boundary, move back right one pixel
        inc _ff_left_x
        bne _ff_sl_done
        inc _ff_left_x+1

_ff_sl_done:
        rts

;=======================================================================================
; _ff_scan_right - Scan right from _ff_left_x, filling pixels
; Updates _ff_right_x to rightmost filled pixel
;=======================================================================================
_ff_scan_right:
        ; Determine screen width
        lda screen_mode
        cmp #80
        beq _ff_sr_640

        ; 40-col: width = 320
        lda #<320
        sta _ff_max_x
        lda #>320
        sta _ff_max_x+1
        jmp _ff_sr_start

_ff_sr_640:
        ; 80-col: width = 640
        lda #<640
        sta _ff_max_x
        lda #>640
        sta _ff_max_x+1

_ff_sr_start:
        lda _ff_left_x
        sta _ff_right_x
        lda _ff_left_x+1
        sta _ff_right_x+1

_ff_sr_loop:
        ; Check if at screen edge
        lda _ff_right_x+1
        cmp _ff_max_x+1
        bcc _ff_sr_in_bounds
        bne _ff_sr_done
        lda _ff_right_x
        cmp _ff_max_x
        bcs _ff_sr_done

_ff_sr_in_bounds:
        ; Check pixel
        lda _ff_right_x
        sta plot_x
        lda _ff_right_x+1
        sta plot_x+1
        lda _ff_scan_y
        sta plot_y
        jsr get_pixel
        cmp _ff_target_color
        bne _ff_sr_done         ; Hit boundary

        ; Fill this pixel
        lda flood_color
        sta plot_col
        jsr plot_pixel

        ; Move right
        inc _ff_right_x
        bne _ff_sr_loop
        inc _ff_right_x+1
        jmp _ff_sr_loop

_ff_sr_done:
        ; Back up one pixel (right_x is now one past the last filled pixel)
        lda _ff_right_x
        bne _ff_sr_dec
        dec _ff_right_x+1
_ff_sr_dec:
        dec _ff_right_x
        rts

;=======================================================================================
; _ff_check_adjacent - Scan adjacent line for seeds to push
; Input: _ff_scan_y = Y coordinate to check
;        _ff_left_x to _ff_right_x = span to check
;=======================================================================================
_ff_check_adjacent:
        lda _ff_left_x
        sta _ff_adj_x
        lda _ff_left_x+1
        sta _ff_adj_x+1
        lda #0
        sta _ff_in_span         ; Track if we're in a fillable span

_ff_ca_loop:
        ; Check if past right edge
        lda _ff_adj_x+1
        cmp _ff_right_x+1
        bcc _ff_ca_check
        bne _ff_ca_done
        lda _ff_adj_x
        cmp _ff_right_x
        beq _ff_ca_check
        bcs _ff_ca_done

_ff_ca_check:
        ; Check pixel
        lda _ff_adj_x
        sta plot_x
        lda _ff_adj_x+1
        sta plot_x+1
        lda _ff_scan_y
        sta plot_y
        jsr get_pixel
        cmp _ff_target_color
        bne _ff_ca_not_target

        ; Pixel is fillable
        lda _ff_in_span
        bne _ff_ca_next         ; Already in span, continue

        ; Start of new span - push this point
        lda #1
        sta _ff_in_span
        lda _ff_adj_x
        sta _ff_push_x
        lda _ff_adj_x+1
        sta _ff_push_x+1
        lda _ff_scan_y
        sta _ff_push_y
        jsr _ff_stack_push
        bcs _ff_ca_error
        jmp _ff_ca_next

_ff_ca_not_target:
        ; Hit boundary, end span
        lda #0
        sta _ff_in_span

_ff_ca_next:
        ; Move to next pixel
        inc _ff_adj_x
        bne _ff_ca_loop
        inc _ff_adj_x+1
        jmp _ff_ca_loop

_ff_ca_done:
        clc
        rts

_ff_ca_error:
        sec
        rts

;=======================================================================================
; Stack management - Stores scanline seed points
; Stack grows upward in memory, max 512 entries (1536 bytes)
;=======================================================================================
STACK_SIZE = 512                ; Max 512 seed points (X:word, Y:byte = 3 bytes each)

_ff_stack_init:
        lda #0
        sta _ff_stack_ptr
        sta _ff_stack_ptr+1
        rts

_ff_stack_push:
        ; Check for overflow
        lda _ff_stack_ptr+1
        cmp #>(STACK_SIZE * 3)
        bcc _ff_sp_ok
        bne _ff_sp_overflow
        lda _ff_stack_ptr
        cmp #<(STACK_SIZE * 3)
        bcs _ff_sp_overflow

_ff_sp_ok:
        ; Calculate stack address: FLOOD_STACK + ptr
        clc
        lda #<FLOOD_STACK
        adc _ff_stack_ptr
        sta PTR
        lda #>FLOOD_STACK
        adc _ff_stack_ptr+1
        sta PTR+1
        lda #0
        sta PTR+2
        sta PTR+3

        ; Push X (word)
        ldz #0
        lda _ff_push_x
        sta [PTR],z
        inz
        lda _ff_push_x+1
        sta [PTR],z
        inz
        lda _ff_push_y
        sta [PTR],z

        ; Increment stack pointer by 3
        clc
        lda _ff_stack_ptr
        adc #3
        sta _ff_stack_ptr
        bcc +
        inc _ff_stack_ptr+1
+       
        clc
        rts

_ff_sp_overflow:
        sec
        rts

_ff_stack_pop:
        ; Check if empty
        lda _ff_stack_ptr
        bne _ff_spo_ok
        lda _ff_stack_ptr+1
        bne _ff_spo_ok
        sec                     ; Stack empty
        rts

_ff_spo_ok:
        ; Decrement stack pointer by 3
        sec
        lda _ff_stack_ptr
        sbc #3
        sta _ff_stack_ptr
        lda _ff_stack_ptr+1
        sbc #0
        sta _ff_stack_ptr+1

        ; Calculate stack address
        clc
        lda #<FLOOD_STACK
        adc _ff_stack_ptr
        sta PTR
        lda #>FLOOD_STACK
        adc _ff_stack_ptr+1
        sta PTR+1
        lda #0
        sta PTR+2
        sta PTR+3

        ; Pop values
        ldz #0
        lda [PTR],z
        sta _ff_pop_x
        inz
        lda [PTR],z
        sta _ff_pop_x+1
        inz
        lda [PTR],z
        sta _ff_pop_y

        clc
        rts

;=======================================================================================
; Working variables
;=======================================================================================
_ff_seed_color:     .byte 0
_ff_target_color:   .byte 0
_ff_scan_x:         .word 0
_ff_scan_y:         .byte 0
_ff_left_x:         .word 0
_ff_right_x:        .word 0
_ff_adj_x:          .word 0
_ff_in_span:        .byte 0
_ff_max_x:          .word 0
_ff_push_x:         .word 0
_ff_push_y:         .byte 0
_ff_pop_x:          .word 0
_ff_pop_y:          .byte 0
_ff_stack_ptr:      .word 0


;=======================================================================================
; Stack storage - 1536 bytes for 512 seed points
;=======================================================================================
        .align 256              ; Align for efficiency
FLOOD_STACK:
        .fill STACK_SIZE * 3, 0
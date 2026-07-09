screen_mode:
        ; Text/bitmap modes store visible columns (40 or 80).
        ; NCM modes store visible 16-pixel cells (20 or 40); helpers that need
        ; the 8-pixel-spaced backing positions multiply this by 2.
        .byte $00

ssm_mode: .byte 0
scrn_base: .byte <SCREEN_RAM40, >SCREEN_RAM40, `SCREEN_RAM40

;=======================================================================================
; set_screen_mode - Initialize screen mode
; Input: A = mode (0-6, other values treated as 0)
; Destroys: A, X, Y, Z, PTR
;=======================================================================================
set_screen_mode:
        ; Validate mode
        cmp #7
        bcc _ssm_valid
        lda #0                  ; Invalid mode -> BASIC
_ssm_valid:
        sta ssm_mode
        
        ; Mode 0 = exit to BASIC
        cmp #0
        bne _ssm_fcm_init
        jmp restore_default_screen

_ssm_fcm_init:
        ; Enable MEGA65 VIC-IV registers
        lda #$47
        sta VIC4_KEY
        lda #$53
        sta VIC4_KEY

        ; Make custom RAM palette entries visible for colors 0-15.
        lda #VIC3_PAL_RAM_BIT
        tsb VIC3_MMAP_CTRL

        ; Disable hot registers
        lda #$80
        trb $D05D

        ; Enable SEAM mode
        lda #%00000101
        sta VIC4_CTRL

        ; turn off screen while clearing RAM
        jsr _ssm_screen_off

        ; Branch based on mode
        lda ssm_mode
        cmp #MODE_TEXT40
        beq _ssm_text40
        cmp #MODE_TEXT80
        beq _ssm_text80
        cmp #MODE_BITMAP40
        beq _ssm_bitmap40
        cmp #MODE_BITMAP80
        beq _ssm_bitmap80
        cmp #MODE_NCM40
        beq _ssm_ncm40
        cmp #MODE_NCM80
        beq _ssm_ncm80
        jmp restore_default_screen     ; Fallback

;---------------------------------------------------------------------------------------
; Text 40-column mode
;---------------------------------------------------------------------------------------
_ssm_text40:
        lda #40
        sta screen_mode

        lda VIC3_CTRL
        and #%01011111          ; Clear H640 AND ATTR
        sta VIC3_CTRL

        lda #80
        sta VIC4_LINESTPLSB
        lda #0
        sta VIC4_LINESTPMSB

        lda #40
        sta VIC4_CHRCOUNT               ; CHRCOUNT

        lda #25
        sta VIC4_DISPROWS               ; CHRCOUNT_V - number of rows 

        lda #$50
        sta VIC4_TEXTXPOS
        lda #0
        sta VIC4_TEXTXPOS+1
        lda #$69
        sta VIC4_TEXTYPOS

        jmp _ssm_finish_text

;---------------------------------------------------------------------------------------
; Text 80-column mode
;---------------------------------------------------------------------------------------
_ssm_text80:
        lda #80
        sta screen_mode

        lda VIC3_CTRL
        and #%11011111          ; Clear ATTR
        ora #%10000000          ; Set H640
        sta VIC3_CTRL

        lda #160
        sta VIC4_LINESTPLSB
        lda #0
        sta VIC4_LINESTPMSB

        lda #80
        sta VIC4_CHRCOUNT               ; CHRCOUNT

        lda #25
        sta VIC4_DISPROWS               ; CHRCOUNT_V - number of rows 

        lda #$50
        sta VIC4_TEXTXPOS
        lda #0
        sta VIC4_TEXTXPOS+1
        lda #$69
        sta VIC4_TEXTYPOS

        jmp _ssm_finish_text

;---------------------------------------------------------------------------------------
; Bitmap 40-column mode (320×200)
;---------------------------------------------------------------------------------------
_ssm_bitmap40:
        lda #40
        sta screen_mode
        lda #<SCREEN_RAM40
        sta scrn_base
        lda #>SCREEN_RAM40
        sta scrn_base+1
        lda #`SCREEN_RAM40
        sta scrn_base+2

        lda VIC3_CTRL
        and #%01111111          ; Clear H640
        ora #%00100000          ; Set ATTR
        sta VIC3_CTRL

        lda #80
        sta VIC4_LINESTPLSB
        lda #0
        sta VIC4_LINESTPMSB

        lda #40
        sta VIC4_CHRCOUNT               ; CHRCOUNT

        lda #25
        sta VIC4_DISPROWS               ; CHRCOUNT_V - number of rows 

        lda #$50
        sta VIC4_TEXTXPOS
        lda #0
        sta VIC4_TEXTXPOS+1
        lda #$69
        sta VIC4_TEXTYPOS

        jmp _ssm_finish_bitmap

;---------------------------------------------------------------------------------------
; Bitmap 80-column mode (640×200)
;---------------------------------------------------------------------------------------
_ssm_bitmap80:

        lda #80
        sta screen_mode
        lda #<SCREEN_RAM80
        sta scrn_base
        lda #>SCREEN_RAM80
        sta scrn_base+1
        lda #`SCREEN_RAM80
        sta scrn_base+2

        lda VIC3_CTRL
        and #%01011111          ; Clear H640 and ATTR first
        ora #%10100000          ; Then set H640 + ATTR
        sta VIC3_CTRL

        lda #160
        sta VIC4_LINESTPLSB
        lda #0
        sta VIC4_LINESTPMSB

        lda #80
        sta VIC4_CHRCOUNT               ; CHRCOUNT

        lda #25
        sta VIC4_DISPROWS               ; CHRCOUNT_V - number of rows 

        lda #$50
        sta VIC4_TEXTXPOS
        lda #0
        sta VIC4_TEXTXPOS+1
        lda #$69
        sta VIC4_TEXTYPOS

        jmp _ssm_finish_bitmap

;---------------------------------------------------------------------------------------
; NCM 40-column mode (320×200, 20 chars wide × 16 pixels)
;---------------------------------------------------------------------------------------
_ssm_ncm40:
        lda #20                 ; 20 visible NCM cells, 40 backing positions
        sta screen_mode

        lda VIC3_CTRL
        and #%01011111          ; Clear H640 AND clear ATTR first
        sta VIC3_CTRL

        lda #80                 ; LINESTEP = 40 backing positions x 2 bytes
        sta VIC4_LINESTPLSB
        lda #0
        sta VIC4_LINESTPMSB

        lda #40
        sta VIC4_CHRCOUNT       ; 40 8-pixel units = 20 NCM cells

        lda #25
        sta VIC4_DISPROWS               ; CHRCOUNT_V - number of rows 

        lda #$50
        sta VIC4_TEXTXPOS
        lda #0
        sta VIC4_TEXTXPOS+1
        lda #$69
        sta VIC4_TEXTYPOS

        ; Enable FCLRHI (bit 2) for FCM on screen codes 256+
        ; Enable CHR16 (bit 0) for 16-pixel wide characters
        ; NCM characters must be FCM characters with color RAM bit 3 set
        lda VIC4_CTRL
        ora #%00000101          ; Set FCLRHI (bit 2) + CHR16 (bit 0)
        sta VIC4_CTRL

        jmp _ssm_finish_ncm

;---------------------------------------------------------------------------------------
; NCM 80-column mode (640×200, 40 chars wide × 16 pixels)
;---------------------------------------------------------------------------------------
_ssm_ncm80:
        lda #40                 ; 40 visible NCM cells, 80 backing positions
        sta screen_mode

        lda VIC3_CTRL
        and #%01011111          ; Clear H640 and ATTR first
        ora #%10000000          ; Then set H640
        sta VIC3_CTRL

        lda #160                ; LINESTEP = 80 backing positions x 2 bytes
        sta VIC4_LINESTPLSB
        lda #0
        sta VIC4_LINESTPMSB

        lda #80
        sta VIC4_CHRCOUNT       ; 80 8-pixel units = 40 NCM cells

        lda #25
        sta VIC4_DISPROWS               ; CHRCOUNT_V - number of rows 

        lda #$50
        sta VIC4_TEXTXPOS
        lda #0
        sta VIC4_TEXTXPOS+1
        lda #$69
        sta VIC4_TEXTYPOS

        ; Enable FCLRHI (bit 2) for FCM on screen codes 256+
        ; Enable CHR16 (bit 0) for 16-pixel wide characters
        ; NCM characters must be FCM characters with color RAM bit 3 set
        lda VIC4_CTRL
        ora #%00000101          ; Set FCLRHI (bit 2) + CHR16 (bit 0)
        sta VIC4_CTRL

        jmp _ssm_finish_ncm

;---------------------------------------------------------------------------------------
; Common setup for text modes
;---------------------------------------------------------------------------------------
_ssm_finish_text:
        jsr _ssm_setup_pointers

        ; Clear color RAM with NCM=0 for traditional chars
        lda #$05                ; Green foreground
        jsr clear_color_ram_text
        
        ; Load custom characters for text mode
        jsr load_chars
        
        jmp _ssm_screen_on

;---------------------------------------------------------------------------------------
; Common setup for bitmap modes
;---------------------------------------------------------------------------------------
_ssm_finish_bitmap:
        jsr _ssm_setup_pointers

        ; Then set the correct $00/$01 pattern
        jsr clear_color_ram

        jsr init_bitmap
        
        lda #$00
        jsr clear_bitmap
        
        jmp _ssm_screen_on

;---------------------------------------------------------------------------------------
; Common setup for NCM modes
;---------------------------------------------------------------------------------------
_ssm_finish_ncm:
        jsr _ssm_setup_pointers

        ; Clear color RAM with NCM bit set, palette base 0
        lda #$00                ; Palette base 0 (colors 0-15)
        jsr clear_color_ram_ncm

        jsr init_ncm
        
        lda #$00                ; Clear to color 0
        jsr clear_ncm
        
        jmp _ssm_screen_on

;---------------------------------------------------------------------------------------
; Setup screen/color/char pointers (common to all FCM modes)
;---------------------------------------------------------------------------------------
_ssm_setup_pointers:
        ; [basic65c] first mode switch: capture the platform's own
        ; CHARPTR, all FOUR bytes -- $D06B (megabyte) included. The
        ; boot charset location differs between xemu and real
        ; hardware (the real machine's standard set lives in the char
        ; WOM at $FF7E000), so restoring a hardcoded $2D000 garbled
        ; the font on real machines while looking fine in xemu.
        lda chp_saved
        bne _ssm_chp_done
        lda $D068
        sta chp_save
        lda $D069
        sta chp_save+1
        lda $D06A
        sta chp_save+2
        lda $D06B
        sta chp_save+3
        lda #1
        sta chp_saved
_ssm_chp_done:
        ; Screen RAM pointer ([basic65c] per-mode: scrn_base)
        lda scrn_base
        sta VIC4_SCRNPTRLSB
        lda scrn_base+1
        sta VIC4_SCRNPTRMSB
        lda scrn_base+2
        sta VIC4_SCRBPTRBNK
        stz $D063

        ; Color RAM pointer
        lda #$00
        sta VIC4_COLPTRLSB
        sta VIC4_COLPTRMSB

        ; CHARPTR = $2D800 (ROM charset for PETSCII)
        lda #$00
        sta $D068
        lda #$d8
        sta $D069
        lda #$02
        sta $D06A
        
        rts

;---------------------------------------------------------------------------------------
; Enable screen display
;---------------------------------------------------------------------------------------
_ssm_screen_on:
        lda $D011
        ora #%00010000          ; Set DEN bit
        sta $D011
        rts

;---------------------------------------------------------------------------------------
; Disable screen display
;---------------------------------------------------------------------------------------
_ssm_screen_off:
        lda $D011
        and #%11101111          ; Clear DEN bit
        sta $D011
        rts

;---------------------------------------------------------------------------------------
; restore_default_screen - switching modes or returning to BASIC
;---------------------------------------------------------------------------------------
restore_default_screen:
        ; Enable VIC-IV
        lda #$47
        sta VIC4_KEY
        lda #$53
        sta VIC4_KEY

        ; Re-enable hot registers FIRST
        lda #$80
        tsb $D05D

        ; NOW disable FCM/SEAM (with hot registers on, write sticks)
        lda #$00
        sta VIC4_CTRL

        ; Restore VIC3_CTRL - clear ATTR, set H640
        lda VIC3_CTRL
        ora #%10000000
        and #%11011111
        sta VIC3_CTRL

        ; Restore LINESTEP
        lda #80
        sta VIC4_LINESTPLSB
        lda #0
        sta VIC4_LINESTPMSB

        ; Restore CHRCOUNT
        lda #80
        sta VIC4_CHRCOUNT

        ; Restore screen pointer to $0800
        lda #$00
        sta VIC4_SCRNPTRLSB
        lda #$08
        sta VIC4_SCRNPTRMSB
        lda #$00
        sta VIC4_SCRBPTRBNK
        stz $D063

        ; Restore DISPROWS
        lda #25
        sta VIC4_DISPROWS

        ; Restore text position
        lda #$50
        sta VIC4_TEXTXPOS
        lda #0
        sta VIC4_TEXTXPOS+1
        lda #$68
        sta VIC4_TEXTYPOS

        ; DMA: Reset color RAM
        lda #$00
        sta $D707
        .byte $80, $00
        .byte $81, $FF
        .byte $00
        .byte $03
        .word 5632
        .byte $05, $00
        .byte $00
        .word $0000
        .byte $08
        .byte $00
        .word $0000

        ; Restore palette
        jsr restore_default_palette

        ; CINT + clear screen
        jsr $FF81
        jsr $FF84

        ; [basic65c] put the CAPTURED boot CHARPTR back, all four
        ; bytes, AFTER CINT (whose hot-register writes recompute the
        ; charset pointer and would clobber an earlier restore).
        ; Falls back to the classic $02D000 if no mode switch ever
        ; saved one (cannot happen through this code path).
        lda chp_saved
        beq _rds_chp_rom
        lda chp_save
        sta $D068
        lda chp_save+1
        sta $D069
        lda chp_save+2
        sta $D06A
        lda chp_save+3
        sta $D06B
        bra _rds_colors
_rds_chp_rom:
        lda #$00
        sta $D068
        sta $D06B
        lda #$D0
        sta $D069
        lda #$02
        sta $D06A

_rds_colors:
        ; Restore default colors
        lda #$06
        sta BORDERCOL
        sta BACKCOL

        rts

chp_saved:
        .byte 0
chp_save:
        .byte 0, 0, 0, 0

;===========================================================================================
; sets the palette of colors
; $00 is always transparent
; $FF is special and is foreground color
;
;       $D100-$D1FF : red
;       $D200-$D2FF : green
;       $D300-$D3FF : blue
;
; load a color from $00-$FF into A
; then STA to the RGB color registers, 
; EXCEPT +$00 (always transparent) or +$FF (always color RAM foreground)
;===========================================================================================
init_palette:
        ; establish the color BLACK
        ; $AA is picked abritrarily to stand out in the character definition below
        lda #$00
        sta $D100+$AA           ; $AA in char data for RED is set to $00
        sta $D200+$AA           ; $AA in char data for RED is set to $00
        sta $D300+$AA           ; $AA in char data for RED is set to $00

        rts

;---------------------------------------------------------------------------------------
; restore_default_palette - Restore default C64/MEGA65 16-color palette
;---------------------------------------------------------------------------------------
restore_default_palette:
        ldx #0
_ssm_rp_loop:
        lda _ssm_rp_defaults,x
        jsr palette_nibble_to_byte
        sta $D100,x             ; Red
        lda _ssm_rp_defaults+16,x
        jsr palette_nibble_to_byte
        sta $D200,x             ; Green  
        lda _ssm_rp_defaults+32,x
        jsr palette_nibble_to_byte
        sta $D300,x             ; Blue
        inx
        cpx #16
        bne _ssm_rp_loop
        rts

_ssm_rp_defaults:
        ; Red channel
        .byte $00,$0F,$0F,$00,$0F,$00,$00,$0F
        .byte $0F,$0A,$0F,$05,$08,$09,$09,$0B
        ; Green channel
        .byte $00,$0F,$00,$0F,$00,$0F,$00,$0F
        .byte $06,$04,$07,$05,$08,$0F,$09,$0B
        ; Blue channel
        .byte $00,$0F,$00,$0F,$0F,$00,$0F,$00
        .byte $00,$00,$07,$05,$08,$09,$0F,$0B

;=======================================================================================
; set_palette_color - Set a single palette entry to an RGB color
; Input: A = palette index (0-255)
;        X = red (0-15)
;        Y = green (0-15)
;        Z = blue (0-15)
; Values are expanded to VIC-IV palette bytes: $0->$00, $8->$88, $F->$FF.
; Note: Index $00 is always transparent, $FF is always color RAM foreground
; Destroys: A
;=======================================================================================
set_palette_color:
        sta _spc_idx
        stx _spc_r
        sty _spc_g
        tza
        sta _spc_b
        ldx _spc_idx
        lda _spc_r
        jsr palette_nibble_to_byte
        sta $D100,x
        lda _spc_g
        jsr palette_nibble_to_byte
        sta $D200,x
        lda _spc_b
        jsr palette_nibble_to_byte
        sta $D300,x
        rts

_spc_idx: .byte 0
_spc_r:   .byte 0
_spc_g:   .byte 0
_spc_b:   .byte 0

;---------------------------------------------------------------------------------------
; palette_nibble_to_byte - Convert a 0-15 RGB component to VIC-IV byte format.
; Input: A = component nibble
; Output: A = repeated nibble ($0->$00, $F->$FF)
; Destroys: A
;---------------------------------------------------------------------------------------
palette_nibble_to_byte:
        and #$0F
        sta _pntb_tmp
        asl
        asl
        asl
        asl
        ora _pntb_tmp
        rts

_pntb_tmp: .byte 0

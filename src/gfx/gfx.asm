; ---------------------------------------------------------------------------
; Banked graphics blob for compiled BASIC65 programs.
;
; Assembled to run at $8000: rtinit reads the "GFX" file into bank 5
; ($50000-$53FFF) when a program uses graphics; each graphics call
; DMA-swaps the blob into CPU $8000-$BFFF (stashing the program bytes
; that live there in bank 5 $4000), dispatches through the jump table
; below, then swaps everything back -- the copy-back also preserves
; the state the library keeps inside itself (screen_mode etc.).
; No MAP is involved, so the KERNAL and its interrupt vectors stay
; put and IRQs keep running through long drawing calls.
;
; Drawing core: the vendored m65-fcm library (src/gfx/lib/), 256-colour
; FCM bitmap graphics. Pixel data lives in bank 4 ($40000+, claimed
; wholly by 320x200); FCM screen codes at bank 5 $8000-$87CF (bank-1
; low belongs to the C65 KERNAL/DOS -- README contract). PTR is repointed into the runtime's varptr slot
; ($F7-$FA) -- free during a graphics call; the resident gfxcall
; restores varptr's bank-1 invariant afterwards.
;
; The resident runtime stages arguments in dma_args (bank-0 absolutes,
; readable through the window; addresses generated into gfxshared.inc
; at build time) and passes the pen colour in gfx_pen.
; ---------------------------------------------------------------------------
        .cpu "45gs02"
        .enc "none"

; --- hardware equates (from m65-fcm src/main.asm) --------------------------
BORDERCOL               = $D020
BACKCOL                 = $D021
VIC4_KEY                = $D02F
VIC3_MMAP_CTRL          = $D030
VIC3_PAL_RAM_BIT        = $04           ; $D030 bit 2 = RAM palette for 0-15
VIC3_CTRL               = $D031
VIC4_CTRL               = $D054
VIC4_LINESTPLSB         = $D058
VIC4_LINESTPMSB         = $D059
VIC4_HOTREGS            = $D05D
VIC4_SCRNPTRLSB         = $D060
VIC4_SCRNPTRMSB         = $D061
VIC4_SCRBPTRBNK         = $D062
VIC4_COLPTRLSB          = $D064
VIC4_COLPTRMSB          = $D065
VIC4_TEXTXPOS           = $D04C
VIC4_TEXTYPOS           = $D04E
VIC4_CHRCOUNT           = $D05E
VIC4_DISPROWS           = $D07B

MULTINA                 = $D770         ; math unit: input A (32-bit)
MULTINB                 = $D774         ; input B (32-bit)
MULTOUT                 = $D778         ; multiply output (64-bit)
DIVOUT                  = $D768         ; divide output
DIVBUSY                 = $D70F         ; bit 7 = divider busy

MODE_BASIC              = 0
MODE_TEXT40             = 1
MODE_TEXT80             = 2
MODE_BITMAP40           = 3
MODE_BITMAP80           = 4
MODE_NCM40              = 5
MODE_NCM80              = 6

SCREEN_RAM              = $58000        ; FCM screen codes (bank 5, after
                                        ; blob $0000 + stash $4000; bank-1
                                        ; low is C65 KERNAL/DOS territory)
CHAR_DATA               = $40000        ; pixel data claims bank 4
CHAR_CODE_BASE          = $1000         ; $40000/64
PTR                     = $F7           ; the runtime's varptr slot

        .include "gfxshared.inc"

        * = $8000

        .word g_init            ; 0  GRAPHIC CLR
        .word g_close           ; 1  SCREEN CLOSE
        .word g_line            ; 2  LINE segment
        .word g_box             ; 3  BOX
        .word g_circle          ; 4  CIRCLE
        .word g_ellipse         ; 5  ELLIPSE
        .word g_paint           ; 6  PAINT
        .word g_palette         ; 7  PALETTE screen,c,r,g,b
        .word g_pixel           ; 8  PIXEL() read
        .word g_plot            ; 9  single-pixel LINE
        .word g_open            ; 10 SCREEN w,h,d
        .word g_palette4        ; 11 PALETTE COLOR c,r,g,b
        .word g_clear           ; 12 SCNCLR colour
        .word g_polygon         ; 13 POLYGON

; GRAPHIC CLR: reset the drawing context; the display is untouched
; until SCREEN opens it
g_init:
        lda #0
        sta gf_mode             ; flat fills
        lda #1                  ; default pen: white
        sta gfx_pen
        rts

; SCREEN [s,]w,h,d: the one supported shape is 320x200x256; opens the
; display with the default palette, black background, white pen
g_open:
        lda #MODE_BITMAP40
        jsr set_screen_mode     ; sets pointers, clears codes + bitmap
        jsr restore_default_palette
        lda #0
        sta gf_mode
        lda #1
        sta gfx_pen
        rts

g_close:
        jmp restore_default_screen

; SCNCLR colour: fill the whole bitmap with one colour
g_clear:
        lda dma_args+0
        jmp clear_bitmap

; POLYGON x,y,xrad,yrad,sides[,drawsides,subtend,angle,solid]: the
; library draws regular n-gons from one radius, so xrad rules and
; yrad/drawsides/subtend are ignored; the start angle arrives in
; degrees and becomes the library's 0-255 units via *182/256
g_polygon:
        lda dma_args+5
        ora dma_args+9
        beq _gpg_ok
        rts
_gpg_ok:
        lda dma_args+0
        sta poly_cx
        lda dma_args+1
        sta poly_cx+1
        lda dma_args+4
        sta poly_cy
        lda dma_args+8
        sta poly_r
        lda dma_args+16
        sta poly_sides
        lda gfx_pen
        sta poly_col
        lda #0
        sta poly_grad
        lda dma_args+28         ; angle: degrees * 182 / 256
        sta _gpg_a
        lda #0
        sta _gpg_hi
        ldx #8
        lda #0
_gpg_mul:
        asl a
        rol _gpg_hi
        asl _gpg_a
        bcc _gpg_next
        clc
        adc #182
        bcc _gpg_next
        inc _gpg_hi
_gpg_next:
        dex
        bne _gpg_mul
        lda _gpg_hi
        sta poly_angle
        lda dma_args+32         ; solid: nonzero fills (carry = fill)
        cmp #1
        jmp draw_polygon
_gpg_a:  .byte 0
_gpg_hi: .byte 0

; each drawing wrapper rejects calls whose 8-bit-consumed args
; (y coordinates, radii) arrive with a nonzero high byte -- the
; plot-level clip can't see the truncation
g_line:
        lda dma_args+5
        ora dma_args+13
        beq _gl_ok
        rts
_gl_ok:
        lda dma_args+0
        sta line_x0
        lda dma_args+1
        sta line_x0+1
        lda dma_args+4
        sta line_y0
        lda dma_args+8
        sta line_x1
        lda dma_args+9
        sta line_x1+1
        lda dma_args+12
        sta line_y1
        lda gfx_pen
        sta line_col
        jmp draw_line

g_plot:
        lda dma_args+5
        beq _gpl_ok
        rts
_gpl_ok:
        lda dma_args+0
        sta plot_x
        lda dma_args+1
        sta plot_x+1
        lda dma_args+4
        sta plot_y
        lda gfx_pen
        sta plot_col
        jmp plot_pixel

; BOX x0,y0,x2,y2[,solid]: two diagonally opposite corners in any
; order; the library wants origin + size
g_box:
        lda dma_args+5
        ora dma_args+13
        beq _gbx_ok
        rts
_gbx_ok:
        sec                     ; x: rect_x = min, rect_w = |dx|+1
        lda dma_args+8
        sbc dma_args+0
        sta rect_w
        lda dma_args+9
        sbc dma_args+1
        sta rect_w+1
        bcs _gb_xok             ; x2 >= x0
        sec
        lda dma_args+0
        sbc dma_args+8
        sta rect_w
        lda dma_args+1
        sbc dma_args+9
        sta rect_w+1
        lda dma_args+8
        sta rect_x
        lda dma_args+9
        sta rect_x+1
        bra _gb_xw
_gb_xok:
        lda dma_args+0
        sta rect_x
        lda dma_args+1
        sta rect_x+1
_gb_xw:
        inc rect_w
        bne _gb_y
        inc rect_w+1
_gb_y:
        sec                     ; y: rect_y = min, rect_h = |dy|+1
        lda dma_args+12
        sbc dma_args+4
        bcs _gb_yok
        eor #$ff                ; carry clear: adc #1 negates
        adc #1
        sta rect_h
        lda dma_args+12
        sta rect_y
        bra _gb_yw
_gb_yok:
        sta rect_h
        lda dma_args+4
        sta rect_y
_gb_yw:
        inc rect_h
        lda gfx_pen
        sta rect_col
        lda #0
        sta rect_grad
        lda dma_args+16         ; solid: nonzero fills (carry = fill)
        cmp #1
        jmp draw_rect

g_circle:
        lda dma_args+5
        ora dma_args+9
        beq _gc_ok
        rts
_gc_ok:
        lda dma_args+0
        sta circ_cx
        lda dma_args+1
        sta circ_cx+1
        lda dma_args+4
        sta circ_cy
        lda dma_args+8
        sta circ_r
        lda gfx_pen
        sta circ_col
        lda #0
        sta circ_grad
        lda dma_args+12         ; flags bit 0 = fill -> carry
        lsr a
        jmp draw_circle

g_ellipse:
        lda dma_args+5
        ora dma_args+9
        ora dma_args+13
        beq _ge_ok
        rts
_ge_ok:
        lda dma_args+0
        sta elip_cx
        lda dma_args+1
        sta elip_cx+1
        lda dma_args+4
        sta elip_cy
        lda dma_args+8
        sta elip_rx
        lda dma_args+12
        sta elip_ry
        lda gfx_pen
        sta elip_col
        lda #0
        sta elip_grad
        lda dma_args+16         ; flags bit 0 = fill -> carry
        lsr a
        jmp draw_ellipse

; PAINT x,y (mode 0 semantics): repaint the seed pixel's colour region
; with the pen colour
g_paint:
        lda dma_args+5
        beq _gpt_ok
        rts
_gpt_ok:
        lda dma_args+0
        sta plot_x
        lda dma_args+1
        sta plot_x+1
        lda dma_args+4
        sta plot_y
        jsr get_pixel
        cmp gfx_pen
        beq _gpt_done           ; already pen-coloured: nothing to do
        sta flood_target
        lda dma_args+0
        sta flood_x
        lda dma_args+1
        sta flood_x+1
        lda dma_args+4
        sta flood_y
        lda gfx_pen
        sta flood_color
        lda #1                  ; replace fill
        sta flood_mode
        jmp flood_fill
_gpt_done:
        rts

; PALETTE screen,c,r,g,b (the screen number is meaningless here)
g_palette:
        lda dma_args+8          ; red
        tax
        lda dma_args+12         ; green
        tay
        lda dma_args+16         ; blue
        taz
        lda dma_args+4          ; index
        jmp set_palette_color

; PALETTE COLOR c,r,g,b
g_palette4:
        lda dma_args+4          ; red
        tax
        lda dma_args+8          ; green
        tay
        lda dma_args+12         ; blue
        taz
        lda dma_args+0          ; index
        jmp set_palette_color

g_pixel:
        lda dma_args+5          ; aliased y: read as colour 0
        beq _gpx_ok
        lda #0
        sta gfxres
        rts
_gpx_ok:
        lda dma_args+0
        sta plot_x
        lda dma_args+1
        sta plot_x+1
        lda dma_args+4
        sta plot_y
        jsr get_pixel
        sta gfxres
        rts

        .include "lib/fcm.asm"
        .include "lib/bitmap.asm"
        .include "lib/gradient.asm"
        .include "lib/gradfill.asm"
        .include "lib/rectangle.asm"
        .include "lib/circle.asm"
        .include "lib/ellipse.asm"
        .include "lib/polygon.asm"
        .include "lib/floodfill.asm"

; text/NCM screen modes are unreachable (g_init only ever selects mode 3,
; 320x200 FCM bitmap); satisfy fcm.asm's references without vendoring
; text.asm/ncm.asm
clear_color_ram_text:
load_chars:
clear_color_ram_ncm:
init_ncm:
clear_ncm:
        rts

        .cerror * > $c000, "graphics blob exceeds the 16KB window"

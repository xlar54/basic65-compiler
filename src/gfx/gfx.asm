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

; FCM screen codes: 40-col at bank 5 $8000 (bank-1 low is C65
; KERNAL/DOS territory); 80-col at bank 0 $c000 because 640x200 pixel
; data claims all of banks 4+5 -- graphics programs cap at $c000.
; scrn_base (in fcm.asm) picks per mode.
SCREEN_RAM40            = $58000
SCREEN_RAM80            = $0c000
CHAR_DATA               = $40000        ; pixel data claims bank 4
CHAR_CODE_BASE          = $1000         ; $40000/64
PTR                     = $F7           ; the runtime's varptr slot

        .include "gfxshared.inc"

        * = $8000

; the drawing base: where plot/get/clear operate. $00040000 (bank 4,
; the displayed canvas) or an attic screen buffer ($810s0000). Fixed
; at the blob head so its offset never moves.
gfx_base:
        .byte $00, $00, $04, $00

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
        .word g_screenset       ; 14 SCREEN SET d,v
        .word g_screenopen      ; 15 SCREEN OPEN [s]
        .word g_screendef       ; 16 SCREEN DEF s,wf,hf,d
        .word g_simple4         ; 17 SCREEN s,w,h,d

; GRAPHIC CLR: reset the drawing context; the display is untouched
; until SCREEN opens it
g_init:
        lda #0
        sta gf_mode             ; flat fills
        lda #1                  ; default pen: white
        sta gfx_pen
        jmp gfx_rstscr

; reset screen state: draw = view = 0, base = the bank-4 canvas
gfx_rstscr:
        lda #0
        sta scr_draw
        sta scr_view
gfx_base4:
        lda #0
        sta gfx_base
        sta gfx_base+1
        sta gfx_base+3
        lda #$04
        sta gfx_base+2
        rts

; base = attic buffer of screen in A (0-3): $08100000 + s*$20000
; (128KB apart: a 640x200 canvas is $1f400 bytes)
gfx_basea:
        and #3
        asl a
        clc
        adc #$10
        sta gfx_base+2
        lda #0
        sta gfx_base
        sta gfx_base+1
        lda #$08
        sta gfx_base+3
        rts

; SCREEN w,h,d: 320x200 or 640x200 at 256 colours; opens the display
; with the default palette, black background, white pen
g_open:
        jsr gfx_rstscr
        lda dma_args+1          ; w high byte >= 2 selects 640
        ldx scr_view
        jsr gfx_setwf
gopencommon:
        ldx scr_view
        lda scr_wf,x
        bne _goc_80
        lda #MODE_BITMAP40
        bra _goc_set
_goc_80:
        lda #MODE_BITMAP80
_goc_set:
        jsr set_screen_mode     ; sets pointers, clears codes + bitmap
        jsr restore_default_palette
        lda #0                  ; FCM pixel value 0 is transparent and
        sta BACKCOL             ; shows $d021: the book says SCREEN
        sta gf_mode             ; sets the background to black
        lda #1                  ; (restore_default_screen puts the
        sta gfx_pen             ; boot blue back on CLOSE)
        rts

; A = w high byte, X = screen: record the width flag
gfx_setwf:
        cmp #2
        bcs _gsw_wide
        lda #0
        sta scr_wf,x
        rts
_gsw_wide:
        lda #1
        sta scr_wf,x
        rts

; SCREEN s,w,h,d: simplified form with an explicit screen number --
; that screen becomes both draw and view, on the bank-4 canvas
g_simple4:
        lda dma_args+0
        and #3
        sta scr_draw
        sta scr_view
        tax
        lda dma_args+5          ; w high byte
        jsr gfx_setwf
        jsr gfx_base4
        bra gopencommon

; SCREEN DEF s,wf,hf,depth: geometry bookkeeping only -- every screen
; renders as 320x200 FCM here (VIC-IV, not VIC-III bitplanes); depths
; 1-8 are a semantic superset of 256 colours
g_screendef:
        lda dma_args+0
        and #3
        tax
        lda dma_args+4
        sta scr_wf,x
        lda dma_args+8
        sta scr_hf,x
        lda dma_args+12
        sta scr_depth,x
        rts

; SCREEN OPEN [s]: clear the screen's attic buffer; if it is the
; viewed screen, clear the visible canvas too
g_screenopen:
        lda dma_args+0
        and #3
        pha
        jsr gsddstattic         ; fill attic buffer of screen A
        pla
        pha
        tax
        lda #0
        jsr gsdfill
        pla
        cmp scr_view
        bne _gso_done
        tax
        jsr gsddstb4
        lda #0
        jsr gsdfill
_gso_done:
        rts

; SCREEN SET d,v: classic double buffering. The attic buffers hold
; every screen's canvas; bank 4 is the display mirror of the viewed
; screen (and the live draw target when draw == view).
g_screenset:
        lda scr_draw            ; drawing was live on bank 4? sync it
        cmp scr_view            ; back to its attic buffer first
        bne _gss_pick
        lda scr_view
        jsr gsddstattic
        jsr gsdsrcb4
        ldx scr_view            ; old view's size
        jsr gsdcopy
_gss_pick:
        lda dma_args+4          ; show the new view screen
        and #3
        sta scr_view
        tax                     ; its recorded width may change the mode
        lda scr_wf,x
        beq _gss_want40
        lda screen_mode
        cmp #80
        beq _gss_show
        lda #MODE_BITMAP80
        jsr set_screen_mode
        bra _gss_show
_gss_want40:
        lda screen_mode
        cmp #80
        bne _gss_show
        lda #MODE_BITMAP40
        jsr set_screen_mode
_gss_show:
        lda scr_view
        jsr gsdsrcattic
        jsr gsddstb4
        ldx scr_view
        jsr gsdcopy
        lda dma_args+0          ; route drawing
        and #3
        sta scr_draw
        cmp scr_view
        bne _gss_attic
        jmp gfx_base4           ; draw == view: live on the canvas
_gss_attic:
        lda scr_draw
        jmp gfx_basea

; ---- 64000-byte screen DMA between bank 4 and the attic buffers ----
; enhanced F018B job; the list lives here in the blob (bank-0 RAM
; while executing)
gsdlist:
        .byte $0b
gsdsmb:
        .byte $80, $00          ; source megabyte
gsddmb:
        .byte $81, $00          ; dest megabyte
        .byte $00               ; end of options
gsdcmd:
        .byte $00               ; 0 copy / 3 fill
        .word 64000
gsdsrc:
        .byte $00, $00, $00
gsddst:
        .byte $00, $00, $00
        .byte $00
        .word 0

gsdsrcb4:
        lda #0
        sta gsdsmb+1
        sta gsdsrc
        sta gsdsrc+1
        lda #$04
        sta gsdsrc+2
        rts
gsddstb4:
        lda #0
        sta gsddmb+1
        sta gsddst
        sta gsddst+1
        lda #$04
        sta gsddst+2
        rts
gsdsrcattic:                    ; A = screen 0-3
        and #3
        asl a
        sta gsdsrc+2            ; bank-in-MB nibble: s*2
        lda #$81                ; $0810xxxx >> 20
        sta gsdsmb+1
        lda #0
        sta gsdsrc
        sta gsdsrc+1
        rts
gsddstattic:
        and #3
        asl a
        sta gsddst+2
        lda #$81
        sta gsddmb+1
        lda #0
        sta gsddst
        sta gsddst+1
        rts
; X = screen whose width flag sizes the transfer (bank-4 jobs follow
; the same screen's geometry)
gsdcopy:
        lda #0
        bra gsdgo
gsdfill:                        ; A = fill value (goes in src lo)
        sta gsdsrc
        lda #3
gsdgo:
        sta gsdcmd
        jsr _gsd_trigger
        lda scr_wf,x            ; wide canvas: second 64000-byte job
        beq _gsd_done           ; covering base+$fa00 on both sides
        lda gsdsrc+1
        pha
        lda gsddst+1
        pha
        lda gsdcmd
        cmp #3
        beq _gsd_fill2          ; fills keep src = value
        lda #$fa
        sta gsdsrc+1
_gsd_fill2:
        lda #$fa
        sta gsddst+1
        jsr _gsd_trigger
        pla
        sta gsddst+1
        pla
        sta gsdsrc+1
_gsd_done:
        rts
_gsd_trigger:
        lda #0
        sta $d702
        sta $d704
        lda #>gsdlist
        sta $d701
        lda #<gsdlist
        sta $d705
        rts

scr_draw:  .byte 0
scr_view:  .byte 0
scr_wf:    .byte 0,0,0,0
scr_hf:    .byte 0,0,0,0
scr_depth: .byte 0,0,0,0

; SCREEN CLOSE [s]: closing the viewed screen returns to text (with
; the palette restore inside restore_default_screen); closing a
; hidden screen just clears its definition
g_close:
        lda dma_args+0
        and #3
        cmp scr_view
        beq _gcl_view
        tax
        lda #0
        sta scr_wf,x
        rts
_gcl_view:
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
        lda dma_args+16         ; start/stop present? arc engine
        ora dma_args+17
        ora dma_args+20
        ora dma_args+21
        beq _gc_full
        lda dma_args+0
        sta arc_cx
        lda dma_args+1
        sta arc_cx+1
        lda dma_args+4
        sta arc_cy
        lda dma_args+8
        sta arc_xr
        sta arc_yr
        lda gfx_pen
        sta arc_col
        lda dma_args+12
        sta arc_flags
        lda dma_args+16
        sta arc_start
        lda dma_args+17
        sta arc_start+1
        lda dma_args+20
        sta arc_stop
        lda dma_args+21
        sta arc_stop+1
        jmp draw_arc
_gc_full:
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
        lda dma_args+20         ; start/stop present? arc engine
        ora dma_args+21
        ora dma_args+24
        ora dma_args+25
        beq _ge_full
        lda dma_args+0
        sta arc_cx
        lda dma_args+1
        sta arc_cx+1
        lda dma_args+4
        sta arc_cy
        lda dma_args+8
        sta arc_xr
        lda dma_args+12
        sta arc_yr
        lda gfx_pen
        sta arc_col
        lda dma_args+16
        sta arc_flags
        lda dma_args+20
        sta arc_start
        lda dma_args+21
        sta arc_start+1
        lda dma_args+24
        sta arc_stop
        lda dma_args+25
        sta arc_stop+1
        jmp draw_arc
_ge_full:
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
        .include "lib/arc.asm"
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

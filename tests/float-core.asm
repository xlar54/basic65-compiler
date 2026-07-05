; Standalone test for the MFLP float core: link against the runtime and run
; in the emulator, no compiler involved.
;
;   64tass --cbm-prg --m45gs02 src\runtime\runtime.asm tests\float-core.asm -o target\float-test.prg
;
; Expected output (printuint formatting: sign/space, value, trailing space):
;
;   5  7 -5  32700 -4  16385  0  1  255  1 -2  1234
;
; covering: fadd same-sign, fsub, negative same-sign add, large operands,
; different-sign borrow, exponent alignment, cancellation to zero, fcmp both
; ways, qint truncation of 3/2, floor of -3/2 (exponent decrement halves a
; float exactly), and a pack/unpack round trip through bank 1.

        * = $4000

        .word start
        .word $2100             ; varheapend: tiny heap, nothing uses it
        .word dataend           ; datastart (empty)
        .word dataend
        .word strroots

start:
; 2 + 3 = 5
        lda #2
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jsr fmovaf
        lda #3
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jsr fadd
        jsr qint
        jsr printuint

; 10 - 3 = 7
        lda #10
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jsr fmovaf
        lda #3
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jsr fsub
        jsr qint
        jsr printuint

; -2 + -3 = -5
        lda #<-2
        sta exprlo
        lda #>-2
        sta exprhi
        jsr float16
        jsr fmovaf
        lda #<-3
        sta exprlo
        lda #>-3
        sta exprhi
        jsr float16
        jsr fadd
        jsr qint
        jsr printuint

; 32000 + 700 = 32700
        lda #<32000
        sta exprlo
        lda #>32000
        sta exprhi
        jsr float16
        jsr fmovaf
        lda #<700
        sta exprlo
        lda #>700
        sta exprhi
        jsr float16
        jsr fadd
        jsr qint
        jsr printuint

; 5 - 9 = -4 (different signs, borrow path)
        lda #5
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jsr fmovaf
        lda #9
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jsr fsub
        jsr qint
        jsr printuint

; 16384 + 1 = 16385 (wide exponent alignment)
        lda #<16384
        sta exprlo
        lda #>16384
        sta exprhi
        jsr float16
        jsr fmovaf
        lda #1
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jsr fadd
        jsr qint
        jsr printuint

; 5 - 5 = 0 (cancellation must normalize to exact zero)
        lda #5
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jsr fmovaf
        lda #5
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jsr fsub
        jsr qint
        jsr printuint

; fcmp: FAC=5 vs ARG=3 -> 1
        lda #3
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jsr fmovaf
        lda #5
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jsr fcmp
        sta exprlo
        lda #0
        sta exprhi
        jsr printuint

; fcmp: FAC=3 vs ARG=5 -> $ff (prints as 255)
        lda #5
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jsr fmovaf
        lda #3
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jsr fcmp
        sta exprlo
        lda #0
        sta exprhi
        jsr printuint

; 3/2 = 1.5 via exponent decrement; qint floors positive -> 1
        lda #3
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        dec facexp
        jsr qint
        jsr printuint

; -3/2 = -1.5; floor -> -2 (interpreter INT() semantics)
        lda #<-3
        sta exprlo
        lda #>-3
        sta exprhi
        jsr float16
        dec facexp
        jsr qint
        jsr printuint

; pack/unpack round trip through bank 1 at $2100
        lda #<1234
        sta exprlo
        lda #>1234
        sta exprhi
        jsr float16
        lda #$00
        sta varptr
        lda #$21
        sta varptr+1
        ldz #0
        jsr fpack
        lda #0                  ; wipe FAC to prove funpack restores it
        sta facexp
        sta facm0
        sta facm1
        ldz #0
        jsr funpack
        jsr qint
        jsr printuint

        lda #$0d
        jsr printch
        jmp rtexit

dataend:
strroots:
        .byte 0, 0, 0, 0

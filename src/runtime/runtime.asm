;=======================================================================================
; runtime.asm -- BASIC65C generated-program runtime
;=======================================================================================
;
; This is the runtime library linked with every compiled program. It is real,
; standalone-assemblable source: 64tass assembles it together with the
; compiler-generated program text in one pass:
;
;   64tass --cbm-prg --m45gs02 src\runtime\runtime.asm target\out.asm.seq -o target\out.prg
;
; Memory contract:
;   $2001         BASIC stub (SYS 8210)
;   $2012         rtinit -- runtime entry, called by the stub
;   $2012-$5fff   runtime cap (actual program base is computed per build)
;   $5000         program header vectors, then the compiled program:
;                   progbase+0  .word start        (program entry)
;                   progbase+2  .word varheapend   (bank-1 clear limit)
;                   progbase+4  .word datastart    (DATA table start)
;                   progbase+6  .word dataend      (DATA table end)
;                   progbase+8  .word strroots     (string GC root table)
;                   progbase+10 .word fltinit      (float literal table)
;
; rtinit copies the header vectors into runtime variables, initializes the
; bank-1 variable heap, string heap, and DATA pointer, then jumps through the
; start vector. The runtime never references program symbols directly, so it
; can later ship as a fixed binary blob under the native code generator.
;
; Calling convention (generated code):
;   exprlo/exprhi   16-bit expression accumulator
;   lhslo/lhshi     left-hand operand scratch
;   varptr ($f7)    4-byte far pointer for [varptr],z bank-1 access
;   rtptr  ($fb)    runtime string/data pointer
;   comparisons return A=1 (true) / A=0 (false)
;
; Bank-1 layout:
;   $0000-$1fff    reserved (C65 KERNAL/DOS)
;   $2000          variable heap, grows up (descriptors 16 bytes, value at +8)
;   $f800          string heap one-past-top, grows down to varheapend
;   $f800-$ffff    reserved (color RAM mirror)
;=======================================================================================

        .cpu "45gs02"
        .enc "none"

kernalchrout = $ffd2
kernalchrin  = $ffcf
kernalscreen = $ffed
kernalplot   = $fff0
kernalgetin  = $ffe4
kernalrdtim  = $ffde
kernalvector = $ff8d
kernalload   = $ffd5
kernalsave   = $ffd8
kernalsetbnk = $ff6b
kernalsetlfs = $ffba
kernalsetnam = $ffbd
kernalopen   = $ffc0
kernalclose  = $ffc3
kernalchkin  = $ffc6
kernalchkout = $ffc9
kernalclrchn = $ffcc
kernalchrin2 = $ffcf
kernalreadst = $ffb7

varptr = $f7
rtptr  = $fb
rtfltptr = $fd

progbase     = $7000            ; standalone-assembly cap; generated programs compute rtpb
varheapstart = $2000
strheaptop   = $f800

;=======================================================================================
; BASIC stub - SYS 8210 ($2012)
;=======================================================================================

        * = $2001

        .word (+), 2026
        .byte $fe, $02, $30
        .byte ':'
        .byte $9e
        .text "8210"
        .byte 0
+       .word 0

;=======================================================================================
; Runtime init
;=======================================================================================

        * = $2012

rtinit:
        ldx #7                  ; the KERNAL editor keeps state in
_rtinit_zpsave:                 ; $f7-$fe, which the runtime borrows
        lda varptr,x            ; for its pointers; hand the editor's
        sta edzpsave,x          ; bytes back at rtexit (READY text
        dex                     ; went black without this)
        bpl _rtinit_zpsave
        lda #0                  ; the program header lives at rtpbhi<<8
        sta rtptr
        lda rtpbhi
        sta rtptr+1
        ldy #2
_rtinit_vecs:
        lda (rtptr),y
        sta rtvheapend-2,y
        iny
        cpy #16
        bne _rtinit_vecs
        jsr varinit
        jsr strinit
        jsr datainit
        ; select MEGA65 I/O mode so the math unit registers at $d768-$d77f
        ; are visible (idempotent under the MEGA65 ROM, which already runs
        ; in this mode)
        lda #$47
        sta $d02f
        lda #$53
        sta $d02f
        ; varptr always points into bank 1 for variable and string access;
        ; every runtime path preserves these two bytes, so generated code
        ; never has to set them (printscroll saves/restores around its use)
        lda #$01
        sta varptr+2
        lda #$00
        sta varptr+3
        lda #128
        sta cur_bank
        jsr strtreset
        ; bank the C65 BASIC and editor ROMs out of $8000-$cfff BEFORE
        ; fltinit: large programs keep their literal text above $8000, and
        ; reading it through the ROMs hands valflt garbage (zero or
        ; OVERFLOW floats, varying with ROM content). The KERNAL stays
        ; mapped at $e000; the bits are restored before returning to BASIC
        lda $d030
        sta rtd030save
        and #%11000111
        sta $d030
        jsr fltinit             ; convert float literals (needs the above)
        lda rtgfxflag           ; load the banked graphics blob (needs
        beq +                   ; rtd030save captured: gfxload toggles
        jsr gfxload             ; the ROMs around the KERNAL calls)
+
        lda $dc04               ; seed RND from the CIA timer
        sta rndseed
        eor #$b5
        sta rndseed+2
        lda $dc05
        sta rndseed+1
        eor #$2f
        sta rndseed+3
        tsx
        stx rtspsave
        jsr rtcallprog
        jsr rtsndshut
        lda rtd030save
        sta $d030
        rts
rtcallprog:
        lda #0
        sta rtptr
        lda rtpbhi
        sta rtptr+1
        ldy #0
        lda (rtptr),y
        sta rtjmp
        iny
        lda (rtptr),y
        sta rtjmp+1
        jmp (rtjmp)

; END/STOP from any GOSUB depth: unwind the stack to the pre-program mark,
; restore the ROM mapping, and return to the BASIC SYS caller
rtexit:
        jsr rtsndshut
        ldx rtspsave
        txs
        lda rtd030save
        sta $d030
        ldx #7
_rtexit_zprest:
        lda edzpsave,x
        sta varptr,x
        dex
        bpl _rtexit_zprest
        rts

;=======================================================================================
; Variable heap runtime
; bank-1 variable heap: $12000 up to varheapend (from program header)
; descriptor size 16 bytes; scalar value starts at descriptor + 8
; plain numeric slots: tag, low/reflo, high/refhi
;=======================================================================================

varinit:
        lda #<varheapstart
        sta varptr
        lda #>varheapstart
        sta varptr+1
        lda #$01
        sta varptr+2
        lda #0
        sta varptr+3
varinitloop:
        lda varptr+1
        cmp rtvheapend+1
        bne varinitclear
        lda varptr
        cmp rtvheapend
        beq varinitdone
varinitclear:
        lda #0
        ldz #0
        sta [varptr],z
        inc varptr
        bne varinitloop
        inc varptr+1
        jmp varinitloop
varinitdone:
        rts

loadintvar:
        ldz #0
        lda [varptr],z
        sta exprlo
        ldz #1
        lda [varptr],z
        sta exprhi
        rts

storeintvar:
        ldz #0
        lda exprlo
        sta [varptr],z
        ldz #1
        lda exprhi
        sta [varptr],z
        rts

;=======================================================================================
; Float literal pool conversion, run once by rtinit: the program header's
; sixth vector points at a table of {bank-1 slot address, literal text}
; word pairs (zero address terminates); each text converts through valflt
; and packs into its slot, so compiled code just funpacks a hidden variable.
;=======================================================================================

fltinit:
        lda rtfltinit
        sta rtfltptr
        lda rtfltinit+1
        sta rtfltptr+1
_fltinit_loop:
        ldy #0
        lda (rtfltptr),y
        iny
        ora (rtfltptr),y
        beq _fltinit_done
        ldy #2
        lda (rtfltptr),y
        sta rtptr
        iny
        lda (rtfltptr),y
        sta rtptr+1
        jsr valflt
        ldy #0
        lda (rtfltptr),y
        sta varptr
        iny
        lda (rtfltptr),y
        sta varptr+1
        ldz #0
        jsr fpack
        clc
        lda rtfltptr
        adc #4
        sta rtfltptr
        bcc _fltinit_loop
        inc rtfltptr+1
        bra _fltinit_loop
_fltinit_done:
        rts

;=======================================================================================
; MFLP floating point core (5-byte CBM format; see docs\floats-mflp.md)
;
; Unpacked accumulators FAC and ARG: exponent (excess-128, 0 means the value
; is zero), 4 mantissa bytes MSB-first with the leading 1 explicit in bit 7,
; sign ($00 positive / $ff negative), and a rounding extension byte.
; Packed memory form: exp, then mantissa MSB with bit 7 replaced by the sign.
;
; Conventions: fadd computes FAC = ARG + FAC, fsub computes FAC = ARG - FAC
; (left operand in ARG). fcmp returns A = 0 equal, 1 FAC > ARG, $ff FAC < ARG.
;=======================================================================================

; pack FAC into 5 bytes at [varptr]+Z .. Z+4 (Z preset by the caller)
fpack:
        lda facexp
        sta [varptr],z
        inz
        lda facm0
        and #$7f
        bit facsgn
        bpl +
        ora #$80
+       sta [varptr],z
        inz
        lda facm1
        sta [varptr],z
        inz
        lda facm2
        sta [varptr],z
        inz
        lda facm3
        sta [varptr],z
        rts

; unpack 5 bytes at [varptr]+Z .. Z+4 into FAC
funpack:
        lda [varptr],z
        sta facexp
        bne +
        lda #0
        sta facm0
        sta facm1
        sta facm2
        sta facm3
        sta facsgn
        sta facext
        rts
+       inz
        lda [varptr],z
        pha
        ora #$80
        sta facm0
        lda #0
        sta facsgn
        pla
        bpl +
        lda #$ff
        sta facsgn
+       inz
        lda [varptr],z
        sta facm1
        inz
        lda [varptr],z
        sta facm2
        inz
        lda [varptr],z
        sta facm3
        lda #0
        sta facext
        rts

; copy FAC to ARG / ARG to FAC
fmovaf:
        lda facexp
        sta argexp
        lda facm0
        sta argm0
        lda facm1
        sta argm1
        lda facm2
        sta argm2
        lda facm3
        sta argm3
        lda facsgn
        sta argsgn
        lda #0
        sta argext
        rts

fmovfa:
        lda argexp
        sta facexp
        lda argm0
        sta facm0
        lda argm1
        sta facm1
        lda argm2
        sta facm2
        lda argm3
        sta facm3
        lda argsgn
        sta facsgn
        lda #0
        sta facext
        rts

fswapfa:
        ldx facexp
        lda argexp
        sta facexp
        stx argexp
        ldx facm0
        lda argm0
        sta facm0
        stx argm0
        ldx facm1
        lda argm1
        sta facm1
        stx argm1
        ldx facm2
        lda argm2
        sta facm2
        stx argm2
        ldx facm3
        lda argm3
        sta facm3
        stx argm3
        ldx facsgn
        lda argsgn
        sta facsgn
        stx argsgn
        ldx facext
        lda argext
        sta facext
        stx argext
        rts

; signed 16-bit integer in exprlo/exprhi -> FAC
float16:
        lda #0
        sta facsgn
        sta facext
        sta facm2
        sta facm3
        lda exprlo
        ora exprhi
        bne +
        sta facexp
        rts
+       lda exprhi
        bpl _float16_pos
        lda #$ff
        sta facsgn
        sec
        lda #0
        sbc exprlo
        sta facm1
        lda #0
        sbc exprhi
        sta facm0
        bra _float16_norm
_float16_pos:
        lda exprlo
        sta facm1
        lda exprhi
        sta facm0
_float16_norm:
        lda #$90                ; 2^16 position
        sta facexp
        jmp fnorm

; FAC -> signed 16-bit integer in exprlo/exprhi with floor semantics
; (INT(-1.5) = -2, matching interpreted BASIC); |x| >= 32768 clamps
qint:
        lda facexp
        bne +
        lda #0
        sta exprlo
        sta exprhi
        rts
+       cmp #$81
        bcs _qint_big
        ; |x| < 1: floor gives 0 for positive, -1 for negative
        lda facsgn
        beq _qint_zero
        lda #$ff
        sta exprlo
        sta exprhi
        rts
_qint_zero:
        lda #0
        sta exprlo
        sta exprhi
        rts
_qint_big:
        lda facexp
        cmp #$91
        bcc +
        ; |x| >= 65536: clamp to the signed extreme
        lda facsgn
        bmi _qint_min
_qint_max:
        lda #$ff
        sta exprlo
        lda #$7f
        sta exprhi
        rts
_qint_min:
        lda #0
        sta exprlo
        lda #$80
        sta exprhi
        rts
+       ; shift the top 16 mantissa bits right ($90 - exp) places
        lda facm0
        sta exprhi
        lda facm1
        sta exprlo
        lda facm2
        ora facm3
        sta qint_lost
        lda #$90
        sec
        sbc facexp
        beq _qint_signed
        tax
_qint_shift:
        lsr exprhi
        ror exprlo
        bcc +
        lda #1
        ora qint_lost
        sta qint_lost
+       dex
        bne _qint_shift
_qint_signed:
        ; exp == $91 handled above; exp == $90 with bit15 set overflows the
        ; signed range except for exactly -32768
        lda exprhi
        bpl +
        lda facsgn
        beq _qint_max
        lda exprlo
        ora qint_lost
        bne _qint_min
        lda #0
        sta exprlo
        lda #$80
        sta exprhi
        rts
+       lda facsgn
        beq _qint_done
        ; negative: negate, then floor adjusts by -1 if bits were lost
        sec
        lda #0
        sbc exprlo
        sta exprlo
        lda #0
        sbc exprhi
        sta exprhi
        lda qint_lost
        beq _qint_done
        lda exprlo
        bne +
        dec exprhi
+       dec exprlo
_qint_done:
        rts

; normalize FAC (leading mantissa bit into bit 7), then round from the
; extension byte; a zero mantissa or exponent underflow yields exact zero
fnorm:
        lda facm0
        ora facm1
        ora facm2
        ora facm3
        ora facext
        bne _fnorm_loop
        sta facexp
        rts
_fnorm_loop:
        lda facm0
        bmi fround
        asl facext
        rol facm3
        rol facm2
        rol facm1
        rol facm0
        dec facexp
        bne _fnorm_loop
        ; exponent underflow: flush to zero
        lda #0
        sta facm0
        sta facm1
        sta facm2
        sta facm3
        sta facext
        sta facexp
        rts

fround:
        lda facext
        bpl _fround_clear
        inc facm3
        bne _fround_clear
        inc facm2
        bne _fround_clear
        inc facm1
        bne _fround_clear
        inc facm0
        bne _fround_clear
        ; mantissa wrapped: value reached the next power of two
        lda #$80
        sta facm0
        inc facexp
        beq fltoverflow
_fround_clear:
        lda #0
        sta facext
        rts

fltoverflow:
        lda #15
        jmp rterror

; FAC = ARG - FAC
fsub:
        lda facexp
        beq fadd
        lda facsgn
        eor #$ff
        sta facsgn
        ; FALLTHROUGH

; FAC = ARG + FAC
fadd:
        lda argexp
        bne +
        rts
+       lda facexp
        bne +
        jmp fmovfa
+       lda #0
        sta facext
        sta argext
        lda facexp
        cmp argexp
        bcs +
        jsr fswapfa
+       lda facexp
        sec
        sbc argexp
        beq _fadd_aligned
        cmp #32
        bcc +
        rts                     ; ARG is negligible against FAC
+       tax
_fadd_shift:
        lsr argm0
        ror argm1
        ror argm2
        ror argm3
        ror argext
        dex
        bne _fadd_shift
_fadd_aligned:
        lda facsgn
        cmp argsgn
        bne _fadd_diff
        clc
        lda facext
        adc argext
        sta facext
        lda facm3
        adc argm3
        sta facm3
        lda facm2
        adc argm2
        sta facm2
        lda facm1
        adc argm1
        sta facm1
        lda facm0
        adc argm0
        sta facm0
        bcc _fadd_done
        ror facm0
        ror facm1
        ror facm2
        ror facm3
        ror facext
        inc facexp
        beq _fadd_overflow
_fadd_done:
        jmp fround

_fadd_overflow:
        jmp fltoverflow

_fadd_diff:
        sec
        lda facext
        sbc argext
        sta facext
        lda facm3
        sbc argm3
        sta facm3
        lda facm2
        sbc argm2
        sta facm2
        lda facm1
        sbc argm1
        sta facm1
        lda facm0
        sbc argm0
        sta facm0
        bcs _fadd_norm
        ; borrow: ARG magnitude was larger, take its sign and negate
        lda argsgn
        sta facsgn
        sec
        lda #0
        sbc facext
        sta facext
        lda #0
        sbc facm3
        sta facm3
        lda #0
        sbc facm2
        sta facm2
        lda #0
        sbc facm1
        sta facm1
        lda #0
        sbc facm0
        sta facm0
_fadd_norm:
        jmp fnorm

; FAC = ARG * FAC, mantissa product from the MEGA65 hardware multiplier
; (MULTINA/MULTINB at $d770/$d774, 64-bit MULTOUT at $d778, MULBUSY in
; $d70f bit 6). rtinit selects MEGA65 I/O mode so these are visible.
fmul:
        lda facexp
        beq _fmul_zero
        lda argexp
        bne _fmul_go
_fmul_zero:
        jmp fzero
_fmul_go:
        ; exponent: e = facexp + argexp - 128; 0 or less underflows to zero,
        ; above 255 overflows
        lda facexp
        clc
        adc argexp
        bcs _fmul_e_high
        sec
        sbc #128
        bcc _fmul_zero          ; underflow
        beq _fmul_zero
        bra _fmul_e_done
_fmul_e_high:
        ; sum is 256..510: e = sum - 128 = low byte + 128
        clc
        adc #128
        bcs _fmul_overflow
_fmul_e_done:
        sta facexp
        lda facsgn
        eor argsgn
        sta facsgn
        lda facm3               ; inputs are little-endian
        sta $d770
        lda facm2
        sta $d771
        lda facm1
        sta $d772
        lda facm0
        sta $d773
        lda argm3
        sta $d774
        lda argm2
        sta $d775
        lda argm1
        sta $d776
        lda argm0
        sta $d777
-       bit $d70f               ; bit 6 = MULBUSY -> V
        bvs -
        lda $d77f               ; top 32 product bits are the new mantissa
        sta facm0
        lda $d77e
        sta facm1
        lda $d77d
        sta facm2
        lda $d77c
        sta facm3
        lda $d77b
        sta facext              ; next 8 bits round
        jmp fnorm

_fmul_overflow:
        jmp fltoverflow

; FAC = ARG / FAC via the hardware divider (DIVOUT at $d768: fraction in
; $d768-$d76b, whole part in $d76c-$d76f; DIVBUSY in $d70f bit 7)
fdiv:
        lda facexp
        bne +
        lda #20
        jmp rterror
+       lda argexp
        bne +
        jmp fzero               ; 0 / x = 0
+       ; e = argexp - facexp + 128; mantissa quotient lands in (0.5, 2)
        lda argexp
        sec
        sbc facexp
        bcs _fdiv_e_pos
        clc
        adc #128
        bcc _fdiv_underflow     ; difference beyond -128
        beq _fdiv_underflow
        bra _fdiv_e_done
_fdiv_e_pos:
        clc
        adc #128
        bcs _fdiv_overflow
_fdiv_e_done:
        sta facexp
        lda facsgn
        eor argsgn
        sta facsgn
        lda argm3               ; numerator = ARG
        sta $d770
        lda argm2
        sta $d771
        lda argm1
        sta $d772
        lda argm0
        sta $d773
        lda facm3               ; denominator = FAC
        sta $d774
        lda facm2
        sta $d775
        lda facm1
        sta $d776
        lda facm0
        sta $d777
-       bit $d70f               ; bit 7 = DIVBUSY -> N
        bmi -
        lda $d76c               ; whole part is 0 or 1 for our operand ranges
        beq _fdiv_frac
        inc facexp
        beq _fdiv_overflow
        lda $d76b               ; mantissa = (1.fraction) >> 1
        sec
        ror
        sta facm0
        lda $d76a
        ror
        sta facm1
        lda $d769
        ror
        sta facm2
        lda $d768
        ror
        sta facm3
        lda #0
        ror
        sta facext
        jmp fround
_fdiv_frac:
        lda $d76b
        sta facm0
        lda $d76a
        sta facm1
        lda $d769
        sta facm2
        lda $d768
        sta facm3
        lda #0
        sta facext
        jmp fnorm

_fdiv_underflow:
        jmp fzero

_fdiv_overflow:
        jmp fltoverflow

; software float stack (packed entries): every conversion and operation is
; free to clobber ARG, so a compiled left operand is parked here while the
; right side evaluates, then popped into ARG
fpush:
        ldx fltsp
        cpx #FLT_STACK_MAX * 5
        bcc +
        jmp fltoverflow
+       lda facexp
        sta fltstack,x
        lda facm0
        and #$7f
        bit facsgn
        bpl +
        ora #$80
+       sta fltstack+1,x
        lda facm1
        sta fltstack+2,x
        lda facm2
        sta fltstack+3,x
        lda facm3
        sta fltstack+4,x
        txa
        clc
        adc #5
        sta fltsp
        rts

fpoparg:
        lda fltsp
        sec
        sbc #5
        sta fltsp
        tax
        lda #0
        sta argext
        lda fltstack,x
        sta argexp
        bne +
        lda #0
        sta argm0
        sta argm1
        sta argm2
        sta argm3
        sta argsgn
        rts
+       lda fltstack+1,x
        pha
        ora #$80
        sta argm0
        lda #0
        sta argsgn
        pla
        bpl +
        lda #$ff
        sta argsgn
+       lda fltstack+2,x
        sta argm1
        lda fltstack+3,x
        sta argm2
        lda fltstack+4,x
        sta argm3
        rts

; float variable access: 5-byte MFLP at [varptr] (bank 1)
floadvar:
        ldz #0
        jmp funpack

fstorevar:
        ldz #0
        jmp fpack

; pop the float stack into FAC (rare; fpoparg is the common direction)
fpopfac:
        lda fltsp
        sec
        sbc #5
        sta fltsp
        tax
        lda #0
        sta facext
        lda fltstack,x
        sta facexp
        bne +
        lda #0
        sta facm0
        sta facm1
        sta facm2
        sta facm3
        sta facsgn
        rts
+       lda fltstack+1,x
        pha
        ora #$80
        sta facm0
        lda #0
        sta facsgn
        pla
        bpl +
        lda #$ff
        sta facsgn
+       lda fltstack+2,x
        sta facm1
        lda fltstack+3,x
        sta facm2
        lda fltstack+4,x
        sta facm3
        rts

; promote the 16-bit integer in lhslo/lhshi to a float in ARG, preserving FAC
fpromotelhs:
        jsr fpush
        lda lhslo
        sta exprlo
        lda lhshi
        sta exprhi
        jsr float16
        jsr fmovaf
        jmp fpopfac

; unary and function helpers on FAC
fneg:
        lda facexp
        beq +
        lda facsgn
        eor #$ff
        sta facsgn
+       rts

fabsf:
        lda #0
        sta facsgn
        rts

fsgnf:
        lda facexp
        beq +
        lda facsgn
        pha
        lda #1
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        pla
        sta facsgn
+       rts

fintf:
        jsr qint
        jmp float16

; FAC as a boolean into exprlo/exprhi (1 nonzero, 0 zero)
ftruth:
        ldx #0
        lda facexp
        beq +
        inx
+       stx exprlo
        lda #0
        sta exprhi
        rts

; float comparison wrappers: FAC = right operand, ARG = left operand
; (fcmp: 0 equal, 1 FAC > ARG, $ff FAC < ARG); boolean into exprlo/exprhi
fcmpeqb:
        jsr fcmp
        cmp #0
        beq fcbtrue
        bra fcbfalse
fcmpneb:
        jsr fcmp
        cmp #0
        bne fcbtrue
        bra fcbfalse
fcmpltb:
        jsr fcmp
        cmp #1                  ; left < right means FAC (right) > ARG (left)
        beq fcbtrue
        bra fcbfalse
fcmpleb:
        jsr fcmp
        cmp #$ff
        bne fcbtrue
        bra fcbfalse
fcmpgtb:
        jsr fcmp
        cmp #$ff                ; left > right means FAC (right) < ARG (left)
        beq fcbtrue
        bra fcbfalse
fcmpgeb:
        jsr fcmp
        cmp #1
        bne fcbtrue
fcbfalse:
        lda #0
        bra fcbstore
fcbtrue:
        lda #1
fcbstore:
        sta exprlo
        lda #0
        sta exprhi
        rts

fzero:
        lda #0
        sta facexp
        sta facm0
        sta facm1
        sta facm2
        sta facm3
        sta facsgn
        sta facext
        rts


; compare FAC with ARG: A = 0 equal, 1 FAC > ARG, $ff FAC < ARG
fcmp:
        lda facexp
        bne +
        lda argexp
        bne _fcmp_fac_zero
        lda #0
        rts
_fcmp_fac_zero:
        lda argsgn
        bmi _fcmp_gt
        bra _fcmp_lt
+       lda argexp
        bne +
        lda facsgn
        bmi _fcmp_lt
        bra _fcmp_gt
+       lda facsgn
        cmp argsgn
        beq _fcmp_same_sign
        lda facsgn
        bmi _fcmp_lt
        bra _fcmp_gt
_fcmp_same_sign:
        lda facexp
        cmp argexp
        bne _fcmp_mag
        lda facm0
        cmp argm0
        bne _fcmp_mag
        lda facm1
        cmp argm1
        bne _fcmp_mag
        lda facm2
        cmp argm2
        bne _fcmp_mag
        lda facm3
        cmp argm3
        bne _fcmp_mag
        lda #0
        rts
_fcmp_mag:
        ; carry set here means FAC magnitude >= ARG magnitude (and not equal)
        bcc _fcmp_mag_lt
        lda facsgn
        bmi _fcmp_lt            ; larger magnitude but negative -> smaller
        bra _fcmp_gt
_fcmp_mag_lt:
        lda facsgn
        bmi _fcmp_gt
        bra _fcmp_lt
_fcmp_gt:
        lda #1
        rts
_fcmp_lt:
        lda #$ff
        rts

;=======================================================================================
; MFLP text conversion: FAC*10, FAC/10, valflt (parse), printflt (format)
;=======================================================================================

; hardwired unpacked constants (ARG or FAC)
fldarg_ten:
        lda #$84
        sta argexp
        lda #$a0
        sta argm0
        lda #0
        sta argm1
        sta argm2
        sta argm3
        sta argsgn
        sta argext
        rts

fldarg_1e8:
        lda #$9b
        sta argexp
        lda #$be
        sta argm0
        lda #$bc
        sta argm1
        lda #$20
        sta argm2
        lda #0
        sta argm3
        sta argsgn
        sta argext
        rts

fldarg_1e9:
        lda #$9e
        sta argexp
        lda #$ee
        sta argm0
        lda #$6b
        sta argm1
        lda #$28
        sta argm2
        lda #0
        sta argm3
        sta argsgn
        sta argext
        rts

fldarg_half:
        lda #$80
        sta argexp
        sta argm0
        lda #0
        sta argm1
        sta argm2
        sta argm3
        sta argsgn
        sta argext
        rts

fmul10:
        jsr fldarg_ten
        jmp fmul

fdiv10:
        jsr fmovaf              ; ARG = x
        lda #$84                ; FAC = 10
        sta facexp
        lda #$a0
        sta facm0
        lda #0
        sta facm1
        sta facm2
        sta facm3
        sta facsgn
        sta facext
        jmp fdiv                ; FAC = ARG / FAC = x / 10

; parse a zero-terminated decimal number at (rtptr) into FAC:
; [spaces][+|-][digits][.digits][e|E[+|-]digits]; stops at any other char
valflt:
        jsr fzero
        ldy #0
        sty vflt_sign
        sty vflt_decexp
        sty vflt_frac
        sty vflt_eexp
        sty vflt_esign
_vf_skip:
        lda (rtptr),y
        cmp #' '
        bne +
        iny
        bra _vf_skip
+       cmp #'-'
        bne +
        lda #$ff
        sta vflt_sign
        iny
        bra _vf_digits
+       cmp #'+'
        bne _vf_digits
        iny
_vf_digits:
        lda (rtptr),y
        beq _vf_scale
        cmp #'.'
        beq _vf_point
        cmp #$65                ; ASCII 'e'
        beq _vf_exp
        cmp #$45                ; PETSCII 'e' / 'E' (compiled literal pools)
        beq _vf_exp
        cmp #'0'
        bcc _vf_scale
        cmp #'9' + 1
        bcs _vf_scale
        sec
        sbc #'0'
        sta vflt_digit
        sty vflt_y
        jsr fmul10
        jsr fmovaf
        lda vflt_digit
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jsr fadd
        ldy vflt_y
        lda vflt_frac
        beq +
        inc vflt_decexp
+       iny
        bra _vf_digits
_vf_point:
        lda #1
        sta vflt_frac
        iny
        bra _vf_digits
_vf_exp:
        iny
        lda (rtptr),y
        cmp #'-'
        bne +
        lda #1
        sta vflt_esign
        iny
        bra _vf_exp_dig
+       cmp #'+'
        bne _vf_exp_dig
        iny
_vf_exp_dig:
        lda (rtptr),y
        cmp #'0'
        bcc _vf_scale
        cmp #'9' + 1
        bcs _vf_scale
        pha
        lda vflt_eexp           ; eexp = eexp*10 + digit
        asl
        asl
        clc
        adc vflt_eexp
        asl
        sta vflt_eexp
        pla
        sec
        sbc #'0'
        clc
        adc vflt_eexp
        sta vflt_eexp
        iny
        bra _vf_exp_dig
_vf_scale:
        lda vflt_eexp
        ldx vflt_esign
        beq +
        eor #$ff
        clc
        adc #1
+       sec
        sbc vflt_decexp
        sta vflt_scale
_vf_apply:
        lda vflt_scale
        beq _vf_sign
        bmi _vf_down
        jsr fmul10
        dec vflt_scale
        bra _vf_apply
_vf_down:
        jsr fdiv10
        inc vflt_scale
        bra _vf_apply
_vf_sign:
        lda facexp
        beq +
        lda vflt_sign
        bpl +
        sta facsgn
+       rts

; print FAC in BASIC style: sign space/minus, up to nine significant digits
; with the point placed by the decimal exponent, E notation outside
; .01 <= |x| < 1e9 (approximately CBM FOUT behavior), trailing space
printflt:
        lda facexp
        bne +
        lda #' '
        jsr printch
        lda #'0'
        jsr printch
        lda #' '
        jmp printch
+       lda facsgn
        bpl _pf_sign_pos
        lda #0
        sta facsgn
        lda #'-'
        jsr printch
        bra _pf_scaled
_pf_sign_pos:
        lda #' '
        jsr printch
_pf_scaled:
        lda #0
        sta fout_dexp
_pf_scale_up:
        jsr fldarg_1e8
        jsr fcmp
        cmp #$ff                ; FAC < 1e8: bring a digit in
        bne _pf_scale_down
        jsr fmul10
        dec fout_dexp
        bra _pf_scale_up
_pf_scale_down:
        jsr fldarg_1e9
        jsr fcmp
        cmp #$ff                ; FAC < 1e9: scaled
        beq _pf_round
        jsr fdiv10
        inc fout_dexp
        bra _pf_scale_down
_pf_round:
        jsr fldarg_half         ; round the ninth digit
        jsr fadd
        jsr fldarg_1e9
        jsr fcmp
        cmp #$ff
        beq _pf_int
        jsr fdiv10
        inc fout_dexp
_pf_int:
        ; 32-bit integer from the scaled FAC (exponent is $9b..$9e here)
        lda facm0
        sta fout_val0
        lda facm1
        sta fout_val1
        lda facm2
        sta fout_val2
        lda facm3
        sta fout_val3
        lda #$a0
        sec
        sbc facexp
        beq _pf_digits
        tax
_pf_shift:
        lsr fout_val0
        ror fout_val1
        ror fout_val2
        ror fout_val3
        dex
        bne _pf_shift
_pf_digits:
        ldx #0
        stx fout_idx
_pf_dig_loop:
        lda #'0'
        sta fout_digit
_pf_dig_sub:
        lda fout_val0
        cmp pf_pow0,x
        bcc _pf_dig_store
        bne _pf_dig_take
        lda fout_val1
        cmp pf_pow1,x
        bcc _pf_dig_store
        bne _pf_dig_take
        lda fout_val2
        cmp pf_pow2,x
        bcc _pf_dig_store
        bne _pf_dig_take
        lda fout_val3
        cmp pf_pow3,x
        bcc _pf_dig_store
_pf_dig_take:
        sec
        lda fout_val3
        sbc pf_pow3,x
        sta fout_val3
        lda fout_val2
        sbc pf_pow2,x
        sta fout_val2
        lda fout_val1
        sbc pf_pow1,x
        sta fout_val1
        lda fout_val0
        sbc pf_pow0,x
        sta fout_val0
        inc fout_digit
        bra _pf_dig_sub
_pf_dig_store:
        ldy fout_idx
        lda fout_digit
        sta fout_buf,y
        inc fout_idx
        inx
        cpx #9
        bne _pf_dig_loop
        ; p = digits before the decimal point
        lda fout_dexp
        clc
        adc #9
        sta fout_p
        bmi _pf_check_m1
        beq _pf_p_zero
        cmp #10
        bcc _pf_fixed
        jmp _pf_e
_pf_check_m1:
        cmp #$ff
        beq _pf_p_m1
        jmp _pf_e

_pf_fixed:
        ; digits, point after position p, fraction trimmed of trailing zeros
        jsr _pf_trim
        ldy #0
_pf_fix_int:
        cpy fout_p
        beq _pf_fix_frac
        lda fout_buf,y
        jsr printch
        iny
        bra _pf_fix_int
_pf_fix_frac:
        lda fout_last
        cmp fout_p
        bcc _pf_space           ; nothing after the point
        lda #'.'
        jsr printch
_pf_fix_floop:
        lda fout_buf,y
        jsr printch
        iny
        cpy fout_last
        bcc _pf_fix_floop
        beq _pf_fix_floop
        bra _pf_space

_pf_p_zero:
        jsr _pf_trim
        lda #'.'
        jsr printch
        ldy #0
        bra _pf_frac_out

_pf_p_m1:
        jsr _pf_trim
        lda #'.'
        jsr printch
        lda #'0'
        jsr printch
        ldy #0
_pf_frac_out:
        lda fout_buf,y
        jsr printch
        iny
        cpy fout_last
        bcc _pf_frac_out
        beq _pf_frac_out
        bra _pf_space

_pf_e:
        ; d.dddddddd E +/- exponent (p-1)
        jsr _pf_trim
        lda fout_buf
        jsr printch
        lda fout_last
        beq _pf_e_mark
        lda #'.'
        jsr printch
        ldy #1
_pf_e_frac:
        lda fout_buf,y
        jsr printch
        iny
        cpy fout_last
        bcc _pf_e_frac
        beq _pf_e_frac
_pf_e_mark:
        lda #$45                ; 'E'
        jsr printch
        lda fout_p
        sec
        sbc #1
        bpl _pf_e_plus
        eor #$ff
        clc
        adc #1
        sta fout_digit
        lda #'-'
        jsr printch
        bra _pf_e_num
_pf_e_plus:
        sta fout_digit
        lda #'+'
        jsr printch
_pf_e_num:
        lda #'0'
        sta fout_p              ; reuse as tens digit
_pf_e_tens:
        lda fout_digit
        cmp #10
        bcc _pf_e_out
        sbc #10
        sta fout_digit
        inc fout_p
        bra _pf_e_tens
_pf_e_out:
        lda fout_p
        jsr printch
        lda fout_digit
        clc
        adc #'0'
        jsr printch

_pf_space:
        lda #' '
        jmp printch

; find the last significant digit index (trailing-zero trim, never trims
; the leading digit)
_pf_trim:
        ldy #8
_pf_trim_loop:
        lda fout_buf,y
        cmp #'0'
        bne _pf_trim_done
        dey
        bne _pf_trim_loop
_pf_trim_done:
        sty fout_last
        rts

; 32-bit powers of ten, MSB first, for nine-digit extraction
pf_pow0:
        .byte $05,$00,$00,$00,$00,$00,$00,$00,$00
pf_pow1:
        .byte $f5,$98,$0f,$01,$00,$00,$00,$00,$00
pf_pow2:
        .byte $e1,$96,$42,$86,$27,$03,$00,$00,$00
pf_pow3:
        .byte $00,$80,$40,$a0,$10,$e8,$64,$0a,$01


;=======================================================================================
; File I/O layer: OPEN/CLOSE/PRINT#/INPUT#/GET#/ST. Channels are selected
; only around file operations; fio_out routes printch straight to CHROUT.
;=======================================================================================

; map the ROMs in/out around KERNAL file calls (A preserved)
fio_rom_on:
        pha
        lda rtd030save
        sta $d030
        pla
        rts

fio_rom_off:
        pha
        lda rtd030save
        and #%11000111
        sta $d030
        pla
        rts

;=======================================================================================
; Runtime error dispatch: A = CBM error code. With a TRAP armed, the stack
; unwinds to the program mark and control transfers to the handler line
; (the trap disarms; the handler re-arms with TRAP if desired). Untrapped
; errors print their message and halt like interpreted BASIC.
;=======================================================================================

rterror:
        pha                     ; strtreset clobbers the error code
        jsr strtreset
        pla
        sta rt_er
        lda curline             ; latch the erroring line for EL
        sta rt_el
        lda curline+1
        sta rt_el+1
        lda traplo
        ora traphi
        beq _rterror_halt
        lda traplo
        sta rtjmp
        lda traphi
        sta rtjmp+1
        lda #0                  ; disarm while the handler runs
        sta traplo
        sta traphi
        ldx rtspsave
        txs
        jmp (rtjmp)

_rterror_halt:
        ldx #0
_rterror_scan:
        lda rterrtab,x
        beq _rterror_msgdone
        cmp rt_er
        beq _rterror_found
        inx
        inx
        inx
        bra _rterror_scan
_rterror_found:
        lda rterrtab+1,x
        sta rtptr
        lda rterrtab+2,x
        sta rtptr+1
        jsr printstr
        lda #$0d
        jsr printch
_rterror_msgdone:
        jmp rtexit

; code, message pointer pairs (0 ends)
rterrtab:
        .byte 13
        .word odm
        .byte 15
        .word ovm
        .byte 16
        .word osm
        .byte 18
        .word abm
        .byte 20
        .word dzm
        .byte 22
        .word tmm
        .byte 0

ovm:
        .byte $4f,$56,$45,$52,$46,$4c,$4f,$57,$00
osm:
        .byte $4f,$55,$54,$20,$4f,$46,$20,$53,$54,$52,$49,$4e,$47,$00
abm:
        .byte $41,$52,$52,$41,$59,$20,$42,$4f,$55,$4e,$44,$53,$00
dzm:
        .byte $44,$49,$56,$49,$53,$49,$4f,$4e,$20,$42,$59,$20,$5a,$45,$52,$4f,$00

trapoff:
        lda #0
        sta traplo
        sta traphi
        rts

trapresume:
        lda #0
        sta rt_er
        rts

; ER and EL
rder:
        lda rt_er
        sta exprlo
        lda #0
        sta exprhi
        rts

rdel:
        lda rt_el
        sta exprlo
        lda rt_el+1
        sta exprhi
        rts

; DECBIN(s$): binary text to number, stops at the first non-binary char
decbinf:
        lda #0
        sta bin_v
        sta bin_v+1
        lda exprlo
        ora exprhi
        beq _decbin_done
        jsr setstrptrexpr
        ldz #0
        lda [varptr],z
        sta bin_n
        lda #0
        sta bin_j
_decbin_loop:
        lda bin_j
        cmp bin_n
        beq _decbin_done
        inc bin_j
        ldz bin_j
        lda [varptr],z
        cmp #$30                ; 0
        beq _decbin_shift
        cmp #$31                ; 1
        bne _decbin_done
        asl bin_v
        rol bin_v+1
        inc bin_v
        bra _decbin_loop
_decbin_shift:
        asl bin_v
        rol bin_v+1
        bra _decbin_loop
_decbin_done:
        lda bin_v
        sta exprlo
        lda bin_v+1
        sta exprhi
        rts

; STRBIN$(n): the low byte as eight binary digits on the string heap
strbinf:
        lda exprlo
        sta bin_v
        lda #8
        sta strlen
        jsr stralloc
        bcs _strbin_done
        ldz #0
        lda #8
        sta [varptr],z
        ldy #8
_strbin_loop:
        lda #$30
        asl bin_v
        adc #0                  ; carry from the shifted-out bit
        inz
        sta [varptr],z
        dey
        bne _strbin_loop
_strbin_done:
        rts

usrf:
        lda exprlo
        ldy exprhi
        jsr _usrjmp
        sta exprlo
        sty exprhi
        rts
_usrjmp:
        jmp ($02f8)

; TI: seconds since CLR TI as a float (BASIC65 semantics; jiffy
; granularity here, not the ROM timer's microseconds)
rdti:
        jsr kernalrdtim         ; A = low, X = mid, Y = high
        sec
        sbc ti_base
        sta ti_j
        txa
        sbc ti_base+1
        sta ti_j+1
        tya
        sbc ti_base+2
        tay
        lda ti_j
        ldx ti_j+1
        jsr rdti24              ; FAC = jiffy delta from A/X/Y
        jsr fpush
        lda #50                 ; PAL 50 jiffies/second, NTSC 60
        sta exprlo
        lda $d06f
        bpl +
        lda #60
        sta exprlo
+       lda #0
        sta exprhi
        jsr float16
        jsr fpoparg
        jmp fdiv                ; seconds = jiffies / rate

; TI$: read the RTC at $ffd7110 (BCD ss,mm,hh) into "hh:mm:ss" on the
; string heap; varptr's bank-1 invariant is saved around the far read
tistr:
        lda varptr+2
        pha
        lda #$10
        sta varptr
        lda #$71
        sta varptr+1
        lda #$fd
        sta varptr+2
        lda #$0f
        sta varptr+3
        ldz #0
        lda [varptr],z
        sta ti_ss
        inz
        lda [varptr],z
        sta ti_mm
        inz
        lda [varptr],z
        and #$7f                ; strip the 24h mode flag
        sta ti_hh
        pla
        sta varptr+2
        lda #0
        sta varptr+3
        lda #8
        sta strlen
        jsr stralloc
        bcs _tistr_done
        ldz #0
        lda #8
        sta [varptr],z
        lda ti_hh
        jsr _tistr_bcd
        lda #$3a                ; colon
        inz
        sta [varptr],z
        lda ti_mm
        jsr _tistr_bcd
        lda #$3a
        inz
        sta [varptr],z
        lda ti_ss
        jsr _tistr_bcd
_tistr_done:
        rts

_tistr_bcd:
        pha
        lsr a
        lsr a
        lsr a
        lsr a
        ora #$30
        inz
        sta [varptr],z
        pla
        and #$0f
        ora #$30
        inz
        sta [varptr],z
        rts

clrti:
        jsr kernalrdtim
        sta ti_base
        stx ti_base+1
        sty ti_base+2
        rts

rdti24:
        sta ti_lo
        stx exprlo
        sty exprhi
        jsr float16             ; high 16 bits (always < $8000)
        lda facexp
        beq +
        clc
        adc #8                  ; * 256
        sta facexp
+       jsr fmovaf
        lda ti_lo
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jmp fadd

; CLR: clear variables, string heap, DATA pointer; reconvert float
; literals (their slots live in the variable heap)
rtclr:
        jsr varinit
        jsr strinit
        jsr datainit
        jmp fltinit

; HEX$(n): four uppercase hex digits as a fresh heap string
hexstr:
        lda exprlo              ; stralloc returns through exprlo/exprhi
        sta hex_val
        lda exprhi
        sta hex_val+1
        lda #4
        sta strlen
        jsr stralloc
        bcs _hexstr_done
        ldz #0
        lda #4
        sta [varptr],z
        lda hex_val+1
        lsr
        lsr
        lsr
        lsr
        ldz #1
        jsr _hexstr_digit
        lda hex_val+1
        and #$0f
        ldz #2
        jsr _hexstr_digit
        lda hex_val
        lsr
        lsr
        lsr
        lsr
        ldz #3
        jsr _hexstr_digit
        lda hex_val
        and #$0f
        ldz #4
        jsr _hexstr_digit
        lda strdstlo
        sta exprlo
        lda strdsthi
        sta exprhi
_hexstr_done:
        rts
_hexstr_digit:
        cmp #10
        bcc +
        clc
        adc #$41 - 10 - '0'     ; A-F
+       clc
        adc #'0'
        sta [varptr],z
        rts

; DEC(h$): hex string to integer (stops at the first non-hex character)
decstr:
        lda exprlo
        ora exprhi
        beq _decstr_zero
        jsr setstrptrexpr
        ldz #0
        lda [varptr],z
        sta strlen
        lda #0
        sta exprlo
        sta exprhi
        sta stridx
_decstr_loop:
        lda stridx
        cmp strlen
        bcs _decstr_done
        inc stridx
        ldz stridx
        lda [varptr],z
        cmp #'0'
        bcc _decstr_done
        cmp #'9' + 1
        bcc _decstr_dig
        cmp #$41                ; A-F
        bcc _decstr_done
        cmp #$47
        bcs _decstr_done
        sbc #6                  ; carry clear: A ($41) -> $3a
_decstr_dig:
        sec
        sbc #'0'
        asl exprlo              ; value = value*16 + digit
        rol exprhi
        asl exprlo
        rol exprhi
        asl exprlo
        rol exprhi
        asl exprlo
        rol exprhi
        ora exprlo
        sta exprlo
        bra _decstr_loop
_decstr_done:
        rts
_decstr_zero:
        lda #0
        sta exprlo
        sta exprhi
        rts

; INSTR(hay$, needle$): 1-based position of needle in hay, 0 if absent;
; hay ref in lhslo/lhshi, needle ref in exprlo/exprhi (both heap strings)
instrf:
        lda lhslo
        sta strsrc1lo
        lda lhshi
        sta strsrc1hi
        lda exprlo
        sta strsrc2lo
        lda exprhi
        sta strsrc2hi
        jsr strlen1load         ; hay length
        jsr strlen2load         ; needle length
        lda strlen2
        beq _instr_zero         ; empty needle: 0 (interpreter gives 1)
        lda #0
        sta instr_pos
_instr_outer:
        ; positions run 0 .. len1 - len2
        lda instr_pos
        clc
        adc strlen2
        bcs _instr_zero
        cmp strlen1
        beq _instr_try
        bcs _instr_zero
_instr_try:
        lda #0
        sta stridx
_instr_inner:
        lda stridx
        cmp strlen2
        beq _instr_found
        lda instr_pos
        sec
        adc stridx              ; +1 for the length byte (carry set)
        taz
        jsr setstrptrsrc1
        lda [varptr],z
        sta strcmpchar
        lda stridx
        clc
        adc #1
        taz
        jsr setstrptrsrc2
        lda [varptr],z
        cmp strcmpchar
        bne _instr_next
        inc stridx
        bra _instr_inner
_instr_next:
        inc instr_pos
        bne _instr_outer
_instr_zero:
        lda #0
        sta exprlo
        sta exprhi
        rts
_instr_found:
        lda instr_pos
        clc
        adc #1                  ; 1-based
        sta exprlo
        lda #0
        sta exprhi
        rts

;=======================================================================================
; Integer math runtime
;=======================================================================================

mul16:
        lda #0
        sta resultlo
        sta resulthi
        ldx #16
mul16loop:
        lda exprlo
        and #1
        beq mul16skip
        clc
        lda resultlo
        adc lhslo
        sta resultlo
        lda resulthi
        adc lhshi
        sta resulthi
mul16skip:
        asl lhslo
        rol lhshi
        lsr exprhi
        ror exprlo
        dex
        bne mul16loop
        lda resultlo
        sta exprlo
        lda resulthi
        sta exprhi
        rts

div16:
        lda exprlo
        ora exprhi
        beq div16zero
        lda #0
        sta quotlo
        sta quothi
        sta remlo
        sta remhi
        ldx #16
div16loop:
        asl lhslo
        rol lhshi
        rol remlo
        rol remhi
        asl quotlo
        rol quothi
        lda remhi
        cmp exprhi
        bcc div16next
        bne div16sub
        lda remlo
        cmp exprlo
        bcc div16next
div16sub:
        sec
        lda remlo
        sbc exprlo
        sta remlo
        lda remhi
        sbc exprhi
        sta remhi
        inc quotlo
div16next:
        dex
        bne div16loop
        lda quotlo
        sta exprlo
        lda quothi
        sta exprhi
        rts
div16zero:
        lda #0
        sta exprlo
        sta exprhi
        rts

;=======================================================================================
; Signed integer comparison runtime
;=======================================================================================

cmpeq:
        lda lhshi
        cmp exprhi
        bne cmpeqfalse
        lda lhslo
        cmp exprlo
        beq cmpeqtrue
cmpeqfalse:
        jmp cmpfalse
cmpeqtrue:
        jmp cmptrue

cmpne:
        lda lhshi
        cmp exprhi
        bne cmpnetrue
        lda lhslo
        cmp exprlo
        bne cmpnetrue
        jmp cmpfalse
cmpnetrue:
        jmp cmptrue

cmplt:
        lda lhshi
        eor exprhi
        bpl cmpltsame
        lda lhshi
        bmi cmplttrue
        jmp cmpfalse
cmplttrue:
        jmp cmptrue
cmpltsame:
        lda lhshi
        cmp exprhi
        bcc cmplttrue2
        bne cmpltfalse
        lda lhslo
        cmp exprlo
        bcc cmplttrue2
cmpltfalse:
        jmp cmpfalse
cmplttrue2:
        jmp cmptrue

cmple:
        lda lhshi
        eor exprhi
        bpl cmplesame
        lda lhshi
        bmi cmpletrue
        jmp cmpfalse
cmpletrue:
        jmp cmptrue
cmplesame:
        lda lhshi
        cmp exprhi
        bcc cmpletrue2
        bne cmplefalse
        lda lhslo
        cmp exprlo
        bcc cmpletrue2
        beq cmpletrue2
cmplefalse:
        jmp cmpfalse
cmpletrue2:
        jmp cmptrue

cmpge:
        lda lhshi
        eor exprhi
        bpl cmpgesame
        lda lhshi
        bmi cmpgefalse
        jmp cmptrue
cmpgefalse:
        jmp cmpfalse
cmpgesame:
        lda lhshi
        cmp exprhi
        bcc cmpgefalse2
        bne cmpgetrue
        lda lhslo
        cmp exprlo
        bcs cmpgetrue
cmpgefalse2:
        jmp cmpfalse
cmpgetrue:
        jmp cmptrue

cmpgt:
        lda lhshi
        eor exprhi
        bpl cmpgtsame
        lda lhshi
        bmi cmpgtfalse
        jmp cmptrue
cmpgtfalse:
        jmp cmpfalse
cmpgtsame:
        lda lhshi
        cmp exprhi
        bcc cmpgtfalse2
        bne cmpgttrue
        lda lhslo
        cmp exprlo
        bcc cmpgtfalse2
        beq cmpgtfalse2
cmpgttrue:
        jmp cmptrue
cmpgtfalse2:
        jmp cmpfalse

cmptrue:
        lda #1
        rts
cmpfalse:
        lda #0
        rts

;=======================================================================================
; Print runtime
;=======================================================================================

printch:
        ldx fio_out
        beq +
        jsr fio_rom_on          ; file output: raw byte through the DOS
        jsr kernalchrout
        jmp fio_rom_off
+       cmp #$0d
        beq printchcr
        pha
        jsr kernalchrout
        pla
        inc printcol
        lda printcol
        cmp #10
        bcc printchdone
        lda #0
        sta printcol
printchdone:
        rts
printchcr:
        phx
        phy
        sec
        jsr kernalplot
        stx sr
        jsr kernalscreen
        dey
        cpy sr
        beq pccs
        lda #$0d
        jsr kernalchrout
        lda #0
        sta printcol
        ply
        plx
        rts
pccs:
        jsr printscroll
        ldx sr
        ldy #0
        clc
        jsr kernalplot
        lda #0
        sta printcol
        ply
        plx
        rts

printstr:
        lda rtptr
        ora rtptr+1
        beq printstrdone
        ldy #0
printstrloop:
        lda (rtptr),y
        beq printstrdone
        jsr printch
        iny
        bne printstrloop
printstrdone:
        rts

printcomma:
        lda #$20
        jsr printch
        lda printcol
        bne printcomma
        rts

printuint:
        lda exprhi
        bpl printpos
        lda #'-'
        jsr printch
        sec
        lda #0
        sbc exprlo
        sta exprlo
        lda #0
        sbc exprhi
        sta exprhi
        jmp printdigits
printpos:
        lda #' '
        jsr printch
printdigits:
        lda #0
        sta printstarted
        lda #<$2710
        ldy #>$2710
        jsr printdigit
        lda #<$03e8
        ldy #>$03e8
        jsr printdigit
        lda #<$0064
        ldy #>$0064
        jsr printdigit
        lda #<$000a
        ldy #>$000a
        jsr printdigit
        lda exprlo
        clc
        adc #'0'
        jsr printch
        lda #' '
        jsr printch
        rts

printdigit:
        sta divlo
        sty divhi
        lda #'0'
        sta digit
pdloop:
        lda exprhi
        cmp divhi
        bcc pddone
        bne pdsub
        lda exprlo
        cmp divlo
        bcc pddone
pdsub:
        sec
        lda exprlo
        sbc divlo
        sta exprlo
        lda exprhi
        sbc divhi
        sta exprhi
        inc digit
        jmp pdloop
pddone:
        lda digit
        cmp #'0'
        bne pdemit
        lda printstarted
        beq pdreturn
        lda digit
pdemit:
        sta digit
        lda #1
        sta printstarted
        lda digit
        jsr printch
pdreturn:
        rts

printscroll:
        lda varptr
        pha
        lda varptr+1
        pha
        lda varptr+2
        pha
        lda varptr+3
        pha
        lda rtptr
        pha
        lda rtptr+1
        pha
        lda rtptr+2
        pha
        lda rtptr+3
        pha
        lda #<$0800
        sta varptr
        lda #>$0800
        sta varptr+1
        lda #0
        sta varptr+2
        sta varptr+3
        lda #<$0850
        sta rtptr
        lda #>$0850
        sta rtptr+1
        lda #0
        sta rtptr+2
        sta rtptr+3
        jsr psc
        lda #<$0f80
        sta varptr
        lda #>$0f80
        sta varptr+1
        lda #$20
        jsr psf
        lda #<$f800
        sta varptr
        lda #>$f800
        sta varptr+1
        lda #1
        sta varptr+2
        lda #0
        sta varptr+3
        lda #<$f850
        sta rtptr
        lda #>$f850
        sta rtptr+1
        lda #1
        sta rtptr+2
        lda #0
        sta rtptr+3
        jsr psc
        lda #<$ff80
        sta varptr
        lda #>$ff80
        sta varptr+1
        lda #1
        sta varptr+2
        lda #0
        sta varptr+3
        lda #$01
        jsr psf
        pla
        sta rtptr+3
        pla
        sta rtptr+2
        pla
        sta rtptr+1
        pla
        sta rtptr
        pla
        sta varptr+3
        pla
        sta varptr+2
        pla
        sta varptr+1
        pla
        sta varptr
        rts
psc:
        lda #<$0780
        sta scl
        lda #>$0780
        sta sch
pcl:
        ldz #0
        lda [rtptr],z
        sta [varptr],z
        jsr pib
        jsr pdc
        bne pcl
        rts
psf:
        sta sf
        lda #<$0050
        sta scl
        lda #>$0050
        sta sch
pfl:
        ldz #0
        lda sf
        sta [varptr],z
        jsr pid
        jsr pdc
        bne pfl
        rts
pib:
        inc rtptr
        bne pid
        inc rtptr+1
pid:
        inc varptr
        bne pir
        inc varptr+1
pir:
        rts
pdc:
        lda scl
        bne pdl
        dec sch
pdl:
        dec scl
        lda scl
        ora sch
        rts

;=======================================================================================
; Input runtime
;=======================================================================================

inputline:
        lda #$3f
        jsr printch
        lda #$20
        jsr printch
        ldx #7                  ; CHRIN runs the KERNAL screen editor,
_inputline_save:                ; whose state lives in $f7-$fe where
        lda varptr,x            ; the runtime keeps its pointers: park
        sta inputzpsave,x       ; ours and hand the editor its own
        lda edzpsave,x          ; bytes for the duration of the read
        sta varptr,x            ; (varptr+3 corruption crashed fpack)
        dex
        bpl _inputline_save
        lda #0
        sta inputpos
        sta inputlen
inputlineloop:
        jsr kernalchrin
        cmp #$0d
        beq inputlinedone
        ldx inputlen
        cpx #80
        bcs inputlineloop
        sta inputbuf,x
        inc inputlen
        jmp inputlineloop
inputlinedone:
        ldx #7
_inputline_restore:
        lda varptr,x            ; editor state (possibly updated) back
        sta edzpsave,x          ; to its parking spot, our pointers in
        lda inputzpsave,x
        sta varptr,x
        dex
        bpl _inputline_restore
        ldx inputlen
        lda #0
        sta inputbuf,x
        lda #$0d
        jsr printch
        lda #0
        sta printcol
        sta inputpos
        rts

inputskipspaces:
        ldx inputpos
        lda inputbuf,x
        cmp #$20
        bne inputskipdone
        inc inputpos
        jmp inputskipspaces
inputskipdone:
        rts

inputint:
        jsr inputskipspaces
        lda #0
        sta exprlo
        sta exprhi
        sta inputneg
        sta inputdigits
inputloop:
        ldx inputpos
        lda inputbuf,x
        beq inputdone
        cmp #$2c
        beq inputcomma
        cmp #$20
        beq _input_space
        cmp #$2d
        beq inputminus
        cmp #$2b
        beq inputplus
        cmp #$30
        bcc inputadvance
        cmp #$3a
        bcs inputadvance
        sec
        sbc #$30
        sta digit
        jsr inputmul10add
        inc inputdigits
        inc inputpos
        jmp inputloop
_input_space:
        lda inputdigits         ; a space ends a started number (CBM-style)
        bne inputdone
inputadvance:
        inc inputpos
        jmp inputloop
inputcomma:
        inc inputpos
        jmp inputdone
inputminus:
        lda inputdigits
        bne inputadvance
        lda #1
        sta inputneg
        inc inputpos
        jmp inputloop
inputplus:
        lda inputdigits
        bne inputadvance
        inc inputpos
        jmp inputloop
inputdone:
        lda inputneg
        beq inputreturn
        lda exprlo
        ora exprhi
        beq inputreturn
        sec
        lda #0
        sbc exprlo
        sta exprlo
        lda #0
        sbc exprhi
        sta exprhi
inputreturn:
        rts

inputstr:
        jsr inputskipspaces
        lda inputpos
        sta inputfieldstart
        lda #0
        sta strlen
inputstrlenloop:
        ldx inputpos
        lda inputbuf,x
        beq inputstralloc
        cmp #$2c
        beq inputstrcomma
        inc inputpos
        inc strlen
        jmp inputstrlenloop
inputstrcomma:
        inc inputpos
inputstralloc:
        jsr stralloc
        bcs inputstrdone
        ldz #0
        lda strlen
        sta [varptr],z
        lda #0
        sta stridx
inputstrcopy:
        lda stridx
        cmp strlen
        beq inputstrfinish
        clc
        lda inputfieldstart
        adc stridx
        tax
        lda inputbuf,x
        pha
        inc stridx
        ldz stridx
        pla
        sta [varptr],z
        jmp inputstrcopy
inputstrfinish:
        lda strdstlo
        sta exprlo
        lda strdsthi
        sta exprhi
inputstrdone:
        rts

;=======================================================================================
; Decimal parse helper
;=======================================================================================

inputmul10add:
        asl exprlo
        rol exprhi
        lda exprlo
        sta lhslo
        lda exprhi
        sta lhshi
        asl exprlo
        rol exprhi
        asl exprlo
        rol exprhi
        clc
        lda exprlo
        adc lhslo
        sta exprlo
        lda exprhi
        adc lhshi
        sta exprhi
        clc
        lda exprlo
        adc digit
        sta exprlo
        lda exprhi
        adc #0
        sta exprhi
        rts

;=======================================================================================
; String temporary heap marks
;=======================================================================================

strmark:
        ldx strmarksp
        cpx #8
        bcc strmarkok
        jmp outofstring
strmarkok:
        lda strheaplo
        sta strmarklo,x
        lda strheaphi
        sta strmarkhi,x
        inc strmarksp
        rts
strrelease:
        lda strmarksp
        beq strreleasedone
        dec strmarksp
        ldx strmarksp
        lda strmarklo,x
        sta strheaplo
        lda strmarkhi,x
        sta strheaphi
strreleasedone:
        rts

;=======================================================================================
; DATA/READ runtime
;=======================================================================================

datainit:
        lda rtdatastart
        sta dataptrlo
        lda rtdatastart+1
        sta dataptrhi
        rts

readint:
        jsr deof
        bcc riok
        lda #0
        sta exprlo
        sta exprhi
        jmp ood
riok:
        jsr drp
        ldy #0
        lda (rtptr),y
        beq rit
        lda #0
        sta exprlo
        sta exprhi
        jmp tm
rit:
        iny
        lda (rtptr),y
        sta exprlo
        iny
        lda (rtptr),y
        sta exprhi
        jsr dadv
        rts

readstr:
        jsr deof
        bcc rsok
        lda #0
        sta exprlo
        sta exprhi
        jmp ood
rsok:
        jsr drp
        ldy #0
        lda (rtptr),y
        cmp #$01
        beq rst
        lda #0
        sta exprlo
        sta exprhi
        jmp tm
rst:
        iny
        lda (rtptr),y
        sta strsrc1lo
        iny
        lda (rtptr),y
        sta strsrc1hi
        jsr dadv
        lda strsrc1lo
        sta rtptr
        lda strsrc1hi
        sta rtptr+1
        jsr strfromlit
        rts

deof:
        lda dataptrhi
        cmp rtdataend+1
        bne dne
        lda dataptrlo
        cmp rtdataend
        bne dne
        sec
        rts
dne:
        clc
        rts

drp:
        lda dataptrlo
        sta rtptr
        lda dataptrhi
        sta rtptr+1
        rts

dadv:
        clc
        lda dataptrlo
        adc #3
        sta dataptrlo
        lda dataptrhi
        adc #0
        sta dataptrhi
        rts

ood:
        lda #13
        jmp rterror

tm:
        lda #22
        jmp rterror

odm:
        .byte $4f,$55,$54,$20,$4f,$46,$20,$44,$41,$54,$41,$00
tmm:
        .byte $54,$59,$50,$45,$20,$4d,$49,$53,$4d,$41,$54,$43,$48,$00

;=======================================================================================
; Array runtime
;=======================================================================================

arraybounds:
        lda #18
        jmp rterror

;=======================================================================================
; GET runtime
;=======================================================================================

getkey:
        jsr kernalgetin
        sta exprlo
        lda #0
        sta exprhi
        rts
getstr:
        jsr kernalgetin
        sta digit
        bne getstrgot
        sta exprlo
        sta exprhi
        rts
; FAC -> unsigned 32-bit in exprlo/exprhi/exprb2/exprb3 (DMA addresses)
fq32:
        lda #0
        sta exprb2
        sta exprb3
        lda facexp
        bne +
        sta exprlo
        sta exprhi
        rts
+       lda #$a0                ; exponent $a0 = exact 32-bit integer
        sec
        sbc facexp
        bcc _fq32_over
        cmp #32
        bcs _fq32_zero
        tax
        lda facm0
        sta exprb3
        lda facm1
        sta exprb2
        lda facm2
        sta exprhi
        lda facm3
        sta exprlo
        cpx #0
        beq _fq32_done
_fq32_shift:
        lsr exprb3
        ror exprb2
        ror exprhi
        ror exprlo
        dex
        bne _fq32_shift
_fq32_done:
        rts
_fq32_zero:
        lda #0
        sta exprlo
        sta exprhi
        rts
_fq32_over:
        lda #14                 ; ILLEGAL QUANTITY
        jmp rterror

; DMA/EDMA argument staging: 7 slots of 4 bytes (cmd, len, src, tgt,
; sub, mod / old-form bank args); dmaa16 zero-extends an int result,
; dmaa32 converts a float result
dmarst:
        lda #0
        sta dma_i
        ldx #35
_dmarst_clr:
        sta dma_args,x
        dex
        bpl _dmarst_clr
        rts

dmaa16:
        lda #0
        sta exprb2
        sta exprb3
        bra dmastore
dmaa32:
        jsr fq32
dmastore:
        lda dma_i
        cmp #9
        bcs _dma_store_done
        asl a
        asl a
        tax
        lda exprlo
        sta dma_args,x
        lda exprhi
        sta dma_args+1,x
        lda exprb2
        sta dma_args+2,x
        lda exprb3
        sta dma_args+3,x
        inc dma_i
_dma_store_done:
        rts

; old DMA form: cmd, len, srcaddr, srcbank, tgtaddr, tgtbank [, sub]
; -> merge the bank args into 28-bit addresses and fall into edmago
dmago:
        lda dma_args+12         ; srcbank low byte -> src bits 16-23
        sta dma_args+10
        lda dma_args+13
        sta dma_args+11
        lda dma_args+16         ; tgt addr slot 4 -> slot 3
        sta dma_args+12
        lda dma_args+17
        sta dma_args+13
        lda dma_args+20         ; tgtbank -> tgt bits 16-23
        sta dma_args+14
        lda dma_args+21
        sta dma_args+15
        lda dma_args+24         ; sub -> slot 4, modulo = 0
        sta dma_args+16
        lda #0
        sta dma_args+17
        sta dma_args+20
        sta dma_args+21
        ; FALLTHROUGH

; build and trigger an enhanced DMAgic job (F018B format with source
; and target megabyte options); args: cmd, len, src28, tgt28, sub, mod
edmago:
        lda #$0b                ; select the 12-byte F018B job format
        sta dmalist+0
        lda #$80                ; source megabyte option
        sta dmalist+1
        lda dma_args+10         ; src bits 16-23
        lsr a
        lsr a
        lsr a
        lsr a
        sta dma_tmp
        lda dma_args+11         ; src bits 24-27
        asl a
        asl a
        asl a
        asl a
        ora dma_tmp
        sta dmalist+2
        lda #$81                ; target megabyte option
        sta dmalist+3
        lda dma_args+14
        lsr a
        lsr a
        lsr a
        lsr a
        sta dma_tmp
        lda dma_args+15
        asl a
        asl a
        asl a
        asl a
        ora dma_tmp
        sta dmalist+4
        lda #$00                ; end of options
        sta dmalist+5
        lda dma_args+0          ; command
        and #$03
        sta dmalist+6
        lda dma_args+4          ; count
        sta dmalist+7
        lda dma_args+5
        sta dmalist+8
        lda dma_args+8          ; source addr low/high, bank-in-MB
        sta dmalist+9
        lda dma_args+9
        sta dmalist+10
        lda dma_args+10
        and #$0f
        sta dmalist+11
        lda dma_args+12         ; target addr low/high, bank-in-MB
        sta dmalist+12
        lda dma_args+13
        sta dmalist+13
        lda dma_args+14
        and #$0f
        sta dmalist+14
        lda dma_args+16         ; sub command -> command high byte
        sta dmalist+15
        lda dma_args+20         ; modulo
        sta dmalist+16
        lda dma_args+21
        sta dmalist+17
        lda #0                  ; list lives in bank 0, megabyte 0
        sta $d702
        sta $d704
        lda #>dmalist
        sta $d701
        lda #<dmalist
        sta $d705               ; enhanced-mode trigger
        rts

; FGOTO/FGOSUB: resolve a computed line number via the emitted table
; (word count, then line#/address pairs); miss raises UNDEF'D STATEMENT
fgres:
        lda rtlinetab
        sta rtptr
        lda rtlinetab+1
        sta rtptr+1
        ldy #0
        lda (rtptr),y
        sta fg_cnt
        iny
        lda (rtptr),y
        sta fg_cnt+1
        clc
        lda rtptr
        adc #2
        sta rtptr
        bcc _fg_loop
        inc rtptr+1
_fg_loop:
        lda fg_cnt
        ora fg_cnt+1
        beq _fg_err
        ldy #0
        lda (rtptr),y
        cmp exprlo
        bne _fg_next
        ldy #1
        lda (rtptr),y
        cmp exprhi
        bne _fg_next
        ldy #2
        lda (rtptr),y
        sta fg_addr
        ldy #3
        lda (rtptr),y
        sta fg_addr+1
        rts
_fg_next:
        clc
        lda rtptr
        adc #4
        sta rtptr
        bcc +
        inc rtptr+1
+       lda fg_cnt
        bne +
        dec fg_cnt+1
+       dec fg_cnt
        jmp _fg_loop
_fg_err:
        lda #11                 ; UNDEF'D STATEMENT
        jmp rterror

fgoto:
        jsr fgres
        pla                     ; GOTO semantics: drop the return
        pla
        jmp (fg_addr)

fgosub:
        jsr fgres
        jmp (fg_addr)           ; the target's RETURN rts's to our caller

; ---------------------------------------------------------------------------
; Banked graphics: the GFX blob loads to bank 5 at init; each graphics
; call DMA-swaps it into the $8000-$bfff window, dispatches through
; its jump table, and swaps the program code back afterwards.
; ---------------------------------------------------------------------------
; The KERNAL banked LOAD does not reach bank 5, so the blob is read
; byte-wise through the DOS data channel and far-stored to $50000.
; One-time cost at init; trivial at 40MHz.
gfxload:
        jsr fio_rom_on
        lda #0
        ldx #0
        jsr kernalsetbnk
        lda #7
        ldx #<_gfx_name
        ldy #>_gfx_name
        jsr kernalsetnam
        lda #15
        ldx #8
        ldy #2                  ; DOS data channel
        jsr kernalsetlfs
        jsr kernalopen
        bcs _gfxl_err
        ldx #15
        jsr kernalchkin
        bcs _gfxl_err
        jsr kernalchrin         ; skip the 2-byte PRG load address
        jsr kernalchrin
        jsr kernalreadst        ; missing file: EOF/error on first reads
        bne _gfxl_err
        lda #0                  ; far pointer: bank 5 offset 0
        sta varptr
        sta varptr+1
        sta varptr+3
        lda #5
        sta varptr+2
        ldz #0
_gfxl_loop:
        jsr kernalchrin
        sta [varptr],z
        inc varptr
        bne +
        inc varptr+1
+       jsr kernalreadst
        and #$40                ; EOF arrives with the last byte
        beq _gfxl_loop
        lda #15
        jsr kernalclose
        jsr kernalclrchn
        jsr fio_rom_off
        jmp scrrestore          ; gfxload borrowed varptr for bank 5
_gfxl_err:
        lda #15
        jsr kernalclose
        jsr kernalclrchn
        jsr fio_rom_off
        lda #21                 ; missing GFX file: FILE NOT FOUND
        jmp rterror
_gfx_name:
        .text "GFX,P,R"

; PEN [pen,] colour -- the colour is the last staged argument; the pen
; number (only pen 0 exists here) is ignored
penset:
        lda dma_i
        cmp #2
        bcc _pen_one
        lda dma_args+4
        sta gfx_pen
        rts
_pen_one:
        lda dma_args+0
        sta gfx_pen
        rts

; multi-pair LINE: the just-drawn segment's end becomes the next
; segment's start; the next two staged args land in slots 2/3
gfxlnext:
        ldx #7
_gfxln_cp:
        lda dma_args+8,x
        sta dma_args,x
        dex
        bpl _gfxln_cp
        lda #2
        sta dma_i
        rts

; RCOLOR(source): 0 background, 1 text colour, 2 highlight, 3 border
rcolorf:
        lda exprlo
        cmp #1
        beq _rcol_text
        cmp #2
        beq _rcol_hl
        cmp #3
        beq _rcol_border
        lda $d021
        bra _rcol_done
_rcol_text:
        lda $f1
        bra _rcol_done
_rcol_hl:
        lda $02d8
        bra _rcol_done
_rcol_border:
        lda $d020
_rcol_done:
        sta exprlo
        lda #0
        sta exprhi
        rts

; RPEN(n): only the drawing pen exists here; other pens read as 0
rpenf:
        lda exprlo
        bne _rpen_zero
        lda gfx_pen
        sta exprlo
        lda #0
        sta exprhi
        rts
_rpen_zero:
        lda #0
        sta exprlo
        sta exprhi
        rts

; A = function index; arguments pre-staged in dma_args.
; The blob executes from real RAM at $8000-$bfff: DMA stashes whatever
; lives there (program code) to bank 5 $4000, copies the blob in from
; bank 5 $0000, dispatches, then copies the blob back (it keeps state
; like the screen mode inside itself) and restores the stash. No MAP:
; the KERNAL, its interrupt vectors, and the IRQ engines stay exactly
; where the hardware expects them, so interrupts keep running even
; through a long PAINT. Four 16KB DMA copies cost ~1ms at 40MHz.
gfxcall:
        asl a
        sta gfx_fn
        ldx #0                  ; stash $08000 -> $54000
        jsr gfxcopy
        ldx #6                  ; blob $50000 -> $08000
        jsr gfxcopy
        ldx gfx_fn
        jsr _gfx_go
        ldx #12                 ; blob (and its state) -> $50000
        jsr gfxcopy
        ldx #18                 ; program code $54000 -> $08000
        jsr gfxcopy
        ldz #0                  ; the blob uses Z freely; compiled code
                                ; relies on the ambient Z=0 convention
        jmp scrrestore          ; and the blob's PTR is varptr: put the
                                ; bank-1 invariant back or every later
                                ; variable store lands in pixel memory
_gfx_go:
        jmp ($8004,x)          ; table sits after the gfx_base slot

; one 16KB copy per entry: src lo/hi/bank, dst lo/hi/bank
gfxcopytab:
        .byte $00,$80,$00, $00,$40,$05
        .byte $00,$00,$05, $00,$80,$00
        .byte $00,$80,$00, $00,$00,$05
        .byte $00,$40,$05, $00,$80,$00

gfxcopy:
        ldy #0
_gfxc_patch:
        lda gfxcopytab,x
        sta gfxdmasrc,y
        inx
        iny
        cpy #6
        bne _gfxc_patch
        lda #0                  ; list in bank 0, megabyte 0
        sta $d702
        sta $d704
        lda #>gfxdmalist
        sta $d701
        lda #<gfxdmalist
        sta $d705               ; enhanced-mode trigger
        rts

gfxdmalist:
        .byte $0b               ; F018B 12-byte job format
        .byte $80, $00          ; source megabyte 0
        .byte $81, $00          ; target megabyte 0
        .byte $00               ; end of options
        .byte $00               ; command: copy
        .word $4000             ; count: the full 16KB window
gfxdmasrc:
        .byte $00, $00, $00     ; source lo/hi/bank (patched)
        .byte $00, $00, $00     ; target lo/hi/bank (patched)
        .byte $00               ; sub command
        .word 0                 ; modulo

; GC-visible string temp stack: 20 two-byte slots in bank 1 at $1fd0.
; Compiled code parks string intermediates here instead of the CPU
; stack so a mid-expression garbage collection can relocate them (the
; PHA-parked form was invisible to the root walk and produced stale
; descriptors -- the long-standing corruption bug). Empty slots stay
; zero so the walker skips them.
strtpush:
        lda strtsp
        cmp #20
        bcc +
        lda #16                 ; OUT OF STRING
        jmp rterror
+       asl a
        tax
        lda exprlo
        sta strtslots,x
        lda exprhi
        sta strtslots+1,x
        inc strtsp
        rts

strtpop:
        dec strtsp
        lda strtsp
        asl a
        tax
        lda strtslots,x
        sta lhslo
        lda strtslots+1,x
        sta lhshi
        lda #0
        sta strtslots,x
        sta strtslots+1,x
        rts

; zero the whole temp stack (init, CLR, and error recovery -- an error
; mid-expression must not leave dead descriptors pinning heap strings)
strtreset:
        lda #0
        sta strtsp
        ldx #43
_strtr:
        sta strtslots,x
        dex
        bpl _strtr
        rts

; SETBIT/CLRBIT: addresses <= $ffff go through the BANK setting
; (>= 128 = CPU view), addresses >= $10000 are flat 28-bit
bitadr16:
        lda exprlo
        sta bit_addr
        lda exprhi
        sta bit_addr+1
        lda #0
        sta bit_addr+2
        sta bit_addr+3
        rts

bitadr32:
        jsr fq32
        lda exprlo
        sta bit_addr
        lda exprhi
        sta bit_addr+1
        lda exprb2
        sta bit_addr+2
        lda exprb3
        sta bit_addr+3
        rts

; C set: far path staged in varptr; C clear: CPU path in rtptr
bitprep:
        lda exprlo              ; bit number -> mask
        and #7
        tax
        lda bittab,x
        sta bit_mask
        lda bit_addr+2
        ora bit_addr+3
        bne _bp_flat
        lda cur_bank
        bmi _bp_cpu
        lda bit_addr
        sta varptr
        lda bit_addr+1
        sta varptr+1
        lda cur_bank
        sta varptr+2
        lda #0
        sta varptr+3
        sec
        rts
_bp_flat:
        lda bit_addr
        sta varptr
        lda bit_addr+1
        sta varptr+1
        lda bit_addr+2
        sta varptr+2
        lda bit_addr+3
        sta varptr+3
        sec
        rts
_bp_cpu:
        lda bit_addr
        sta rtptr
        lda bit_addr+1
        sta rtptr+1
        clc
        rts

setbitgo:
        jsr bitprep
        bcc _sb_cpu
        ldz #0
        lda [varptr],z
        ora bit_mask
        sta [varptr],z
        jmp scrrestore
_sb_cpu:
        ldy #0
        lda (rtptr),y
        ora bit_mask
        sta (rtptr),y
        rts

clrbitgo:
        jsr bitprep
        lda bit_mask
        eor #$ff
        sta bit_mask
        bcc _cb_cpu
        ldz #0
        lda [varptr],z
        and bit_mask
        sta [varptr],z
        jmp scrrestore
_cb_cpu:
        ldy #0
        lda (rtptr),y
        and bit_mask
        sta (rtptr),y
        rts

bittab:
        .byte 1, 2, 4, 8, 16, 32, 64, 128

; SPRSAV: 64-byte C64-style sprite shapes staged through sprsavbuf.
; Sprite data is found through the live pointers at screen+1016 (the
; screen base comes from SCRNPTR, VIC bank 0 assumed).
sprdataptr:
        lda $d060               ; screen base + $3f8 + sprite#
        clc
        adc #$f8
        sta varptr
        lda $d061
        adc #$03
        sta varptr+1
        lda $d062
        adc #0
        sta varptr+2
        lda #0
        sta varptr+3
        lda exprlo
        and #7
        taz
        lda [varptr],z          ; the sprite pointer byte
        sta rtptr+1             ; *64: byte<<6 across 16 bits
        lda #0
        sta rtptr
        lsr rtptr+1
        ror rtptr
        lsr rtptr+1
        ror rtptr
        jmp scrrestore          ; varptr bank-1 invariant back

sprsava:                        ; numeric source: sprite -> buffer
        jsr sprdataptr
        ldy #0
_ssa_loop:
        lda (rtptr),y
        sta sprsavbuf,y
        iny
        cpy #64
        bne _ssa_loop
        rts

sprsavs:                        ; string source -> buffer (pad with 0)
        ldy #0
        tya
_sss_clr:
        sta sprsavbuf,y
        iny
        cpy #64
        bne _sss_clr
        lda exprlo
        ora exprhi
        beq _sss_done
        jsr setstrptrexpr
        ldz #0
        lda [varptr],z
        cmp #65
        bcc +
        lda #64
+       sta sprs_len
        ldy #0
_sss_copy:
        cpy sprs_len
        bcs _sss_done
        iny
        tya
        taz
        lda [varptr],z
        dey
        sta sprsavbuf,y
        iny
        bra _sss_copy
_sss_done:
        rts

sprsavdn:                       ; buffer -> sprite (numeric dest)
        jsr sprdataptr
        ldy #0
_ssd_loop:
        lda sprsavbuf,y
        sta (rtptr),y
        iny
        cpy #64
        bne _ssd_loop
        rts

sprsavstr:                      ; buffer -> fresh 64-byte heap string
        lda #64
        sta strlen
        jsr stralloc
        bcs _sstr_done
        ldz #0
        lda #64
        sta [varptr],z
        ldy #0
_sstr_loop:
        lda sprsavbuf,y
        inz
        sta [varptr],z
        iny
        cpy #64
        bne _sstr_loop
_sstr_done:
        rts

; VSYNC raster: busy-wait until the 9-bit VIC raster matches
vsync:
        lda $d012
        cmp exprlo
        bne vsync
        lda $d011
        asl a
        lda #0
        rol a
        cmp exprhi
        bne vsync
        rts

; BANK n: banks >= 128 keep the CPU view (the compiled default);
; 0-127 switch the PEEK/POKE family to far 28-bit access
bankset:
        lda exprlo
        sta cur_bank
        rts

; bank-aware PEEK/POKE helpers (used only when the program says BANK);
; they borrow varptr and restore its bank-1 invariant afterwards
pokebk:
        lda cur_bank
        bmi _pokebk_cpu
        jsr bankptr
        lda exprlo
        ldz #0
        sta [varptr],z
        jmp scrrestore
_pokebk_cpu:
        lda exprlo
        ldy #0
        sta (rtptr),y
        rts

wpokebk:
        lda cur_bank
        bmi _wpokebk_cpu
        jsr bankptr
        lda exprlo
        ldz #0
        sta [varptr],z
        lda exprhi
        inz
        sta [varptr],z
        jmp scrrestore
_wpokebk_cpu:
        lda exprlo
        ldy #0
        sta (rtptr),y
        iny
        lda exprhi
        sta (rtptr),y
        rts

peekbk:
        lda cur_bank
        bmi _peekbk_cpu
        lda exprlo
        sta rtptr
        lda exprhi
        sta rtptr+1
        jsr bankptr
        ldz #0
        lda [varptr],z
        sta exprlo
        lda #0
        sta exprhi
        jmp scrrestore
_peekbk_cpu:
        lda exprlo
        sta rtptr
        lda exprhi
        sta rtptr+1
        ldy #0
        lda (rtptr),y
        sta exprlo
        lda #0
        sta exprhi
        rts

wpeekbk:
        lda cur_bank
        bmi _wpeekbk_cpu
        lda exprlo
        sta rtptr
        lda exprhi
        sta rtptr+1
        jsr bankptr
        ldz #0
        lda [varptr],z
        sta exprlo
        inz
        lda [varptr],z
        sta exprhi
        jmp scrrestore
_wpeekbk_cpu:
        lda exprlo
        sta rtptr
        lda exprhi
        sta rtptr+1
        ldy #0
        lda (rtptr),y
        sta exprlo
        iny
        lda (rtptr),y
        sta exprhi
        rts

bankptr:
        lda rtptr
        sta varptr
        lda rtptr+1
        sta varptr+1
        lda cur_bank
        sta varptr+2
        lda #0
        sta varptr+3
        rts

; SYS register capture for RREG (Z is a real register on the 45GS02)
sysregsave:
        php
        sta sys_a
        stx sys_x
        sty sys_y
        stz sys_z
        pla
        sta sys_sr
        rts

; RREG reader: A = register index into the capture block
rregn:
        tax
        lda sys_a,x
        sta exprlo
        lda #0
        sta exprhi
        rts

; pi constant for the $ff token (classic CBM packed value)
cpival:
        .byte $82, $49, $0f, $da, $a2
pif:
        lda #<cpival
        ldy #>cpival
        jmp fldc

; CHR$(n): a one-byte heap string (shares the GET tail)
chrstrf:
        lda exprlo
        sta digit
getstrgot:
        lda #1
        sta strlen
        jsr stralloc
        bcs getstrdone
        ldz #0
        lda #1
        sta [varptr],z
        ldz #1
        lda digit
        sta [varptr],z
        lda strdstlo
        sta exprlo
        lda strdsthi
        sta exprhi
getstrdone:
        rts

;=======================================================================================
; String heap runtime
; bank-1 string heap grows downward from $1f800, last usable byte $1f7ff
;=======================================================================================

strinit:
        lda #<strheaptop
        sta strheaplo
        lda #>strheaptop
        sta strheaphi
        rts

stralloc:
        lda #0
        sta strgctried
sa1:
        sec
        lda strheaplo
        sbc strlen
        sta strdstlo
        lda strheaphi
        sbc #0
        sta strdsthi
        sec
        lda strdstlo
        sbc #1
        sta strdstlo
        lda strdsthi
        sbc #0
        sta strdsthi
        lda strdsthi
        cmp rtvheapend+1
        bcs sarh
        jmp sagc
sarh:
        bne saok
        lda strdstlo
        cmp rtvheapend
        bcs saok
        jmp sagc
saok:
        lda strdstlo
        sta strheaplo
        sta exprlo
        sta varptr
        lda strdsthi
        sta strheaphi
        sta exprhi
        sta varptr+1
        lda #$01
        sta varptr+2
        lda #0
        sta varptr+3
        clc
        rts
sagc:
        lda strmarksp
        bne saoom
        lda strgctried
        bne saoom
        inc strgctried
        jsr strgc
        jmp sa1
saoom:
        jmp outofstring

strfromlit:
        ldy #0
strfromlitlen:
        lda (rtptr),y
        beq strfromlitalloc
        iny
        bne strfromlitlen
        jmp outofstring
strfromlitalloc:
        sty strlen
        jsr stralloc
        bcs strfromlitdone
        ldz #0
        lda strlen
        sta [varptr],z
        lda #0
        sta stridx
strfromlitcopy:
        lda stridx
        cmp strlen
        beq strfromlitdone
        tay
        lda (rtptr),y
        pha
        inc stridx
        ldz stridx
        pla
        sta [varptr],z
        jmp strfromlitcopy
strfromlitdone:
        rts

strcopyexpr:
        lda exprlo
        ora exprhi
        bne strcopygo
        rts
strcopygo:
        lda exprlo
        sta strsrc1lo
        lda exprhi
        sta strsrc1hi
        jsr setstrptrsrc1
        ldz #0
        lda [varptr],z
        sta strlen
        ldy #1                  ; src1 holds a live heap string: let a
        sty gcregmask           ; mid-alloc GC relocate it with us
        jsr stralloc
        ldy #0
        sty gcregmask
        bcs strcopydone
        ldz #0
        lda strlen
        sta [varptr],z
        lda #0
        sta stridx
strcopyloop:
        lda stridx
        cmp strlen
        beq strcopyfinish
        inc stridx
        jsr setstrptrsrc1
        ldz stridx
        lda [varptr],z
        pha
        jsr setstrptrdst
        ldz stridx
        pla
        sta [varptr],z
        jmp strcopyloop
strcopyfinish:
        lda strdstlo
        sta exprlo
        lda strdsthi
        sta exprhi
strcopydone:
        rts

concatstr:
        lda lhslo
        sta strsrc1lo
        lda lhshi
        sta strsrc1hi
        lda exprlo
        sta strsrc2lo
        lda exprhi
        sta strsrc2hi
        jsr strlen1load
        jsr strlen2load
        clc
        lda strlen1
        adc strlen2
        sta strlen
        bcc concatlenok
        jmp outofstring
concatlenok:
        ldy #3                  ; both sources are live heap strings
        sty gcregmask
        jsr stralloc
        ldy #0
        sty gcregmask
        bcs concatdone
        ldz #0
        lda strlen
        sta [varptr],z
        lda #0
        sta stridx
        lda #1
        sta strdstidx
concatcopy1:
        lda stridx
        cmp strlen1
        beq concatcopy2start
        inc stridx
        jsr setstrptrsrc1
        ldz stridx
        lda [varptr],z
        pha
        jsr setstrptrdst
        ldz strdstidx
        pla
        sta [varptr],z
        inc strdstidx
        jmp concatcopy1
concatcopy2start:
        lda #0
        sta stridx
concatcopy2:
        lda stridx
        cmp strlen2
        beq concatfinish
        inc stridx
        jsr setstrptrsrc2
        ldz stridx
        lda [varptr],z
        pha
        jsr setstrptrdst
        ldz strdstidx
        pla
        sta [varptr],z
        inc strdstidx
        jmp concatcopy2
concatfinish:
        lda strdstlo
        sta exprlo
        lda strdsthi
        sta exprhi
concatdone:
        rts

;=======================================================================================
; String comparisons (heap values)
;=======================================================================================

streq:
        jsr strcmp
        bne streqfalse
        jmp strcmptrue
streqfalse:
        jmp strcmpfalse
strne:
        jsr strcmp
        bne strnetrue
        jmp strcmpfalse
strnetrue:
        jmp strcmptrue
strlt:
        jsr strcmp
        bpl strltfalse
        jmp strcmptrue
strltfalse:
        jmp strcmpfalse
strle:
        jsr strcmp
        beq strletrue
        bpl strlefalse
strletrue:
        jmp strcmptrue
strlefalse:
        jmp strcmpfalse
strgt:
        jsr strcmp
        beq strgtfalse
        bmi strgtfalse
        jmp strcmptrue
strgtfalse:
        jmp strcmpfalse
strge:
        jsr strcmp
        beq strgetrue
        bmi strgefalse
strgetrue:
        jmp strcmptrue
strgefalse:
        jmp strcmpfalse
strcmptrue:
        lda #1
        rts
strcmpfalse:
        lda #0
        rts

;=======================================================================================
; String comparisons (heap/literal references)
;=======================================================================================

strrefeq:
        jsr srcmp
        bne sreqf
        jmp strcmptrue
sreqf:
        jmp strcmpfalse
strrefne:
        jsr srcmp
        bne srnet
        jmp strcmpfalse
srnet:
        jmp strcmptrue
strreflt:
        jsr srcmp
        bpl srltf
        jmp strcmptrue
srltf:
        jmp strcmpfalse
strrefle:
        jsr srcmp
        beq srlet
        bpl srlef
srlet:
        jmp strcmptrue
srlef:
        jmp strcmpfalse
strrefgt:
        jsr srcmp
        beq srgtf
        bmi srgtf
        jmp strcmptrue
srgtf:
        jmp strcmpfalse
strrefge:
        jsr srcmp
        beq srget
        bmi srgef
srget:
        jmp strcmptrue
srgef:
        jmp strcmpfalse
srcmp:
        lda lhslo
        sta strsrc1lo
        lda lhshi
        sta strsrc1hi
        lda exprlo
        sta strsrc2lo
        lda exprhi
        sta strsrc2hi
        jsr srlen1
        jsr srlen2
        lda #0
        sta stridx
srclp:
        lda stridx
        cmp strlen1
        beq srclhe
        cmp strlen2
        beq srcgt
        inc stridx
        jsr srch1
        sta strcmpchar
        jsr srch2
        sta strdstidx
        lda strcmpchar
        cmp strdstidx
        bcc srclt
        bne srcgt
        jmp srclp
srclhe:
        lda stridx
        cmp strlen2
        beq srceq
srclt:
        lda #$ff
        rts
srcgt:
        lda #1
        rts
srceq:
        lda #0
        rts
srlen1:
        lda strsrc1lo
        sta rtptr
        lda strsrc1hi
        sta rtptr+1
        lda strarg1lo
        jsr srlen
        sta strlen1
        rts
srlen2:
        lda strsrc2lo
        sta rtptr
        lda strsrc2hi
        sta rtptr+1
        lda strarg1hi
        jsr srlen
        sta strlen2
        rts
srlen:
        sta strsrcoff
        lda rtptr
        ora rtptr+1
        bne srlgo
        lda #0
        rts
srlgo:
        lda strsrcoff
        bne srllit
        lda rtptr
        sta varptr
        lda rtptr+1
        sta varptr+1
        jsr setstrptrbank
        ldz #0
        lda [varptr],z
        rts
srllit:
        ldy #0
srllp:
        lda (rtptr),y
        beq srldn
        iny
        bne srllp
        jmp outofstring
srldn:
        tya
        rts
srch1:
        lda strsrc1lo
        sta rtptr
        lda strsrc1hi
        sta rtptr+1
        lda strarg1lo
        jmp srch
srch2:
        lda strsrc2lo
        sta rtptr
        lda strsrc2hi
        sta rtptr+1
        lda strarg1hi
srch:
        bne srchlit
        lda rtptr
        sta varptr
        lda rtptr+1
        sta varptr+1
        jsr setstrptrbank
        ldz stridx
        lda [varptr],z
        rts
srchlit:
        ldy stridx
        dey
        lda (rtptr),y
        rts

strcmp:
        lda lhslo
        sta strsrc1lo
        lda lhshi
        sta strsrc1hi
        lda exprlo
        sta strsrc2lo
        lda exprhi
        sta strsrc2hi
        jsr strlen1load
        jsr strlen2load
        lda #0
        sta stridx
strcmploop:
        lda stridx
        cmp strlen1
        beq strcmplhsend
        cmp strlen2
        beq strcmpgreater
        inc stridx
        jsr setstrptrsrc1
        ldz stridx
        lda [varptr],z
        sta strcmpchar
        jsr setstrptrsrc2
        ldz stridx
        lda [varptr],z
        sta strdstidx
        lda strcmpchar
        cmp strdstidx
        bcc strcmpless
        bne strcmpgreater
        jmp strcmploop
strcmplhsend:
        lda stridx
        cmp strlen2
        beq strcmpequal
strcmpless:
        lda #$ff
        rts
strcmpgreater:
        lda #1
        rts
strcmpequal:
        lda #0
        rts

;=======================================================================================
; String helpers
;=======================================================================================

strlenexpr:
        lda exprlo
        ora exprhi
        bne strlenexprgo
        lda #0
        sta exprlo
        sta exprhi
        rts
strlenexprgo:
        jsr setstrptrexpr
        ldz #0
        lda [varptr],z
        sta exprlo
        lda #0
        sta exprhi
        rts

printheapstr:
        lda exprlo
        ora exprhi
        beq printheapdone
        jsr setstrptrexpr
        ldz #0
        lda [varptr],z
        sta strlen
        lda #0
        sta stridx
printheaploop:
        lda stridx
        cmp strlen
        beq printheapdone
        inc stridx
        ldz stridx
        lda [varptr],z
        jsr printch
        jmp printheaploop
printheapdone:
        rts

strlen1load:
        lda strsrc1lo
        ora strsrc1hi
        bne strlen1go
        lda #0
        sta strlen1
        rts
strlen1go:
        jsr setstrptrsrc1
        ldz #0
        lda [varptr],z
        sta strlen1
        rts

strlen2load:
        lda strsrc2lo
        ora strsrc2hi
        bne strlen2go
        lda #0
        sta strlen2
        rts
strlen2go:
        jsr setstrptrsrc2
        ldz #0
        lda [varptr],z
        sta strlen2
        rts

;=======================================================================================
; Substring runtime (LEFT$/RIGHT$/MID$)
;=======================================================================================

strright:
        lda lhslo
        sta strsrc1lo
        lda lhshi
        sta strsrc1hi
        lda lhslo
        ora lhshi
        bne srn
        jmp strsubempty
srn:
        jsr strlen1load
        lda exprhi
        bpl srcp
        jmp strsubempty
srcp:
        bne strrightall
        lda exprlo
        bne srcn
        jmp strsubempty
srcn:
        cmp strlen1
        bcs strrightall
        sta strlen
        sec
        lda strlen1
        sbc strlen
        clc
        adc #1
        sta strarg1lo
        lda #0
        sta strarg1hi
        lda strlen
        sta exprlo
        lda #0
        sta exprhi
        jmp strsub
strrightall:
        lda #1
        sta strarg1lo
        lda #0
        sta strarg1hi
        lda strlen1
        sta exprlo
        lda #0
        sta exprhi
        jmp strsub

strsub:
        lda lhslo
        sta strsrc1lo
        lda lhshi
        sta strsrc1hi
        lda lhslo
        ora lhshi
        bne ssn
        jmp strsubempty
ssn:
        jsr strlen1load
        lda strarg1hi
        bmi strsubstartone
        bne strsubempty
        lda strarg1lo
        beq strsubstartone
        sec
        sbc #1
        sta strsrcoff
        jmp strsubhavestart
strsubstartone:
        lda #0
        sta strsrcoff
strsubhavestart:
        lda strsrcoff
        cmp strlen1
        bcs strsubempty
        sec
        lda strlen1
        sbc strsrcoff
        sta strlen2
        lda exprhi
        bmi strsubempty
        bne strsubuseavail
        lda exprlo
        beq strsubempty
        cmp strlen2
        bcs strsubuseavail
        sta strlen
        jmp strsuballoc
strsubuseavail:
        lda strlen2
        sta strlen
strsuballoc:
        ldy #1                  ; src1 = the substring source
        sty gcregmask
        jsr stralloc
        ldy #0
        sty gcregmask
        bcs strsubdone
        ldz #0
        lda strlen
        sta [varptr],z
        lda #0
        sta stridx
strsubcopy:
        lda stridx
        cmp strlen
        beq strsubfinish
        clc
        lda strsrcoff
        adc stridx
        clc
        adc #1
        sta strdstidx
        jsr setstrptrsrc1
        ldz strdstidx
        lda [varptr],z
        pha
        jsr setstrptrdst
        inc stridx
        ldz stridx
        pla
        sta [varptr],z
        jmp strsubcopy
strsubfinish:
        lda strdstlo
        sta exprlo
        lda strdsthi
        sta exprhi
strsubdone:
        rts
strsubempty:
        lda #0
        sta strlen
        jsr stralloc
        bcs strsubdone
        ldz #0
        lda #0
        sta [varptr],z
        lda strdstlo
        sta exprlo
        lda strdsthi
        sta exprhi
        rts

;=======================================================================================
; STR$ runtime
;=======================================================================================

strfromint:
        lda exprlo
        sta lhslo
        lda exprhi
        sta lhshi
        lda #6
        sta strlen
        jsr stralloc
        bcs strfromintdone
        lda #0
        sta stridx
        lda lhshi
        bmi strfromintneg
        lda #' '
        jsr strputchar
        jmp strfromintdigits
strfromintneg:
        lda #'-'
        jsr strputchar
        sec
        lda #0
        sbc lhslo
        sta lhslo
        lda #0
        sbc lhshi
        sta lhshi
strfromintdigits:
        lda #0
        sta printstarted
        lda #<$2710
        ldy #>$2710
        jsr strdigit
        lda #<$03e8
        ldy #>$03e8
        jsr strdigit
        lda #<$0064
        ldy #>$0064
        jsr strdigit
        lda #<$000a
        ldy #>$000a
        jsr strdigit
        lda lhslo
        clc
        adc #'0'
        jsr strputchar
        ldz #0
        lda stridx
        sta [varptr],z
        lda strdstlo
        sta exprlo
        lda strdsthi
        sta exprhi
strfromintdone:
        rts
strputchar:
        inc stridx
        ldz stridx
        sta [varptr],z
        rts
strdigit:
        sta divlo
        sty divhi
        lda #'0'
        sta digit
strdigitloop:
        lda lhshi
        cmp divhi
        bcc strdigitdone
        bne strdigitsub
        lda lhslo
        cmp divlo
        bcc strdigitdone
strdigitsub:
        sec
        lda lhslo
        sbc divlo
        sta lhslo
        lda lhshi
        sbc divhi
        sta lhshi
        inc digit
        jmp strdigitloop
strdigitdone:
        lda digit
        cmp #'0'
        bne strdigitemit
        lda printstarted
        beq strdigitreturn
        lda digit
strdigitemit:
        sta digit
        lda #1
        sta printstarted
        lda digit
        jsr strputchar
strdigitreturn:
        rts

;=======================================================================================
; VAL runtime
;=======================================================================================

valstr:
        lda exprlo
        ora exprhi
        bne valstrgo
        lda #0
        sta exprlo
        sta exprhi
        rts
valstrgo:
        lda exprlo
        sta strsrc1lo
        lda exprhi
        sta strsrc1hi
        jsr setstrptrsrc1
        ldz #0
        lda [varptr],z
        sta strlen
        lda #0
        sta exprlo
        sta exprhi
        sta stridx
        sta strdstidx
valskip:
        jsr valreadchar
        bcs valdone
        cmp #$20
        beq valskip
        cmp #'-'
        beq valminus
        cmp #'+'
        beq valdigitloop
        jmp valdigitgot
valminus:
        lda #1
        sta strdstidx
valdigitloop:
        jsr valreadchar
        bcs valapplysign
valdigitgot:
        cmp #'0'
        bcc valapplysign
        cmp #$3a
        bcs valapplysign
        sec
        sbc #'0'
        sta digit
        jsr inputmul10add
        jmp valdigitloop
valreadchar:
        lda stridx
        cmp strlen
        bcc valreadmore
        sec
        rts
valreadmore:
        inc stridx
        jsr setstrptrsrc1
        ldz stridx
        lda [varptr],z
        clc
        rts
valapplysign:
        lda strdstidx
        beq valdone
        lda exprlo
        ora exprhi
        beq valdone
        sec
        lda #0
        sbc exprlo
        sta exprlo
        lda #0
        sbc exprhi
        sta exprhi
valdone:
        rts

;=======================================================================================
; Far pointer helpers
;=======================================================================================

setstrptrexpr:
        lda exprlo
        sta varptr
        lda exprhi
        sta varptr+1
        jmp setstrptrbank
setstrptrsrc1:
        lda strsrc1lo
        sta varptr
        lda strsrc1hi
        sta varptr+1
        jmp setstrptrbank
setstrptrsrc2:
        lda strsrc2lo
        sta varptr
        lda strsrc2hi
        sta varptr+1
        jmp setstrptrbank
setstrptrdst:
        lda strdstlo
        sta varptr
        lda strdsthi
        sta varptr+1
        bra setstrptrbank

; the GC's pass-1 destination: the attic mirror of the final bank-1
; address ($801xxxx keeps clear of the relocation map at $800xxxx)
setstrptrdstmir:
        lda strdstlo
        sta varptr
        lda strdsthi
        sta varptr+1
        lda #$01
        sta varptr+2
        lda #$08
        sta varptr+3
        rts

setstrptrbank:
        lda #$01
        sta varptr+2
        lda #0
        sta varptr+3
        rts

outofstring:
        lda #16
        jmp rterror

;=======================================================================================
; String garbage collector
;=======================================================================================

; The GC compacts live strings to the top of the bank-1 heap by walking
; the root regions (slots holding heap pointers). Hazards handled here:
; (1) string ops hold source pointers in bank-0 registers across
; stralloc, so a GC fired mid-operation must relocate those too -- they
; are stashed as a synthetic first root region (strtslots tail); (2) the
; same heap string may be referenced by several slots, so every move is
; recorded in an old->new map (attic RAM, $8000000+) and later references
; reuse the mapped address instead of copying stale bytes; (3) roots are
; visited in table order, not address order, so a descending destination
; frontier could overwrite a not-yet-visited source -- pass 1 therefore
; writes every string to an attic mirror of its final address (megabyte
; $801xxxx, same 16-bit offset) and never touches the live heap; the
; packed block is CPU-copied back in one pass at the end.
strgc:
        lda #<strheaptop
        sta strdstlo
        lda #>strheaptop
        sta strdsthi
        lda #0
        sta gcmapcnt
        sta gcmapcnt+1
        lda #0                  ; stash the source-string registers as
        sta strtslots+40        ; walkable roots -- but only when the
        sta strtslots+41        ; interrupted routine flagged them live
        sta strtslots+42        ; (gcregmask), else they hold plain
        sta strtslots+43        ; numbers; zeros make the walker skip
        lda gcregmask
        and #1
        beq +
        lda strsrc1lo
        sta strtslots+40
        lda strsrc1hi
        sta strtslots+41
+       lda gcregmask
        and #2
        beq +
        lda strsrc2lo
        sta strtslots+42
        lda strsrc2hi
        sta strtslots+43
+       lda #0                  ; phase 0: the synthetic region --
        sta gcphase             ; string temp stack + register stash,
        lda #<strtslots         ; plain runtime storage in bank 0
        sta gcslotlo
        lda #>strtslots
        sta gcslothi
        lda #44
        sta gcbyteslo
        lda #0
        sta gcbyteshi
        jmp strgcslot
strgcroot:
        ldy #0
        lda (rtptr),y
        sta gcrootlo
        iny
        lda (rtptr),y
        sta gcroothi
        iny
        lda (rtptr),y
        sta gcbyteslo
        iny
        lda (rtptr),y
        sta gcbyteshi
        lda gcrootlo
        ora gcroothi
        ora gcbyteslo
        ora gcbyteshi
        beq strgcdone
        lda gcrootlo
        sta gcslotlo
        lda gcroothi
        sta gcslothi
strgcslot:
        lda gcbyteslo
        ora gcbyteshi
        beq strgcnextroot
        jsr strgcloadroot
        lda gcoldlo
        ora gcoldhi
        beq strgcslotnext
        jsr strgcmapfind        ; moved already? reuse its new address
        bcc +
        jsr strgcslotptr
        ldz #0
        lda gcnewlo
        sta [varptr],z
        ldz #1
        lda gcnewhi
        sta [varptr],z
        jmp strgcslotnext
+       lda gcoldlo
        sta strsrc1lo
        lda gcoldhi
        sta strsrc1hi
        jsr setstrptrsrc1
        ldz #0
        lda [varptr],z
        sta strlen1
        jsr strgcallocdst
strgccopyfwd:
        lda #0
        sta stridx
strgccopyfwdloop:
        jsr setstrptrsrc1
        ldz stridx
        lda [varptr],z
        pha
        jsr setstrptrdstmir     ; pass 1 writes the attic mirror only
        ldz stridx
        pla
        sta [varptr],z
        lda stridx
        cmp strlen1
        beq strgcupdateroot
        inc stridx
        jmp strgccopyfwdloop
strgcupdateroot:
        jsr strgcslotptr
        ldz #0
        lda strdstlo
        sta [varptr],z
        ldz #1
        lda strdsthi
        sta [varptr],z
        jsr strgcmapadd
strgcslotnext:
        clc
        lda gcslotlo
        adc #2
        sta gcslotlo
        lda gcslothi
        adc #0
        sta gcslothi
        sec
        lda gcbyteslo
        sbc #2
        sta gcbyteslo
        lda gcbyteshi
        sbc #0
        sta gcbyteshi
        jmp strgcslot
strgcnextroot:
        lda gcphase
        bne +
        lda #1                  ; register region done: walk the table
        sta gcphase
        lda rtstrroots
        sta rtptr
        lda rtstrroots+1
        sta rtptr+1
        jmp strgcroot
+       clc
        lda rtptr
        adc #4
        sta rtptr
        lda rtptr+1
        adc #0
        sta rtptr+1
        jmp strgcroot
strgcdone:
        lda strdstlo            ; copy the packed block back from the
        sta varptr              ; attic mirror in one ascending pass
        lda strdsthi            ; (only varptr+3 toggles: $08 = mirror,
        sta varptr+1            ; $00 = live bank-1 heap)
        lda #$01
        sta varptr+2
        ldz #0
_gccb_loop:
        lda varptr+1
        cmp #>strheaptop
        bne +
        lda varptr
        cmp #<strheaptop
        beq _gccb_done
+       lda #$08
        sta varptr+3
        lda [varptr],z
        tax
        lda #$00
        sta varptr+3
        txa
        sta [varptr],z
        inc varptr
        bne _gccb_loop
        inc varptr+1
        bra _gccb_loop
_gccb_done:
        lda strdstlo
        sta strheaplo
        lda strdsthi
        sta strheaphi
        lda gcregmask           ; hand the relocated pointers back to
        and #1                  ; the interrupted string operation
        beq +
        lda strtslots+40
        sta strsrc1lo
        lda strtslots+41
        sta strsrc1hi
+       lda gcregmask
        and #2
        beq +
        lda strtslots+42
        sta strsrc2lo
        lda strtslots+43
        sta strsrc2hi
+       rts

; relocation map in bank 4 from $0000: 4-byte (old, new) entries.
; find: C set + gcnewlo/hi on a hit. add: append gcold -> strdst.
strgcmapfind:
        lda #0
        sta varptr
        sta varptr+1
        lda #$00
        sta varptr+2
        lda #$08                ; relocation map lives in attic RAM
        sta varptr+3
        lda gcmapcnt
        sta gcmapi
        lda gcmapcnt+1
        sta gcmapi+1
_gcmf_loop:
        lda gcmapi
        ora gcmapi+1
        beq _gcmf_miss
        ldz #0
        lda [varptr],z
        cmp gcoldlo
        bne _gcmf_next
        ldz #1
        lda [varptr],z
        cmp gcoldhi
        bne _gcmf_next
        ldz #2
        lda [varptr],z
        sta gcnewlo
        ldz #3
        lda [varptr],z
        sta gcnewhi
        sec
        rts
_gcmf_next:
        clc
        lda varptr
        adc #4
        sta varptr
        lda varptr+1
        adc #0
        sta varptr+1
        lda gcmapi
        bne +
        dec gcmapi+1
+       dec gcmapi
        jmp _gcmf_loop
_gcmf_miss:
        clc
        rts

strgcmapadd:
        lda gcmapcnt            ; entry address = count * 4
        sta varptr
        lda gcmapcnt+1
        sta varptr+1
        asl varptr
        rol varptr+1
        asl varptr
        rol varptr+1
        lda #$00
        sta varptr+2
        lda #$08                ; relocation map lives in attic RAM
        sta varptr+3
        ldz #0
        lda gcoldlo
        sta [varptr],z
        inz
        lda gcoldhi
        sta [varptr],z
        inz
        lda strdstlo
        sta [varptr],z
        inz
        lda strdsthi
        sta [varptr],z
        inc gcmapcnt
        bne +
        inc gcmapcnt+1
+       rts
strgcloadroot:
        jsr strgcslotptr
        ldz #0
        lda [varptr],z
        sta gcoldlo
        ldz #1
        lda [varptr],z
        sta gcoldhi
        rts
; varptr = the current root slot, in the right bank for the phase
strgcslotptr:
        lda gcslotlo
        sta varptr
        lda gcslothi
        sta varptr+1
        lda gcphase
        bne +
        lda #0                  ; the synthetic region is runtime
        sta varptr+2            ; storage in bank 0
        sta varptr+3
        rts
+       jmp setstrptrbank

strgcallocdst:
        sec
        lda strdstlo
        sbc strlen1
        sta strdstlo
        lda strdsthi
        sbc #0
        sta strdsthi
        sec
        lda strdstlo
        sbc #1
        sta strdstlo
        lda strdsthi
        sbc #0
        sta strdsthi
        rts

;=======================================================================================
; Runtime storage
;=======================================================================================

; program header vectors, copied by rtinit
rtvheapend:   .byte 0,0
rtdatastart:  .byte 0,0
rtdataend:    .byte 0,0
rtstrroots:   .byte 0,0
rtfltinit:    .byte 0,0
rtlinetab:    .byte 0,0
rtgfxflag:    .byte 0,0
rtd030save:   .byte 0
rtspsave:     .byte 0
snd_shutptr:  .word rtshutnop
scr_c:        .byte 0,0
scr_r:        .byte 0
cur_c:        .byte 0
cur_r:        .byte 0
win_i:        .byte 0
win_a:        .fill 5, 0
key_n:        .byte 0
key_new:      .byte 0
key_old:      .byte 0
key_off:      .byte 0
key_tail:     .byte 0
key_srci:     .byte 0
key_dsti:     .byte 0
key_byte:     .byte 0
fg_cnt:       .byte 0,0
fg_addr:      .byte 0,0
exprb2:       .byte 0
exprb3:       .byte 0
dma_i:        .byte 0
dma_tmp:      .byte 0
dma_args:     .fill 36, 0
dmalist:      .fill 18, 0
cur_bank:     .byte 128
boot_addr:    .byte 0,0
sprs_len:     .byte 0
bit_addr:     .byte 0,0,0,0
bit_mask:     .byte 0
strtsp:       .byte 0
gfx_fn:       .byte 0
gfx_pen:      .byte 1
gfxres:       .byte 0
strtslots:    .fill 44, 0
sprsavbuf:    .fill 64, 0
sys_a:        .byte 0
sys_x:        .byte 0
sys_y:        .byte 0
sys_z:        .byte 0
sys_sr:       .byte 0
inputzpsave:  .fill 8, 0
edzpsave:     .fill 8, 0
gcphase:      .byte 0
gcregmask:    .byte 0
gcmapcnt:     .byte 0,0
gcmapi:       .byte 0,0
gcnewlo:      .byte 0
gcnewhi:      .byte 0
scr_off:      .byte 0,0
ch_off:       .byte 0,0
ch_k:         .byte 0
ti_base:      .byte 0,0,0
cmd_len:      .byte 0
cmd_i:        .byte 0
cmd_n:        .byte 0
cmd_j:        .byte 0
cmd_tmp:      .byte 0,0
cmdbuf:       .fill 48, 0
ds_len:       .byte 0
ds_code:      .byte 0
ds_valid:     .byte 0
dsbuf:        .fill 40, 0
bin_v:        .byte 0,0
bin_n:        .byte 0
bin_j:        .byte 0
bl_addr:      .byte 0,0
bl_end:       .byte 0,0
ti_ss:        .byte 0
ti_mm:        .byte 0
ti_hh:        .byte 0
ti_j:         .byte 0,0
rtpbhi:       .byte >rtpb       ; native writer patches this during copy
mthbuf:       .fill 21, 0
mth_ptr:      .byte 0,0
mth_n:        .byte 0
mth_sgn:      .byte 0
mth_sgn2:     .byte 0
mth_r1:       .byte 0
mth_r2:       .byte 0
mth_e:        .byte 0
mth_e2:       .byte 0
mod_a:        .byte 0,0
mod_r:        .byte 0,0
slp_last:     .byte 0
slp_nz:       .byte 0
wt_addr:      .byte 0,0
wt_and:       .byte 0
wt_xor:       .byte 0
err_no:       .byte 0

; MFLP float accumulators (unpacked)
facexp:       .byte 0
facm0:        .byte 0
facm1:        .byte 0
facm2:        .byte 0
facm3:        .byte 0
facsgn:       .byte 0
facext:       .byte 0
argexp:       .byte 0
argm0:        .byte 0
argm1:        .byte 0
argm2:        .byte 0
argm3:        .byte 0
argsgn:       .byte 0
argext:       .byte 0
qint_lost:    .byte 0
vflt_sign:    .byte 0
vflt_decexp:  .byte 0
vflt_frac:    .byte 0
vflt_eexp:    .byte 0
vflt_esign:   .byte 0
vflt_digit:   .byte 0
vflt_y:       .byte 0
vflt_scale:   .byte 0
fout_dexp:    .byte 0
fout_p:       .byte 0
fout_val0:    .byte 0
fout_val1:    .byte 0
fout_val2:    .byte 0
fout_val3:    .byte 0
fout_idx:     .byte 0
fout_digit:   .byte 0
fout_last:    .byte 0
fout_buf:     .fill 9, 0
FLT_STACK_MAX = 8
fltsp:        .byte 0
fltstack:     .fill FLT_STACK_MAX * 5, 0
rndseed:      .fill 4, 0
sqrx:         .fill 5, 0
sqry:         .fill 5, 0
sqr_it:       .byte 0
pow_e:        .byte 0,0
pow_neg:      .byte 0
ti_lo:        .byte 0
instr_pos:    .byte 0
hex_val:      .byte 0,0
fio_lf:       .byte 0
fio_dev:      .byte 0
fio_sa:       .byte 0
fio_name_lo:  .byte 0
fio_name_hi:  .byte 0
fio_out:      .byte 0
traplo:       .byte 0
traphi:       .byte 0
rt_er:        .byte 0
rt_el:        .byte 0,0
curline:      .byte 0,0
rtjmp:        .byte 0,0

snd_pdir:     .fill 6, 0
snd_phase:    .fill 6, 0
snd_vectab:   .fill 64, 0       ; KERNAL vector table copy (with headroom)

; integer runtime storage
exprlo:       .byte 0
exprhi:       .byte 0
lhslo:        .byte 0
lhshi:        .byte 0
resultlo:     .byte 0
resulthi:     .byte 0
quotlo:       .byte 0
quothi:       .byte 0
remlo:        .byte 0
remhi:        .byte 0
divlo:        .byte 0
divhi:        .byte 0
digit:        .byte 0
printstarted: .byte 0
printcol:     .byte 0
arrptrlo:     .byte 0
arrptrhi:     .byte 0
dataptrlo:    .byte 0
dataptrhi:    .byte 0
strheaplo:    .byte 0
strheaphi:    .byte 0
strmarksp:    .byte 0
strgctried:   .byte 0
strmarklo:    .fill 8,0
strmarkhi:    .fill 8,0
gcrootlo:     .byte 0
gcroothi:     .byte 0
gcbyteslo:    .byte 0
gcbyteshi:    .byte 0
gcslotlo:     .byte 0
gcslothi:     .byte 0
gcoldlo:      .byte 0
gcoldhi:      .byte 0
strlen:       .byte 0
strlen1:      .byte 0
strlen2:      .byte 0
stridx:       .byte 0
strdstidx:    .byte 0
strcmpchar:   .byte 0
strsrcoff:    .byte 0
strarg1lo:    .byte 0
strarg1hi:    .byte 0
strsrc1lo:    .byte 0
strsrc1hi:    .byte 0
strsrc2lo:    .byte 0
strsrc2hi:    .byte 0
strdstlo:     .byte 0
strdsthi:     .byte 0

; print runtime storage
sr: .byte 0
scl:.byte 0
sch:.byte 0
sf: .byte 0

; input runtime storage
inputpos:     .byte 0
inputlen:     .byte 0
inputfieldstart: .byte 0
inputneg:     .byte 0
inputdigits:  .byte 0
inputbuf:     .fill 81,0


; MOD(a,b): 16-bit remainder by shift-subtract; b=0 raises DIV BY ZERO
modseta:
        lda exprlo
        sta mod_a
        lda exprhi
        sta mod_a+1
        rts

modf:
        lda exprlo
        ora exprhi
        bne +
        lda #20
        jmp rterror
+       lda #0
        sta mod_r
        sta mod_r+1
        ldx #16
_modf_loop:
        asl mod_a
        rol mod_a+1
        rol mod_r
        rol mod_r+1
        lda mod_r
        sec
        sbc exprlo
        tay
        lda mod_r+1
        sbc exprhi
        bcc _modf_next
        sta mod_r+1
        sty mod_r
        inc mod_a
_modf_next:
        dex
        bne _modf_loop
        lda mod_r
        sta exprlo
        lda mod_r+1
        sta exprhi
        rts

; SLEEP seconds (float in FAC): frame-granular wait on FRAMECOUNT
sleepf:
        lda facexp              ; remember a nonzero argument
        sta slp_nz
        lda #<cfifty
        ldy #>cfifty
        jsr fldca
        jsr fmul
        lda #<chalf2            ; round to nearest frame: MFLP products
        ldy #>chalf2            ; like 0.02*50 can land just under 1.0,
        jsr fldca               ; and flooring made short sleeps vanish
        jsr fadd
        jsr qint                ; exprlo/hi = frames
        lda exprlo
        ora exprhi
        bne +
        lda slp_nz
        beq _sleepf_zero
        inc exprlo              ; any nonzero sleep waits at least a frame
        bra +
_sleepf_zero:
        rts
+       lda $d7fa
        sta slp_last
_sleepf_loop:
        lda $d7fa
        cmp slp_last
        beq _sleepf_loop
        sta slp_last
        lda exprlo
        bne +
        dec exprhi
+       dec exprlo
        lda exprlo
        ora exprhi
        bne _sleepf_loop
        rts

; WAIT address, andmask [, xormask]
waitseta:
        lda exprlo
        sta wt_addr
        lda exprhi
        sta wt_addr+1
        rts

waitsetm:
        lda exprlo
        sta wt_and
        lda #0
        sta wt_xor
        rts

waitsetx:
        lda exprlo
        sta wt_xor
        rts

waitgo:
        lda wt_addr
        sta rtptr
        lda wt_addr+1
        sta rtptr+1
        ldy #0
_waitgo_loop:
        lda (rtptr),y
        and wt_and
        eor wt_xor
        beq _waitgo_loop
        rts

; FRE(1) = bank-1 string heap bottom minus the variable heap end;
; FRE(0) and FRE(-1) have no compiled equivalent and return 0
fref:
        lda exprlo
        cmp #1
        beq _fref_bank1
        lda #0
        sta exprlo
        sta exprhi
        jmp float16
_fref_bank1:
        lda strheaplo
        sec
        sbc rtvheapend
        sta exprlo
        lda strheaphi
        sbc rtvheapend+1
        sta exprhi
        pha
        jsr float16             ; result exceeds signed 16 bits: go float
        pla
        bpl _fref_done
        lda #<c65536
        ldy #>c65536
        jsr fldca
        jsr fadd
_fref_done:
        rts

; ERR$(n): our error message table covers the codes the runtime can
; raise; anything else out of 1-41 errors, in-range-but-unknown gets ""
errstrf:
        lda exprhi
        bne _errstrf_bad
        lda exprlo
        beq _errstrf_bad
        cmp #42
        bcs _errstrf_bad
        sta err_no
        ldx #0
_errstrf_scan:
        lda rterrtab,x
        beq _errstrf_empty      ; unknown in-range code: empty string
        cmp err_no
        beq _errstrf_found
        inx
        inx
        inx
        bra _errstrf_scan
_errstrf_found:
        lda rterrtab+1,x
        sta rtptr
        lda rterrtab+2,x
        sta rtptr+1
        ldy #0
_errstrf_len:
        lda (rtptr),y
        beq _errstrf_alloc
        iny
        bne _errstrf_len
_errstrf_alloc:
        sty strlen
        tya
        pha
        jsr stralloc
        pla
        sta strlen
        bcs _errstrf_done
        ldz #0
        lda strlen
        sta [varptr],z
        ldy #0
_errstrf_copy:
        cpy strlen
        beq _errstrf_done
        lda (rtptr),y
        inz
        sta [varptr],z
        iny
        bne _errstrf_copy
_errstrf_done:
        rts
_errstrf_empty:
        lda #0
        sta strlen
        jsr stralloc
        bcs _errstrf_done
        ldz #0
        lda #0
        sta [varptr],z
        rts

_errstrf_bad:
        lda #14
        jmp rterror

; 0.5
chalf2:
        .byte $80, $00, $00, $00, $00   ; 0.5
; 1.0
cone:
        .byte $81, $00, $00, $00, $00   ; 1.0
; 1/ln(10) and the PAL jiffy rate, packed MFLP
c1oln10:
        .byte $7f, $5e, $5b, $d8, $a9
c65536:
        .byte $91, $00, $00, $00, $00
cfifty:
        .byte $86, $48, $00, $00, $00

fldc:
        sta rtfltptr
        sty rtfltptr+1
        ldy #0
        lda (rtfltptr),y
        sta facexp
        bne +
        lda #0
        sta facm0
        sta facm1
        sta facm2
        sta facm3
        sta facsgn
        sta facext
        rts
+       iny
        lda (rtfltptr),y
        pha
        ora #$80
        sta facm0
        lda #0
        sta facsgn
        pla
        bpl +
        lda #$ff
        sta facsgn
+       iny
        lda (rtfltptr),y
        sta facm1
        iny
        lda (rtfltptr),y
        sta facm2
        iny
        lda (rtfltptr),y
        sta facm3
        lda #0
        sta facext
        rts

; packed 5-byte constant at A/Y (bank 0) -> ARG
fldca:
        sta rtfltptr
        sty rtfltptr+1
        ldy #0
        lda (rtfltptr),y
        sta argexp
        bne +
        lda #0
        sta argm0
        sta argm1
        sta argm2
        sta argm3
        sta argsgn
        sta argext
        rts
+       iny
        lda (rtfltptr),y
        pha
        ora #$80
        sta argm0
        lda #0
        sta argsgn
        pla
        bpl +
        lda #$ff
        sta argsgn
+       iny
        lda (rtfltptr),y
        sta argm1
        iny
        lda (rtfltptr),y
        sta argm2
        iny
        lda (rtfltptr),y
        sta argm3
        lda #0
        sta argext
        rts

; FAC snapshots in mthbuf: X = 0, 7, or 14
fsavb:
        lda facexp
        sta mthbuf,x
        lda facm0
        sta mthbuf+1,x
        lda facm1
        sta mthbuf+2,x
        lda facm2
        sta mthbuf+3,x
        lda facm3
        sta mthbuf+4,x
        lda facsgn
        sta mthbuf+5,x
        lda facext
        sta mthbuf+6,x
        rts

frstb:
        lda mthbuf,x
        sta facexp
        lda mthbuf+1,x
        sta facm0
        lda mthbuf+2,x
        sta facm1
        lda mthbuf+3,x
        sta facm2
        lda mthbuf+4,x
        sta facm3
        lda mthbuf+5,x
        sta facsgn
        lda mthbuf+6,x
        sta facext
        rts

fargb:
        lda mthbuf,x
        sta argexp
        lda mthbuf+1,x
        sta argm0
        lda mthbuf+2,x
        sta argm1
        lda mthbuf+3,x
        sta argm2
        lda mthbuf+4,x
        sta argm3
        lda mthbuf+5,x
        sta argsgn
        lda mthbuf+6,x
        sta argext
        rts


; T@& and C@&: reserved array variables reading/writing the screen
; code / colour code at (column, row). Screen RAM moves on the MEGA65,
; so the address comes from SCRNPTR ($d060-$d062) and the line step
; from $d058/$d059 each access; colour RAM is $ff80000 + COLPTR
; ($d064/5) + the same offset. Out-of-range throws ARRAY BOUNDS.
tcsetc:
        lda exprlo
        sta scr_c
        lda exprhi
        sta scr_c+1
        rts

tcsetr:
        lda exprlo
        sta scr_r
        rts

; shared: bounds check and offset = row*linestep + col into scr_off
scroffs:
        lda scr_c+1             ; col must fit the line step
        bne _scroffs_bad
        lda scr_c
        cmp $d058
        bcs _scroffs_bad
        lda scr_r
        cmp #25
        bcs _scroffs_bad
        lda scr_r               ; row * linestep on the math unit
        sta $d770
        lda #0
        sta $d771
        sta $d772
        sta $d773
        lda $d058
        sta $d774
        lda $d059
        sta $d775
        lda #0
        sta $d776
        sta $d777
        lda $d778
        clc
        adc scr_c
        sta scr_off
        lda $d779
        adc #0
        sta scr_off+1
        rts
_scroffs_bad:
        pla                     ; abandon the caller
        pla
        lda #18                 ; ARRAY BOUNDS (bad subscript)
        jmp rterror

; far pointer to the screen cell (borrows varptr, restores the bank-1
; invariant afterwards like tistr does)
scrptr:
        jsr scroffs
        lda $d060
        clc
        adc scr_off
        sta varptr
        lda $d061
        adc scr_off+1
        sta varptr+1
        lda $d062
        adc #0
        sta varptr+2
        lda #0
        sta varptr+3
        rts

colptr:
        jsr scroffs
        lda $d064
        clc
        adc scr_off
        sta varptr
        lda $d065
        adc scr_off+1
        sta varptr+1
        lda #$f8
        adc #0
        sta varptr+2
        lda #$0f
        sta varptr+3
        rts

scrrestore:
        lda #1                  ; varptr's bank-1 invariant
        sta varptr+2
        lda #0
        sta varptr+3
        rts

tscrf:
        jsr scrptr
        ldz #0
        lda [varptr],z
        sta exprlo
        lda #0
        sta exprhi
        jmp scrrestore

tscrw:
        lda exprlo
        pha
        jsr scrptr
        ldz #0
        pla
        sta [varptr],z
        jmp scrrestore

cscrf:
        jsr colptr
        ldz #0
        lda [varptr],z
        sta exprlo
        lda #0
        sta exprhi
        jmp scrrestore

cscrw:
        lda exprlo
        pha
        jsr colptr
        ldz #0
        pla
        sta [varptr],z
        jmp scrrestore

; screen attributes: BORDER/BACKGROUND take the full palette index;
; FOREGROUND/COLOR set the text colour through the PETSCII colour
; codes (exact for 0-15; 16-31 fall back to the low nibble until the
; KERNAL's colour cell is identified). CHARDEF pokes the VIC character
; generator at $ff7e000.
bdrset:
        lda exprlo
        sta $d020
        rts

bkgset:
        lda exprlo
        sta $d021
        rts

fgtab:
        .byte 144,   5,  28, 159, 156,  30,  31, 158
        .byte 129, 149, 150, 151, 152, 153, 154, 155

fgset:
        lda exprhi
        bne _fgset_bad
        lda exprlo
        cmp #16                 ; the ROM rejects 16+ despite the book's
        bcs _fgset_bad          ; documented 0-31 (user-tested V920413)
        tax
        lda fgtab,x
        jmp printch
_fgset_bad:
        lda #14                 ; ILLEGAL QUANTITY
        jmp rterror

chsetidx:
        lda exprlo              ; character index 0-255 -> *8 offset
        sta ch_off
        lda #0
        sta ch_off+1
        asl ch_off
        rol ch_off+1
        asl ch_off
        rol ch_off+1
        asl ch_off
        rol ch_off+1
        lda #0
        sta ch_k
        rts

; one bitmap byte; after 8 the offset rolls into the next character
chputb:
        lda varptr+2
        pha
        lda ch_off
        sta varptr
        lda ch_off+1
        clc
        adc #$e0
        sta varptr+1
        lda #$f7
        adc #0
        sta varptr+2
        lda #$0f
        sta varptr+3
        ldz ch_k
        lda exprlo
        sta [varptr],z
        pla
        sta varptr+2
        lda #0
        sta varptr+3
        inc ch_k
        lda ch_k
        cmp #8
        bcc +
        lda #0
        sta ch_k
        clc
        lda ch_off
        adc #8
        sta ch_off
        bcc +
        inc ch_off+1
+       rts

rtsndshut:
        jmp (snd_shutptr)
rtshutnop:
        rts

;=======================================================================================
; Tier-1 function runtime: RND, SQR, ASC, TAB(, SPC(, POS
;=======================================================================================

; 32-bit LCG stepped on the hardware multiplier; result becomes a float in
; [0, 1). Seeded from the CIA timer by rtinit.
rndf:
        lda rndseed
        sta $d770
        lda rndseed+1
        sta $d771
        lda rndseed+2
        sta $d772
        lda rndseed+3
        sta $d773
        lda #$0d                ; 1664525 = $0019660d
        sta $d774
        lda #$66
        sta $d775
        lda #$19
        sta $d776
        lda #$00
        sta $d777
-       bit $d70f
        bvs -
        clc                     ; + 1013904223 = $3c6ef35f
        lda $d778
        adc #$5f
        sta rndseed
        lda $d779
        adc #$f3
        sta rndseed+1
        lda $d77a
        adc #$6e
        sta rndseed+2
        lda $d77b
        adc #$3c
        sta rndseed+3
        ; float in [0,1): mantissa = seed, exponent 0 -> fnorm cleans up
        lda rndseed+3
        sta facm0
        lda rndseed+2
        sta facm1
        lda rndseed+1
        sta facm2
        lda rndseed
        sta facm3
        lda #$80
        sta facexp
        lda #0
        sta facsgn
        sta facext
        jmp fnorm

; FAC = sqrt(FAC) by Newton iteration: y' = (y + x/y) / 2, six rounds,
; initial guess by halving the exponent. Negative input is treated as
; positive (interpreted BASIC errors instead).
sqrf:
        lda facexp
        bne +
        rts
+       lda #0
        sta facsgn
        jsr fsavex
        lda facexp              ; y0: halve the (excess-128) exponent
        sec
        sbc #$80
        cmp #$80                ; arithmetic halve for negative exponents
        ror
        clc
        adc #$80
        sta facexp
        jsr fsavey
        lda #6
        sta sqr_it
_sqr_loop:
        jsr floadx_arg          ; ARG = x
        jsr floady_fac          ; FAC = y
        jsr fdiv                ; FAC = x / y
        jsr floady_arg          ; ARG = y
        jsr fadd                ; FAC = y + x/y
        dec facexp              ; / 2, exact
        jsr fsavey
        dec sqr_it
        bne _sqr_loop
        rts

fsavex:
        lda facexp
        sta sqrx
        lda facm0
        sta sqrx+1
        lda facm1
        sta sqrx+2
        lda facm2
        sta sqrx+3
        lda facm3
        sta sqrx+4
        rts

fsavey:
        lda facexp
        sta sqry
        lda facm0
        sta sqry+1
        lda facm1
        sta sqry+2
        lda facm2
        sta sqry+3
        lda facm3
        sta sqry+4
        rts

floadx_arg:
        lda sqrx
        sta argexp
        lda sqrx+1
        sta argm0
        lda sqrx+2
        sta argm1
        lda sqrx+3
        sta argm2
        lda sqrx+4
        sta argm3
        lda #0
        sta argsgn
        sta argext
        rts

floady_arg:
        lda sqry
        sta argexp
        lda sqry+1
        sta argm0
        lda sqry+2
        sta argm1
        lda sqry+3
        sta argm2
        lda sqry+4
        sta argm3
        lda #0
        sta argsgn
        sta argext
        rts

floady_fac:
        lda sqry
        sta facexp
        lda sqry+1
        sta facm0
        lda sqry+2
        sta facm1
        lda sqry+3
        sta facm2
        lda sqry+4
        sta facm3
        lda #0
        sta facsgn
        sta facext
        rts

; first character code of the string whose heap ref is in exprlo/exprhi
ascstr:
        lda exprlo
        ora exprhi
        beq _ascstr_zero
        jsr setstrptrexpr
        ldz #0
        lda [varptr],z
        beq _ascstr_zero
        ldz #1
        lda [varptr],z
        sta exprlo
        lda #0
        sta exprhi
        rts
_ascstr_zero:
        lda #0
        sta exprlo
        sta exprhi
        rts

; print spaces until the real cursor column reaches exprlo (TAB target)
tabto:
-       sec
        jsr kernalplot          ; returns row in X, column in Y
        cpy exprlo
        bcs +
        lda #' '
        jsr printch
        bra -
+       rts

; print exprlo spaces
spcn:
        lda exprlo
        beq +
-       lda #' '
        jsr printch
        dec exprlo
        bne -
+       rts

; CURSOR col,row positioning: curinit snapshots the current position
; so omitted arguments keep their value; setters overwrite; curgo plots
curinit:
        phx
        phy
        sec
        jsr kernalplot          ; row in X, column in Y
        stx cur_r
        sty cur_c
        ply
        plx
        rts

cursetc:
        lda exprlo
        sta cur_c
        rts

cursetr:
        lda exprlo
        sta cur_r
        rts

curgo:
        phx
        phy
        ldx cur_r
        ldy cur_c
        clc
        jsr kernalplot
        ply
        plx
        rts

; WINDOW l,t,r,b[,clear]: winrst/winarg stage the arguments, wingo
; releases any old window (home-home), marks the corners with the
; editor's printable ESC T / ESC B at PLOT-positioned cursor spots,
; and clears inside the window when the flag argument is nonzero
winrst:
        lda #0
        sta win_i
        rts

winarg:
        ldx win_i
        cpx #5
        bcs +
        lda exprlo
        sta win_a,x
        inc win_i
+       rts

wingo:
        lda #$13                ; home-home: back to the full screen
        jsr kernalchrout
        lda #$13
        jsr kernalchrout
        phx
        phy
        ldx win_a+1             ; PLOT wants row in X, column in Y
        ldy win_a+0
        clc
        jsr kernalplot
        lda #$1b
        jsr kernalchrout
        lda #$54                ; ESC T: top-left corner
        jsr kernalchrout
        sec                     ; once the top-left is set, PLOT works
        lda win_a+3             ; window-relative -- aim at the corner
        sbc win_a+1             ; as (bottom-top, right-left)
        tax
        sec
        lda win_a+2
        sbc win_a+0
        tay
        clc
        jsr kernalplot
        lda #$1b
        jsr kernalchrout
        lda #$42                ; ESC B: bottom-right corner
        jsr kernalchrout
        lda #$13                ; home the cursor inside the window,
        jsr kernalchrout        ; like the ROM's WINDOW does
        ply
        plx
        lda #0
        sta printcol
        lda win_i
        cmp #5
        bcc +
        lda win_a+4
        beq +
        lda #$93                ; clear flag: clear inside the window
        jsr kernalchrout
+       rts

; KEY n,s$: rewrite the editor's function-key table in place.
; Probe-verified layout: 16 length bytes at $1000 (F1..), string data
; packed at $1010, 240 bytes capacity. keysetn stages the key number,
; keysetgo repacks (shift tail, copy new text, update length).
keysetn:
        ldx exprlo
        dex
        cpx #16
        bcc +
        lda #14                 ; ILLEGAL QUANTITY
        jmp rterror
+       stx key_n
        rts

keysetgo:
        lda #0
        sta key_new
        lda exprlo
        ora exprhi
        beq +
        jsr setstrptrexpr
        ldz #0
        lda [varptr],z
        sta key_new
+       ldx #0                  ; offset of slot n = sum of lengths 0..n-1
        lda #0
_ks_off:
        cpx key_n
        beq _ks_have_off
        clc
        adc $1000,x
        inx
        bra _ks_off
_ks_have_off:
        sta key_off
        ldx key_n
        lda $1000,x
        sta key_old
        lda #0                  ; tail = sum of lengths after slot n
        ldx key_n
        inx
_ks_tail:
        cpx #16
        beq _ks_have_tail
        clc
        adc $1000,x
        inx
        bra _ks_tail
_ks_have_tail:
        sta key_tail
        clc                     ; capacity: off + new + tail <= 240
        lda key_off
        adc key_new
        bcs _ks_err
        adc key_tail
        bcs _ks_err
        cmp #241
        bcs _ks_err
        clc
        lda key_off
        adc key_old
        sta key_srci            ; tail currently starts here
        clc
        lda key_off
        adc key_new
        sta key_dsti            ; and moves here
        lda key_new
        cmp key_old
        beq _ks_copy
        bcc _ks_shrink
        ldx key_tail            ; growing: move the tail upward from
_ks_grow:                       ; its high end so bytes never collide
        cpx #0
        beq _ks_copy
        dex
        txa
        clc
        adc key_srci
        tay
        lda $1010,y
        sta key_byte
        txa
        clc
        adc key_dsti
        tay
        lda key_byte
        sta $1010,y
        bra _ks_grow
_ks_shrink:
        ldx #0                  ; shrinking: move it downward forwards
_ks_shr:
        cpx key_tail
        beq _ks_copy
        txa
        clc
        adc key_srci
        tay
        lda $1010,y
        sta key_byte
        txa
        clc
        adc key_dsti
        tay
        lda key_byte
        sta $1010,y
        inx
        bra _ks_shr
_ks_copy:
        lda key_new
        beq _ks_len
        ldz #1
        ldx #0
_ks_cpy:
        cpx key_new
        beq _ks_len
        txa
        clc
        adc key_off
        tay
        lda [varptr],z
        sta $1010,y
        inz
        inx
        bra _ks_cpy
_ks_len:
        ldx key_n
        lda key_new
        sta $1000,x
        rts
_ks_err:
        lda #14
        jmp rterror

; RCURSOR colvar, rowvar readers (zero-based, like the ROM)
curcolf:
        phx
        phy
        sec
        jsr kernalplot
        sty exprlo
        lda #0
        sta exprhi
        ply
        plx
        rts

currowf:
        phx
        phy
        sec
        jsr kernalplot
        stx exprlo
        lda #0
        sta exprhi
        ply
        plx
        rts

; current cursor column
posf:
        sec
        jsr kernalplot
        sty exprlo
        lda #0
        sta exprhi
        rts

; FAC = ARG ^ int(FAC): binary exponentiation with fmul; negative
; exponents via a final reciprocal. 0^0 = 1 like the interpreter.
fpowi:
        jsr qint                ; exponent
        lda exprhi
        sta pow_neg
        bpl +
        sec                     ; |e|
        lda #0
        sbc exprlo
        sta exprlo
        lda #0
        sbc exprhi
        sta exprhi
+       lda exprlo
        sta pow_e
        lda exprhi
        sta pow_e+1
        jsr fmovfa              ; FAC = base
        jsr fsavex              ; x-buffer = running square
        lda #1
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jsr fsavey              ; y-buffer = result, starts at 1
_fpow_loop:
        lda pow_e
        ora pow_e+1
        beq _fpow_done
        lda pow_e
        and #1
        beq _fpow_square
        jsr floady_fac          ; result = result * square
        jsr floadx_arg
        jsr fmul
        jsr fsavey
_fpow_square:
        lsr pow_e+1
        ror pow_e
        beq _fpow_check_done
_fpow_squared:
        jsr floadx_fac          ; square = square * square
        jsr floadx_arg
        jsr fmul
        jsr fsavex
        bra _fpow_loop
_fpow_check_done:
        lda pow_e+1
        bne _fpow_squared
        bra _fpow_loop
_fpow_done:
        jsr floady_fac
        lda pow_neg
        bpl +
        jsr fmovaf              ; 1 / result
        lda #1
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jsr fswapfa
        jsr fdiv
+       rts

floadx_fac:
        lda sqrx
        sta facexp
        lda sqrx+1
        sta facm0
        lda sqrx+2
        sta facm1
        lda sqrx+3
        sta facm2
        lda sqrx+4
        sta facm3
        lda #0
        sta facsgn
        sta facext
        rts

; USR(x): call the ML routine vectored at $02f8 like the ROM, but with
; a compiled-world convention: argument as a 16-bit int in A(lo)/Y(hi)
; (also exprlo/exprhi), result returned the same way. The ROM's
; FAC-based convention assumes interpreter internals we do not keep.

rtendcore:

.if RTLEVEL >= 1
;=======================================================================================
; Disk verbs: DOS command strings on the command channel (15,8,15),
; DS/DS$ drive status, BLOAD/BSAVE, DOPEN#/APPEND#/DCLOSE#. All KERNAL
; calls ride the fio ROM bridge like the rest of the file layer.
;=======================================================================================

; command prefixes, indexed: 0 s0: 1 r0: 2 c0: 3 n0: 4 cd: 5 v0 6 i0
cmdpretab:
        .byte $53, $30, $3a     ; S0:  (PETSCII uppercase for DOS)
        .byte $52, $30, $3a     ; R0:
        .byte $43, $30, $3a     ; C0:
        .byte $4e, $30, $3a     ; N0:
        .byte $43, $44, $3a     ; CD:
        .byte $56, $30, $00     ; V0
        .byte $49, $30, $00     ; I0
        .byte $00, $00, $00     ; 7: empty, plain filename

; A = prefix index: reset the buffer and append the 2-3 byte prefix
cmdpre:
        sta cmd_i
        lda #0
        sta cmd_len
        lda cmd_i
        asl a
        clc
        adc cmd_i               ; *3
        tax
        ldy #0
_cmdpre_loop:
        lda cmdpretab,x
        beq _cmdpre_done
        jsr cmdputc
        inx
        iny
        cpy #3
        bne _cmdpre_loop
_cmdpre_done:
        rts

cmdputc:
        ldx cmd_len
        cpx #48
        bcs +
        sta cmdbuf,x
        inc cmd_len
+       rts

cmdeq:
        lda #$3d                ; =
        bra cmdputc

; CONCAT tail: the buffer holds "C0:target=" and exprlo/exprhi still
; carries target; emit "0:target,0:append" -- the sources need explicit
; 0: drive prefixes or CBDOS quietly skips the append (probe-verified;
; the ROM's CONCAT sends this same form)
cmdcat:
        jsr _cmdcat_drv
        jsr cmdstr
        lda #$2c                ; ,
        jsr cmdputc
        jsr _cmdcat_drv
        bra cmdstashout
_cmdcat_drv:
        lda #$30                ; 0
        jsr cmdputc
        lda #$3a                ; :
        jmp cmdputc

; append the heap string whose descriptor is in exprlo/exprhi
cmdstr:
        lda exprlo
        ora exprhi
        beq _cmdstr_done
        jsr setstrptrexpr
        ldz #0
        lda [varptr],z
        sta cmd_n
        lda #0
        sta cmd_j
_cmdstr_loop:
        lda cmd_j
        cmp cmd_n
        beq _cmdstr_done
        inc cmd_j
        ldz cmd_j
        lda [varptr],z
        jsr cmdputc
        bra _cmdstr_loop
_cmdstr_done:
        rts

; RENAME/COPY stash the first string's descriptor across the second
; -- through the GC-visible temp stack, since evaluating the second
; string can collect
cmdstash:
        jmp strtpush

cmdstashout:
        jsr strtpop
        lda lhslo
        sta exprlo
        lda lhshi
        sta exprhi
        bra cmdstr

; send cmdbuf on the command channel: open 15,8,15,"cmd" then close
cmdgo:
        jsr fio_rom_on
        lda #15
        jsr kernalclose
        lda #0
        ldx #0
        jsr kernalsetbnk        ; command text in bank 0
        lda cmd_len
        ldx #<cmdbuf
        ldy #>cmdbuf
        jsr kernalsetnam
        lda #15
        ldx #8
        ldy #15
        jsr kernalsetlfs
        jsr kernalopen
        lda #15
        jsr kernalclose
        jmp fio_rom_off

; DS: read the drive status line, cache the text and the 2-digit code
dsreadf:
        jsr fio_rom_on
        lda #15
        jsr kernalclose
        lda #0
        ldx #0
        jsr kernalsetbnk
        lda #0
        jsr kernalsetnam
        lda #15
        ldx #8
        ldy #15
        jsr kernalsetlfs
        jsr kernalopen
        ldx #15
        jsr kernalchkin
        lda #0
        sta ds_len
_dsread_loop:
        jsr kernalchrin2
        cmp #13
        beq _dsread_done
        ldx ds_len
        cpx #40
        bcs _dsread_loop
        sta dsbuf,x
        inc ds_len
        bra _dsread_loop
_dsread_done:
        jsr kernalclrchn
        lda #15
        jsr kernalclose
        jsr fio_rom_off
        lda #1
        sta ds_valid
        lda dsbuf               ; two ASCII digits -> code
        sec
        sbc #$30
        asl a
        sta ds_code
        asl a
        asl a
        clc
        adc ds_code             ; *10
        sta ds_code
        lda dsbuf+1
        sec
        sbc #$30
        clc
        adc ds_code
        sta ds_code
        rts

; DS numeric intercept: fresh read each use, like the ROM
rdds:
        jsr dsreadf
        lda ds_code
        sta exprlo
        lda #0
        sta exprhi
        rts

; BOOT filename$: chain-load a PRG and jump to its header address.
; The loader runs from a trampoline at $1e00 because the incoming file
; may overwrite the runtime (including this routine); the KERNAL name
; pointer is latched before the jump and the target address is read
; from the file's two-byte header first.
bootgo:
        lda #7                  ; filename into cmdbuf, no DOS prefix
        jsr cmdpre
        jsr cmdstr
        jsr fio_rom_on
        lda #0                  ; read the PRG header for the start
        ldx #0
        jsr kernalsetbnk
        lda cmd_len
        ldx #<cmdbuf
        ldy #>cmdbuf
        jsr kernalsetnam
        lda #4
        ldx #8
        ldy #4                  ; sec 4: raw file read
        jsr kernalsetlfs
        jsr kernalopen
        bcs _boot_fail
        ldx #4
        jsr kernalchkin
        jsr kernalchrin2
        sta boot_addr
        jsr kernalchrin2
        sta boot_addr+1
        lda #4
        jsr kernalclose
        jsr kernalclrchn
        ; stage the real load
        lda #0
        ldx #0
        jsr kernalsetbnk
        lda cmd_len
        ldx #<cmdbuf
        ldy #>cmdbuf
        jsr kernalsetnam
        lda #1
        ldx #8
        ldy #1                  ; sec 1: honour the header address
        jsr kernalsetlfs
        jsr rtsndshut           ; unhook the IRQ engine
        lda rtd030save          ; restore the ROM banking the target
        sta $d030               ; will expect
        ldx #7                  ; hand the editor its zero page back
_boot_zp:
        lda edzpsave,x
        sta varptr,x
        dex
        bpl _boot_zp
        ldx #0                  ; copy the trampoline out of harm's way
_boot_copy:
        lda boottramp,x
        sta $1e00,x
        inx
        cpx #boottrampend-boottramp
        bne _boot_copy
        lda boot_addr
        sta $1e20
        lda boot_addr+1
        sta $1e21
        jmp $1e00
_boot_fail:
        lda #4
        jsr kernalclose
        jsr kernalclrchn
        jsr fio_rom_off
        lda #21                 ; FILE NOT FOUND-ish
        jmp rterror

; assembled for $1e00 (target address slot at $1e20)
boottramp:
        .logical $1e00
        lda #0
        ldx #$ff
        ldy #$ff
        jsr $ffd5               ; KERNAL LOAD (sec 1: header address)
        bcs _bt_fail
        jmp ($1e20)
_bt_fail:
        inc $d020               ; visible freeze on a failed chain
        bra _bt_fail
        .endlogical
boottrampend:

; bare DISK: read the drive status fresh and print it
dskst:
        lda #0
        sta ds_valid
        jsr dsstrf
        jsr printheapstr
        lda #$0d
        jmp printch

; DS$ string intercept: last cached status (reads once if never read)
dsstrf:
        lda ds_valid
        bne +
        jsr dsreadf
+       lda ds_len
        sta strlen
        pha
        jsr stralloc
        pla
        sta strlen
        bcs _dsstrf_done
        ldz #0
        lda strlen
        sta [varptr],z
        ldy #0
_dsstrf_loop:
        cpy strlen
        beq _dsstrf_done
        lda dsbuf,y
        inz
        sta [varptr],z
        iny
        bne _dsstrf_loop
_dsstrf_done:
        rts

; BLOAD name (already in cmdbuf via cmdpre-less cmdstr), P address
bloadgo:
        jsr fio_rom_on
        lda #0
        ldx #0
        jsr kernalsetbnk
        lda cmd_len
        ldx #<cmdbuf
        ldy #>cmdbuf
        jsr kernalsetnam
        lda #1
        ldx #8
        ldy #0                  ; secondary 0: load to the given address
        jsr kernalsetlfs
        lda #0                  ; load, not verify
        ldx bl_addr
        ldy bl_addr+1
        jsr kernalload
        jmp fio_rom_off

bladdr:
        lda exprlo
        sta bl_addr
        lda exprhi
        sta bl_addr+1
        rts

blend:
        lda exprlo
        sta bl_end
        lda exprhi
        sta bl_end+1
        rts

; BSAVE: name in cmdbuf, bl_addr..bl_end (end exclusive, KERNAL SAVE)
bsavego:
        jsr fio_rom_on
        lda #0
        ldx #0
        jsr kernalsetbnk
        lda cmd_len
        ldx #<cmdbuf
        ldy #>cmdbuf
        jsr kernalsetnam
        lda #1
        ldx #8
        ldy #1
        jsr kernalsetlfs
        lda bl_addr
        sta rtptr
        lda bl_addr+1
        sta rtptr+1
        lda #rtptr
        ldx bl_end
        ldy bl_end+1
        jsr kernalsave
        jmp fio_rom_off

; DOPEN#/APPEND#: channel in fio_lf, name in cmdbuf; append ,s,<mode>
; (A = mode letter) then open with sa = (channel & 13) + 2
dopmode:
        pha
        lda #$2c                ; ,S,
        jsr cmdputc
        lda #$53
        jsr cmdputc
        lda #$2c
        jsr cmdputc
        pla
        jsr cmdputc
        jsr fio_rom_on
        lda fio_lf
        jsr kernalclose
        lda #0
        ldx #0
        jsr kernalsetbnk
        lda cmd_len
        ldx #<cmdbuf
        ldy #>cmdbuf
        jsr kernalsetnam
        lda fio_lf
        and #13
        clc
        adc #2
        tay
        ldx #8
        lda fio_lf
        jsr kernalsetlfs
        jsr kernalopen
        jmp fio_rom_off

dopr:
        lda #$52                ; R
        bra dopmode
dopw:
        lda #$57                ; W
        bra dopmode
dopa:
        lda #$41                ; A
        bra dopmode

dclosech:
        jsr fio_rom_on
        lda fio_lf
        jsr kernalclose
        jmp fio_rom_off

fiodefaults:
        lda #8
        sta fio_dev
        lda #0
        sta fio_sa
        sta fio_name_lo
        sta fio_name_hi
        rts

fiosetlf:
        lda exprlo
        sta fio_lf
        rts

fiosetdev:
        lda exprlo
        sta fio_dev
        rts

fiosetsa:
        lda exprlo
        sta fio_sa
        rts

fiosetname:
        lda exprlo
        sta fio_name_lo
        lda exprhi
        sta fio_name_hi
        rts

fopen:
        jsr fio_rom_on
        lda fio_lf
        jsr kernalclose         ; forgiving re-open
        lda fio_name_lo
        ora fio_name_hi
        beq _fopen_noname
        lda #0                  ; data bank 0, filename in bank 1
        ldx #1
        jsr kernalsetbnk
        lda fio_name_lo
        sta varptr
        lda fio_name_hi
        sta varptr+1
        ldz #0
        lda [varptr],z
        pha
        lda fio_name_lo
        clc
        adc #1
        tax
        lda fio_name_hi
        adc #0
        tay
        pla
        jsr kernalsetnam
        bra _fopen_lfs
_fopen_noname:
        lda #0
        tax
        jsr kernalsetbnk
        lda #0
        tax
        tay
        jsr kernalsetnam
_fopen_lfs:
        lda fio_lf
        ldx fio_dev
        ldy fio_sa
        jsr kernalsetlfs
        jsr kernalopen
        jmp fio_rom_off

fclose:
        jsr fio_rom_on
        lda exprlo
        jsr kernalclose
        jsr kernalclrchn
        jmp fio_rom_off

fiochkout:
        jsr fio_rom_on
        ldx exprlo
        jsr kernalchkout
        jsr fio_rom_off
        lda #1
        sta fio_out
        rts

fiochkin:
        jsr fio_rom_on
        ldx exprlo
        jsr kernalchkin
        jmp fio_rom_off

fiodone:
        jsr fio_rom_on
        jsr kernalclrchn
        jsr fio_rom_off
        lda #0
        sta fio_out
        rts

; read one record (to CR or end of file) into inputbuf for the INPUT#
; field parsers
fioreadline:
        jsr fio_rom_on
        lda #0
        sta inputpos
        sta inputlen
_frl_loop:
        jsr kernalchrin2
        cmp #$0d
        beq _frl_done
        ldx inputlen
        cpx #80
        bcs _frl_status
        sta inputbuf,x
        inc inputlen
_frl_status:
        jsr kernalreadst
        beq _frl_loop
_frl_done:
        ldx inputlen
        lda #0
        sta inputbuf,x
        jmp fio_rom_off

; one byte from the selected input channel
fiogetbyte:
        jsr fio_rom_on
        jsr kernalchrin2
        jsr fio_rom_off
        sta exprlo
        lda #0
        sta exprhi
        rts

; one byte as a one-character heap string
fiogetstr:
        jsr fio_rom_on
        jsr kernalchrin2
        jsr fio_rom_off
        sta digit
        lda #1
        sta strlen
        jsr stralloc
        bcs _fiogetstr_done
        ldz #0
        lda #1
        sta [varptr],z
        ldz #1
        lda digit
        sta [varptr],z
        lda strdstlo
        sta exprlo
        lda strdsthi
        sta exprhi
_fiogetstr_done:
        rts

; ST: the KERNAL status byte
rdst:
        jsr fio_rom_on
        jsr kernalreadst
        jsr fio_rom_off
        sta exprlo
        lda #0
        sta exprhi
        rts

.fi

rtendfio:
.if RTLEVEL >= 2
;=======================================================================================
; Transcendental math: SIN COS TAN ATN LOG EXP over the MFLP core.
; Coefficients are generated and packed offline (Taylor/artanh series,
; Horner order); fpoly evaluates them. Three 7-byte buffers snapshot
; the unpacked FAC. fsub is ARG-FAC and fdiv is ARG/FAC throughout.
;=======================================================================================

; sin(2*pi*u), u^2-poly coeffs, highest power first
csin:
        .byte $84, $f1, $83, $a7, $ef   ; -15.094642576822984
        .byte $86, $28, $3c, $1a, $44   ; 42.058693944897634
        .byte $87, $99, $69, $66, $73   ; -76.70585975306136
        .byte $87, $23, $35, $e3, $3c   ; 81.60524927607504
        .byte $86, $a5, $5d, $e7, $31   ; -41.341702240399755
        .byte $83, $49, $0f, $da, $a2   ; 6.283185307179586
; quarter turn for cos
chalf:
        .byte $7f, $00, $00, $00, $00   ; 0.25
; 1/(2*pi)
cinv2pi:
        .byte $7e, $22, $f9, $83, $6e   ; 0.15915494309189535
; artanh series *2, highest first
clog:
        .byte $7e, $63, $8e, $38, $e4   ; 0.2222222222222222
        .byte $7f, $12, $49, $24, $92   ; 0.2857142857142857
        .byte $7f, $4c, $cc, $cc, $cd   ; 0.4
        .byte $80, $2a, $aa, $aa, $ab   ; 0.6666666666666666
        .byte $82, $00, $00, $00, $00   ; 2.0
; sqrt(0.5)
csqh:
        .byte $80, $35, $04, $f3, $34   ; 0.7071067811865476
; ln(sqrt(0.5))
clnsqh:
        .byte $7f, $b1, $72, $17, $f8   ; -0.3465735902799726
; ln 2
cln2:
        .byte $80, $31, $72, $17, $f8   ; 0.6931471805599453
; 1/ln 2
cinvln2:
        .byte $81, $38, $aa, $3b, $29   ; 1.4426950408889634
; exp Taylor, highest first
cexp:
        .byte $74, $50, $0d, $00, $d0   ; 0.0001984126984126984
        .byte $77, $36, $0b, $60, $b6   ; 0.001388888888888889
        .byte $7a, $08, $88, $88, $89   ; 0.008333333333333333
        .byte $7c, $2a, $aa, $aa, $ab   ; 0.041666666666666664
        .byte $7e, $2a, $aa, $aa, $ab   ; 0.16666666666666666
        .byte $80, $00, $00, $00, $00   ; 0.5
        .byte $81, $00, $00, $00, $00   ; 1.0
        .byte $81, $00, $00, $00, $00   ; 1.0
; atan t^2-poly coeffs, highest first
catn:
        .byte $7c, $70, $f0, $f0, $f1   ; 0.058823529411764705
        .byte $7d, $88, $88, $88, $89   ; -0.06666666666666667
        .byte $7d, $1d, $89, $d8, $9e   ; 0.07692307692307693
        .byte $7d, $ba, $2e, $8b, $a3   ; -0.09090909090909091
        .byte $7d, $63, $8e, $38, $e4   ; 0.1111111111111111
        .byte $7e, $92, $49, $24, $92   ; -0.14285714285714285
        .byte $7e, $4c, $cc, $cc, $cd   ; 0.2
        .byte $7f, $aa, $aa, $aa, $ab   ; -0.3333333333333333
        .byte $81, $00, $00, $00, $00   ; 1.0
; pi/4
cpi4:
        .byte $80, $49, $0f, $da, $a2   ; 0.7853981633974483
; pi/2
cpi2:
        .byte $81, $49, $0f, $da, $a2   ; 1.5707963267948966
; tan(pi/8)
ctan8:
        .byte $7f, $54, $13, $cc, $d0   ; 0.41421356237309503

; packed 5-byte constant at A/Y (bank 0) -> FAC
; FAC = poly(FAC): packed coeffs at A/Y (highest power first), X terms
fpoly:
        sta mth_ptr
        sty mth_ptr+1
        stx mth_n
        ldx #0
        jsr fsavb               ; z
        lda mth_ptr
        ldy mth_ptr+1
        jsr fldc
        jsr fpolyadv
_fpoly_loop:
        dec mth_n
        beq _fpoly_done
        ldx #0
        jsr fargb
        jsr fmul
        lda mth_ptr
        ldy mth_ptr+1
        jsr fldca
        jsr fadd
        jsr fpolyadv
        bra _fpoly_loop
_fpoly_done:
        rts

fpolyadv:
        lda mth_ptr
        clc
        adc #5
        sta mth_ptr
        bcc +
        inc mth_ptr+1
+       rts

; SIN(x): u = x/2pi, folded by symmetry to a in [0, 1/4], a*poly(a^2)
sinf:
        lda #<cinv2pi
        ldy #>cinv2pi
        jsr fldca
        jsr fmul
        ldx #7
        jsr fsavb               ; u
        jsr qint
        jsr float16             ; FAC = floor(u)
        ldx #7
        jsr fargb               ; ARG = u
        jsr fsub                ; frac = u - floor(u), [0,1)
        lda #<chalf2
        ldy #>chalf2
        jsr fldca
        jsr fcmp
        cmp #1
        bne _sinf_centered
        ldx #7
        jsr fsavb
        lda #<cone
        ldy #>cone
        jsr fldc
        ldx #7
        jsr fargb
        jsr fsub                ; frac - 1, now in [-1/2, 1/2]
_sinf_centered:
        lda facsgn
        sta mth_sgn
        lda #0
        sta facsgn              ; a = |frac|
        lda #<chalf
        ldy #>chalf
        jsr fldca
        jsr fcmp
        cmp #1
        bne _sinf_folded
        lda #<chalf2
        ldy #>chalf2
        jsr fldca
        jsr fsub                ; a = 1/2 - a
_sinf_folded:
        ldx #7
        jsr fsavb               ; a
        jsr fmovaf
        jsr fmul                ; z = a*a
        lda #<csin
        ldy #>csin
        ldx #6
        jsr fpoly
        ldx #7
        jsr fargb
        jsr fmul                ; a * poly
        lda mth_sgn
        beq _sinf_done
        lda facsgn
        eor #$ff
        sta facsgn
_sinf_done:
        rts

cosf:
        lda #<cpi2
        ldy #>cpi2
        jsr fldca
        jsr fadd
        bra sinf

tanf:
        ldx #14
        jsr fsavb
        jsr sinf
        jsr fpush
        ldx #14
        jsr frstb
        jsr cosf
        jsr fpoparg             ; ARG = sin
        jsr fdiv                ; sin/cos
        rts

; ATN(x): odd; reduce 1/x above 1, then (x-1)/(x+1) above tan(pi/8)
atnf:
        lda facsgn
        sta mth_sgn2
        lda #0
        sta facsgn
        sta mth_r1
        sta mth_r2
        lda #<cone
        ldy #>cone
        jsr fldca
        jsr fcmp
        cmp #1
        bne _atnf_le1
        inc mth_r1
        lda #<cone
        ldy #>cone
        jsr fldca
        jsr fdiv                ; 1/x
_atnf_le1:
        lda #<ctan8
        ldy #>ctan8
        jsr fldca
        jsr fcmp
        cmp #1
        bne _atnf_small
        inc mth_r2
        ldx #7
        jsr fsavb               ; x
        lda #<cone
        ldy #>cone
        jsr fldca
        jsr fadd                ; x+1
        ldx #14
        jsr fsavb
        lda #<cone
        ldy #>cone
        jsr fldc
        ldx #7
        jsr fargb
        jsr fsub                ; x-1
        jsr fpush
        ldx #14
        jsr frstb
        jsr fpoparg
        jsr fdiv                ; (x-1)/(x+1)
_atnf_small:
        ldx #7
        jsr fsavb               ; t
        jsr fmovaf
        jsr fmul                ; z = t*t
        lda #<catn
        ldy #>catn
        ldx #9
        jsr fpoly
        ldx #7
        jsr fargb
        jsr fmul
        lda mth_r2
        beq _atnf_nor2
        lda #<cpi4
        ldy #>cpi4
        jsr fldca
        jsr fadd
_atnf_nor2:
        lda mth_r1
        beq _atnf_nor1
        lda #<cpi2
        ldy #>cpi2
        jsr fldca
        jsr fsub                ; pi/2 - r
_atnf_nor1:
        lda mth_sgn2
        beq _atnf_done
        lda facsgn
        eor #$ff
        sta facsgn
_atnf_done:
        rts

; LOG(x): e*ln2 + ln(m), m in [1/2,1) via artanh((m-r)/(m+r)), r=sqrt(1/2)
logf:
        lda facexp
        beq _logf_err
        lda facsgn
        bne _logf_err
        lda facexp
        sec
        sbc #$80
        sta mth_e
        lda #$80
        sta facexp
        ldx #7
        jsr fsavb               ; m
        lda #<csqh
        ldy #>csqh
        jsr fldca
        jsr fadd                ; m + r
        ldx #14
        jsr fsavb
        lda #<csqh
        ldy #>csqh
        jsr fldc
        ldx #7
        jsr fargb
        jsr fsub                ; m - r
        jsr fpush
        ldx #14
        jsr frstb
        jsr fpoparg
        jsr fdiv                ; t
        ldx #7
        jsr fsavb
        jsr fmovaf
        jsr fmul                ; z = t*t
        lda #<clog
        ldy #>clog
        ldx #5
        jsr fpoly
        ldx #7
        jsr fargb
        jsr fmul                ; ln((1+t)/(1-t))
        lda #<clnsqh
        ldy #>clnsqh
        jsr fldca
        jsr fadd                ; ln m
        jsr fpush
        lda mth_e
        sta exprlo
        and #$80
        beq _logf_epos
        lda #$ff
        bra _logf_ehi
_logf_epos:
        lda #0
_logf_ehi:
        sta exprhi
        jsr float16
        lda #<cln2
        ldy #>cln2
        jsr fldca
        jsr fmul                ; e * ln2
        jsr fpoparg
        jsr fadd
        rts
_logf_err:
        lda #14                 ; ILLEGAL QUANTITY
        jmp rterror

; EXP(x): v = x/ln2, n = round(v), 2^n * e^((v-n)*ln2)
expf:
        lda #<cinvln2
        ldy #>cinvln2
        jsr fldca
        jsr fmul                ; v
        ldx #7
        jsr fsavb
        lda #<chalf2
        ldy #>chalf2
        jsr fldca
        jsr fadd
        jsr qint                ; n = floor(v + 1/2)
        lda exprlo
        sta mth_e
        lda exprhi
        sta mth_e2
        jsr float16             ; FAC = n
        ldx #7
        jsr fargb               ; ARG = v
        jsr fsub                ; f = v - n, |f| <= 1/2
        lda #<cln2
        ldy #>cln2
        jsr fldca
        jsr fmul                ; g = f*ln2
        lda #<cexp
        ldy #>cexp
        ldx #8
        jsr fpoly               ; e^g
        lda facexp
        beq _expf_done
        clc
        lda facexp
        adc mth_e
        tax                     ; new exponent low
        lda #0
        adc mth_e2              ; high + carry
        beq _expf_inrange
        cmp #$ff
        beq _expf_zero          ; negative sum: underflow to 0
        bra _expf_ovf
_expf_inrange:
        txa
        beq _expf_zero
        sta facexp
        bra _expf_done
_expf_zero:
        lda #0
        sta facexp
        sta facm0
        sta facm1
        sta facm2
        sta facm3
        sta facsgn
        sta facext
_expf_done:
        rts
_expf_ovf:
        lda #15                 ; OVERFLOW
        jmp rterror

log10f:
        jsr logf
        lda #<c1oln10
        ldy #>c1oln10
        jsr fldca
        jmp fmul

.fi

rtendmath:


.weak
RTLEVEL = 3                     ; 0 core, 1 +fio, 2 +math, 3 +sound
rtpb = $5400                    ; overridden by each generated OUT.ASM                    ; OUT.ASM sets 0 when the program uses no sound
.endweak

.if RTLEVEL >= 3

;=======================================================================================
; Optional sections below: programs that never use sound, PLAY, or
; sprites can set progbase to rtendcore (sectioned emission, later).
;=======================================================================================

;=======================================================================================
; PLAY: up to six note strings, one per voice -- 1-3 on SID1 ($d400),
; 4-6 on SID3 ($d440), distinct from SOUND's SID2/SID4. Each string is
; copied to a bank-0 track buffer at statement time; the IRQ tick parses
; notes incrementally. Notes A-G with # (sharp), $ (flat), . (dotted);
; durations W H Q I S persist until changed; R rests. Directives:
; On octave, Tn instrument (C128 envelope set), Un volume, L loop;
; Xn/Mn/Pn are parsed and ignored for now.
;=======================================================================================

PLAY_TRACK_LEN = 128

; per-semitone SID frequency, octave 7 (C..B); lower octaves shift right
play_notetab:
        .word 34334, 36376, 38539, 40830, 43258, 45830
        .word 48556, 51443, 54502, 57743, 61176, 64814

; note letter A-G -> semitone (C=0 D=2 E=4 F=5 G=7 A=9 B=11)
play_semitab:
        .byte 9, 11, 0, 2, 4, 5, 7

; W H Q I S in jiffies; recomputed by TEMPO, reset by bare PLAY
play_durtab:
        .byte 75, 37, 18, 9, 4
play_durdef:
        .byte 75, 37, 18, 9, 4

; ENVELOPE waveform code -> gate-on control (tri saw pulse noise ring)
play_wfmap:
        .byte $11, $21, $41, $81, $15

; TEMPO speed: whole note = 24/speed seconds = 1200/speed PAL jiffies,
; clamped to 255 since track countdowns are 8-bit
tempof:
        lda exprlo
        bne +
        rts
+       sta play_tdiv
        lda #<1200
        sta play_tacc
        lda #>1200
        sta play_tacc+1
        lda #0
        sta play_tq
_tempo_div:
        lda play_tacc
        sec
        sbc play_tdiv
        sta play_tacc
        lda play_tacc+1
        sbc #0
        sta play_tacc+1
        bcc _tempo_done
        inc play_tq
        bne _tempo_div
        lda #255                ; quotient saturated
        sta play_tq
_tempo_done:
        lda play_tq
        ldx #0
_tempo_store:
        sta play_durtab,x
        lsr a
        bne +
        lda #1                  ; every duration is at least one jiffy
+       inx
        cpx #5
        bne _tempo_store
        rts

; ENVELOPE n, attack, decay, sustain, release, waveform, pw --
; setters patch the slot tables in place so omitted args stay put
envsetn:
        lda exprlo
        cmp #10
        bcc +
        lda #0
+       sta play_envn
        rts

envseta:
        ldx play_envn
        lda exprlo
        asl a
        asl a
        asl a
        asl a
        sta play_tq
        lda play_envad,x
        and #$0f
        ora play_tq
        sta play_envad,x
        rts

envsetd:
        ldx play_envn
        lda exprlo
        and #$0f
        sta play_tq
        lda play_envad,x
        and #$f0
        ora play_tq
        sta play_envad,x
        rts

envsetss:
        ldx play_envn
        lda exprlo
        asl a
        asl a
        asl a
        asl a
        sta play_tq
        lda play_envsr,x
        and #$0f
        ora play_tq
        sta play_envsr,x
        rts

envsetr:
        ldx play_envn
        lda exprlo
        and #$0f
        sta play_tq
        lda play_envsr,x
        and #$f0
        ora play_tq
        sta play_envsr,x
        rts

envsetw:
        ldx play_envn
        lda exprlo
        cmp #5
        bcs +
        tay
        lda play_wfmap,y
        sta play_envwave,x
+       rts

envsetpw:
        ldx play_envn
        lda exprhi
        and #$0f
        sta play_envpw,x
        rts

; RPLAY(voice): nonzero while that voice's track is still playing
rplayf:
        ldx exprlo
        dex
        cpx #6
        bcc +
        ldx #0
+       lda play_act,x
        sta exprlo
        lda #0
        sta exprhi
        rts



; instrument envelopes 0-9 (C128 set): attack/decay, sustain/release,
; gate-on control value, pulse width high byte
play_envad:
        .byte $09, $c0, $00, $05, $94, $09, $09, $09, $89, $09
play_envsr:
        .byte $00, $c0, $f0, $50, $40, $21, $00, $90, $41, $00
play_envwave:
        .byte $41, $21, $11, $81, $11, $21, $41, $41, $41, $11
play_envpw:
        .byte $06, $00, $00, $00, $00, $00, $02, $08, $02, $00

play_voltab:
        .byte 0, 2, 3, 5, 7, 8, 10, 12, 13, 15

; voice register offsets from $d400: SID1 voices 1-3, SID3 voices 4-6
play_regoff:
        .byte $00, $07, $0e, $40, $47, $4e

play_buflo:
        .byte <(play_buf+0*PLAY_TRACK_LEN), <(play_buf+1*PLAY_TRACK_LEN)
        .byte <(play_buf+2*PLAY_TRACK_LEN), <(play_buf+3*PLAY_TRACK_LEN)
        .byte <(play_buf+4*PLAY_TRACK_LEN), <(play_buf+5*PLAY_TRACK_LEN)
play_bufhi:
        .byte >(play_buf+0*PLAY_TRACK_LEN), >(play_buf+1*PLAY_TRACK_LEN)
        .byte >(play_buf+2*PLAY_TRACK_LEN), >(play_buf+3*PLAY_TRACK_LEN)
        .byte >(play_buf+4*PLAY_TRACK_LEN), >(play_buf+5*PLAY_TRACK_LEN)

; load track playarg from the heap string in exprlo/exprhi (length-
; prefixed, bank 1), copied into a bank-0 track buffer for the ISR
playtrk:
        jsr sndinit             ; PLAY shares the sound IRQ hook
        ldx playarg
        lda #0
        sta play_act,x
        lda play_buflo,x
        sta rtfltptr
        lda play_bufhi,x
        sta rtfltptr+1
        lda exprlo
        ora exprhi
        beq _playtrk_done       ; empty string: track stays off
        jsr setstrptrexpr
        ldz #0
        lda [varptr],z
        sta play_cplen
        ldy #0
_playtrk_copy:
        cpy play_cplen
        beq _playtrk_copied
        cpy #PLAY_TRACK_LEN-1
        beq _playtrk_copied
        iny
        tya
        taz
        lda [varptr],z
        dey
        sta (rtfltptr),y
        iny
        bra _playtrk_copy
_playtrk_copied:
        lda #0
        sta (rtfltptr),y
        lda #0
        sta play_pos,x
        sta play_env,x
        sta play_rem,x
        sta play_loop,x
        lda #4
        sta play_oct,x
        lda play_durtab+2       ; quarter notes until changed
        sta play_dur,x
        lda snd_vol             ; volume must keep the FILTER mode bits:
        ora flt_mode            ; a raw write here bypassed the filter
        sta $d418               ; for every note PLAYed after a FILTER
        lda snd_vol
        ora flt_mode+1
        sta $d458
        lda #1
        sta play_act,x
_playtrk_done:
        rts

; bare PLAY and rtexit: stop and silence every track
playoff:
        ldx #4
_playoff_tempo:
        lda play_durdef,x
        sta play_durtab,x
        dex
        bpl _playoff_tempo
        ldx #5
_playoff_loop:
        lda #0
        sta play_act,x
        ldy play_regoff,x
        sta $d404,y
        dex
        bpl _playoff_loop
        rts

; one jiffy for all tracks; called from the sound ISR (A/X/Y saved there)
play_tick:
        lda rtfltptr            ; the ISR may interrupt mainline float code
        pha
        lda rtfltptr+1
        pha
        ldx #5
_ptick_loop:
        lda play_act,x
        beq _ptick_next
        lda play_rem,x
        beq _ptick_parse
        dec play_rem,x
        lda play_rem,x
        cmp #2                  ; release window before the next note
        bne _ptick_next
        lda play_ctrl,x
        and #$fe
        ldy play_regoff,x
        sta $d404,y
_ptick_next:
        dex
        bpl _ptick_loop
        pla
        sta rtfltptr+1
        pla
        sta rtfltptr
        rts

_ptick_parse:
        lda play_buflo,x
        sta rtfltptr
        lda play_bufhi,x
        sta rtfltptr+1
        lda #0
        sta play_acc            ; pending sharp/flat as signed semitones
        sta play_dot
_ptick_scan:
        ldy play_pos,x
        lda (rtfltptr),y
        bne _ptick_char
        lda play_loop,x         ; end of string: restart or stop
        beq _ptick_stop
        lda #0
        sta play_pos,x
        bra _ptick_scan
_ptick_stop:
        lda #0
        sta play_act,x
        ldy play_regoff,x
        sta $d404,y
        bra _ptick_next
_ptick_char:
        inc play_pos,x
        cmp #'#'
        bne +
        inc play_acc
        bra _ptick_scan
+       cmp #'$'
        bne +
        dec play_acc
        bra _ptick_scan
+       cmp #'.'
        bne +
        lda #1
        sta play_dot
        bra _ptick_scan
+       cmp #$52                ; R: rest
        beq _ptick_rest
        cmp #$57                ; W
        bne +
        ldy #0
        bra _ptick_setdur
+       cmp #$48                ; H
        bne +
        ldy #1
        bra _ptick_setdur
+       cmp #$51                ; Q
        bne +
        ldy #2
        bra _ptick_setdur
+       cmp #$49                ; I
        bne +
        ldy #3
        bra _ptick_setdur
+       cmp #$53                ; S
        bne +
        ldy #4
        bra _ptick_setdur
+       cmp #$4c                ; L: loop the whole string
        bne +
        lda #1
        sta play_loop,x
        bra _ptick_scan
+       cmp #$4f                ; O octave
        bne +
        jsr _ptick_digit
        cmp #7
        bcs _ptick_scan
        sta play_oct,x
        bra _ptick_scan
+       cmp #$54                ; T instrument
        bne +
        jsr _ptick_digit
        cmp #10
        bcs _ptick_scan
        sta play_env,x
        bra _ptick_scan
+       cmp #$55                ; U volume
        bne +
        jsr _ptick_digit
        cmp #10
        bcs _ptick_scan
        tay
        lda play_voltab,y
        sta snd_vol             ; U is the master volume; keep the
        ora flt_mode            ; FILTER mode bits when rewriting
        sta $d418
        lda snd_vol
        ora flt_mode+1
        sta $d458
        bra _ptick_scan
+       cmp #$58                ; X: filter this voice
        beq _ptick_xdir
        cmp #$4d                ; M: consume the digit, ignore
        beq _ptick_skiparg
        cmp #$50
        bne +
_ptick_skiparg:
        jsr _ptick_digit
        bra _ptick_scan
+       cmp #$41                ; A-G: a note
        bcc _ptick_scan
        cmp #$47+1
        bcs _ptick_scan
        sec
        sbc #$41
        tay
        lda play_semitab,y
        clc
        adc play_acc            ; sharps/flats, may cross the octave
        sta play_acc
        lda play_oct,x
        sta play_octw
        lda play_acc
        bpl +
        clc
        adc #12
        sta play_acc
        dec play_octw
+       cmp #12
        bcc +
        sbc #12
        sta play_acc
        inc play_octw
+       lda play_acc
        asl a
        tay
        lda play_notetab,y
        sta play_frq
        lda play_notetab+1,y
        sta play_frq+1
        lda #7
        sec
        sbc play_octw           ; octave 0-6 -> shift 7..1
        tay
_ptick_shift:
        lsr play_frq+1
        ror play_frq
        dey
        bne _ptick_shift
        ldy play_regoff,x
        lda #0                  ; gate off, reset envelope
        sta $d404,y
        lda play_frq
        sta $d400,y
        lda play_frq+1
        sta $d401,y
        lda play_env,x
        phx
        tax
        lda play_envad,x
        sta play_ad
        lda play_envsr,x
        sta play_sr
        lda play_envwave,x
        sta play_wv
        lda play_envpw,x
        plx
        sta $d403,y
        lda #0
        sta $d402,y
        lda play_ad
        sta $d405,y
        lda play_sr
        sta $d406,y
        lda play_wv
        sta play_ctrl,x
        sta $d404,y
_ptick_arm:
        lda play_dur,x
        ldy play_dot
        beq +
        lsr a
        clc
        adc play_dur,x          ; dotted: half again as long
+       sta play_rem,x
        jmp _ptick_next

_ptick_rest:
        lda play_ctrl,x
        and #$fe
        ldy play_regoff,x
        sta $d404,y
        bra _ptick_arm

_ptick_setdur:
        lda play_durtab,y
        sta play_dur,x
        bra _ptick_scan

_ptick_xdir:
        jsr _ptick_digit
        sta play_xt1             ; 0 = off, else on
        ldy #0
        txa                     ; track 0-5 -> SID index + voice bit
        cmp #3
        bcc +
        iny
        sec
        sbc #3
+       phx
        tax
        lda sprbit,x
        sta play_xt2
        lda play_xt1
        beq _ptick_xdir_off
        lda flt_rout,y
        ora play_xt2
        bra _ptick_xdir_wr
_ptick_xdir_off:
        lda play_xt2
        eor #$ff
        and flt_rout,y
_ptick_xdir_wr:
        sta flt_rout,y
        ora flt_res,y
        cpy #0
        bne _ptick_xdir_s2
        sta $d417
        bra _ptick_xdir_done
_ptick_xdir_s2:
        sta $d457
_ptick_xdir_done:
        plx
        jmp _ptick_scan

; read the digit after a directive letter; returns 0-9 in A
_ptick_digit:
        ldy play_pos,x
        lda (rtfltptr),y
        sec
        sbc #$30
        cmp #10
        bcs _ptick_digit_bad
        inc play_pos,x
        rts
_ptick_digit_bad:
        lda #0
        rts

;=======================================================================================
; Sprites and joystick: SPRITE attribute form, MOVSPR absolute position,
; SPRCOLOR, JOY(), BUMP(). Attribute setters write the VIC-II registers
; directly so omitted SPRITE arguments leave state untouched, like the
; interpreter. MOVSPR uses raw VIC coordinates (x MSB via $d010).
;=======================================================================================

sprbit:
        .byte $01, $02, $04, $08, $10, $20, $40, $80

sprsetn:
        lda exprlo
        and #7
        sta spr_n
        rts

sprswitch:
        ldx spr_n
        lda exprlo
        beq _sprswitch_off
        lda sprbit,x
        ora $d015
        sta $d015
        rts
_sprswitch_off:
        lda sprbit,x
        eor #$ff
        and $d015
        sta $d015
        rts

sprsetfg:
        ldx spr_n
        lda exprlo
        sta $d027,x
        rts

; prio 1 = sprite in front of screen data = $d01b bit CLEAR
sprsetprio:
        ldx spr_n
        lda exprlo
        beq _sprprio_behind
        lda sprbit,x
        eor #$ff
        and $d01b
        sta $d01b
        rts
_sprprio_behind:
        lda sprbit,x
        ora $d01b
        sta $d01b
        rts

sprsetexpx:
        lda #<$d01d
        sta rtptr
        bra sprbitreg
sprsetexpy:
        lda #<$d017
        sta rtptr
        bra sprbitreg
sprsetmode:
        lda #<$d01c
        sta rtptr

; set or clear this sprite's bit in the VIC register at $d0xx (low byte
; staged in rtptr) according to exprlo being nonzero or zero
sprbitreg:
        lda #>$d000
        sta rtptr+1
        ldx spr_n
        ldz #0
        lda exprlo
        beq _sprbitreg_clear
        lda sprbit,x
        ora (rtptr),z
        sta (rtptr),z
        rts
_sprbitreg_clear:
        lda sprbit,x
        eor #$ff
        and (rtptr),z
        sta (rtptr),z
        rts

sprsetx:
        lda exprlo
        sta spr_x
        lda exprhi
        sta spr_x+1
        rts

; MOVSPR n,x,y: y arrives in exprlo, x was staged by sprsetx
movsprgo:
        ldx spr_n
        lda #0
        sta mo_mode,x
        lda spr_n
        asl a
        tay
        lda spr_x
        sta $d000,y
        lda exprlo
        sta $d001,y
        ldx spr_n
        lda spr_x+1
        beq _movspr_msboff
        lda sprbit,x
        ora $d010
        sta $d010
        rts
_movspr_msboff:
        lda sprbit,x
        eor #$ff
        and $d010
        sta $d010
        rts

sprmc1:
        lda exprlo
        sta $d025
        rts

sprmc2:
        lda exprlo
        sta $d026
        rts

; JOY(port): 0 centre, 1-8 clockwise from up, bit 7 = fire
joyf:
        lda exprlo
        cmp #1
        bne _joy_port2
        lda $dc01
        bra _joy_decode
_joy_port2:
        lda $dc00
_joy_decode:
        eor #$ff
        tay
        and #$0f
        tax
        lda joytab,x
        sta exprlo
        tya
        and #$10
        beq _joy_nofire
        lda exprlo
        ora #$80
        sta exprlo
_joy_nofire:
        lda #0
        sta exprhi
        rts

; index bits: 0=up 1=down 2=left 3=right (already inverted to active-high)
joytab:
        .byte 0, 1, 5, 0, 7, 8, 6, 0, 3, 2, 4, 0, 0, 0, 0, 0

; BUMP(type): 1 sprite-sprite ($d01e), else sprite-data ($d01f);
; the VIC latches collisions and clears the register on read
bumpf:
        lda exprlo
        cmp #1
        bne _bump_data
        lda col_armed
        and #1
        beq _bump_hw1
        lda col_acc1            ; the tick owns the register: hand over
        ldx #0                  ; the accumulated mask and clear it
        stx col_acc1
        bra _bump_done
_bump_hw1:
        lda $d01e
        bra _bump_done
_bump_data:
        lda col_armed
        and #2
        beq _bump_hw2
        lda col_acc2
        ldx #0
        stx col_acc2
        bra _bump_done
_bump_hw2:
        lda $d01f
_bump_done:
        sta exprlo
        lda #0
        sta exprhi
        rts

;=======================================================================================
; Sound: VOL and SOUND voice,freq,dur[,dir,min,sweep,wave,pulse] per the
; BASIC65 spec: voices 1-3 on SID2 ($d420), 4-6 on SID4 ($d460); default
; waveform is square with 50% duty. Durations and sweeps tick once per
; jiffy in a routine chained into the KERNAL raster IRQ on first use and
; unhooked at exit. The hook goes through the KERNAL VECTOR accessor
; ($ff8d) per dansanderson.com/mega65/kernal-of-truth: read the RAM
; vector table, patch the IRQ entry (first word), write it back --
; never poke $0314 directly, the MEGA65 table location is internal.
; The handler touches only snd_* state and SID registers.
;=======================================================================================

sndinit:
        lda snd_hooked
        bne _sndinit_done
        lda #<sndshutdown
        sta snd_shutptr
        lda #>sndshutdown
        sta snd_shutptr+1
        sei
        sec                     ; read the KERNAL RAM vector table
        ldx #<snd_vectab
        ldy #>snd_vectab
        jsr kernalvector
        lda snd_vectab          ; first entry is the IRQ vector
        sta snd_oldirq
        lda snd_vectab+1
        sta snd_oldirq+1
        lda #<rtsound_isr
        sta snd_vectab
        lda #>rtsound_isr
        sta snd_vectab+1
        clc                     ; write the patched table back
        ldx #<snd_vectab
        ldy #>snd_vectab
        jsr kernalvector
        lda #1
        sta snd_hooked
        cli
_sndinit_done:
        rts

; runs in the middle of the KERNAL raster IRQ, once per jiffy
rtsound_isr:
        pha
        phx
        phy
        jsr play_tick
        jsr mouse_tick
        jsr col_tick
        jsr spr_tick
        ldx #5
_snd_isr_loop:
        lda snd_dur_lo,x
        ora snd_dur_hi,x
        beq _snd_isr_next
        lda snd_dur_lo,x
        bne +
        dec snd_dur_hi,x
+       dec snd_dur_lo,x
        lda snd_dur_lo,x
        ora snd_dur_hi,x
        bne _snd_isr_sweep
        lda snd_ctrl,x          ; expired: drop the gate bit
        and #$fe
        ldy snd_regoff,x
        sta $d404,y
        bra _snd_isr_next
_snd_isr_sweep:
        lda snd_pswp_lo,x       ; sweep armed for this voice?
        ora snd_pswp_hi,x
        beq _snd_isr_next
        jsr sndsweepstep
        ldy snd_regoff,x
        lda snd_frq_lo,x
        sta $d400,y
        lda snd_frq_hi,x
        sta $d401,y
_snd_isr_next:
        dex
        bpl _snd_isr_loop
        ply
        plx
        pla
        jmp (snd_oldirq)

; advance the sweep of voice X by one jiffy: dir 0 climbs from freq,
; 1 falls toward min, 2 bounces between min and the starting freq
sndsweepstep:
        lda snd_pdir,x
        cmp #1
        beq _swpstep_down
        cmp #2
        bne _swpstep_up
        lda snd_phase,x         ; oscillate: phase 0 falls, 1 climbs
        beq _swpstep_oscdown
        clc
        lda snd_frq_lo,x
        adc snd_pswp_lo,x
        sta snd_frq_lo,x
        lda snd_frq_hi,x
        adc snd_pswp_hi,x
        sta snd_frq_hi,x
        bcs _swpstep_turndown
        lda snd_frq_lo,x        ; reached the starting freq again?
        cmp snd_pmax_lo,x
        lda snd_frq_hi,x
        sbc snd_pmax_hi,x
        bcc _swpstep_done
_swpstep_turndown:
        lda snd_pmax_lo,x
        sta snd_frq_lo,x
        lda snd_pmax_hi,x
        sta snd_frq_hi,x
        lda #0
        sta snd_phase,x
        rts
_swpstep_oscdown:
        jsr _swpstep_down
        lda snd_frq_lo,x        ; bottomed out at min?
        cmp snd_pmin_lo,x
        bne _swpstep_done
        lda snd_frq_hi,x
        cmp snd_pmin_hi,x
        bne _swpstep_done
        lda #1
        sta snd_phase,x
_swpstep_done:
        rts

_swpstep_up:
        clc
        lda snd_frq_lo,x
        adc snd_pswp_lo,x
        sta snd_frq_lo,x
        lda snd_frq_hi,x
        adc snd_pswp_hi,x
        sta snd_frq_hi,x
        bcc _swpstep_done
        lda #$ff                ; clamp at the top of the range
        sta snd_frq_lo,x
        sta snd_frq_hi,x
        rts

_swpstep_down:
        sec
        lda snd_frq_lo,x
        sbc snd_pswp_lo,x
        sta snd_frq_lo,x
        lda snd_frq_hi,x
        sbc snd_pswp_hi,x
        sta snd_frq_hi,x
        bcc _swpstep_floor
        lda snd_frq_lo,x        ; fell below min?
        cmp snd_pmin_lo,x
        lda snd_frq_hi,x
        sbc snd_pmin_hi,x
        bcs _swpstep_done2
_swpstep_floor:
        lda snd_pmin_lo,x
        sta snd_frq_lo,x
        lda snd_pmin_hi,x
        sta snd_frq_hi,x
_swpstep_done2:
        rts

; called from rtexit: unhook the IRQ routine and gate off every SOUND
; voice (volume is left alone so interpreter sound keeps working)
sndshutdown:
        lda #0
        sta mou_on
        sta col_armed
        ldx #7
_sndshut_mo:
        sta mo_mode,x
        dex
        bpl _sndshut_mo
        lda #0
        sta col_pending
        sta col_active
        jsr playoff
        lda snd_hooked
        beq _sndshut_gates_only
        sei
        lda snd_oldirq
        sta snd_vectab
        lda snd_oldirq+1
        sta snd_vectab+1
        clc
        ldx #<snd_vectab
        ldy #>snd_vectab
        jsr kernalvector
        lda #0
        sta snd_hooked
        cli
_sndshut_gates_only:
        ldx #5
_sndshut_gates:
        ldy snd_regoff,x
        lda #0
        sta $d404,y
        sta snd_dur_lo,x
        sta snd_dur_hi,x
        dex
        bpl _sndshut_gates
        rts

; POT(1-4): select the paddle pair on CIA1 port A, read SID pots;
; value > 255 means the fire button is down too
potf:
        ldx exprlo
        dex
        cpx #4
        bcc +
        ldx #0
+       txa
        and #2
        beq _potf_p1
        lda #$80                ; paddles on control port 2
        bra _potf_sel
_potf_p1:
        lda #$40                ; control port 1
_potf_sel:
        sta $dc00
        ldy #0
_potf_settle:
        dey
        bne _potf_settle
        txa
        and #1
        bne _potf_y
        lda $d419
        bra _potf_val
_potf_y:
        lda $d41a
_potf_val:
        sta exprlo
        lda #0
        sta exprhi
        txa
        and #2
        beq _potf_fb1
        lda $dc00
        bra _potf_fire
_potf_fb1:
        lda $dc01
_potf_fire:
        and #$0c                ; paddle fire lines
        cmp #$0c
        beq _potf_nofire
        lda #1
        sta exprhi              ; value + 256
_potf_nofire:
        lda #$ff                ; restore keyboard scanning
        sta $dc00
        rts

lpenf:
        lda exprlo
        bne _lpenf_y
        lda $d013
        asl a
        sta exprlo
        lda #0
        rol a
        sta exprhi
        rts
_lpenf_y:
        lda $d014
        sta exprlo
        lda #0
        sta exprhi
        rts

rspset:
        lda exprlo
        and #7
        sta spr_n
        rts

; RSPPOS(sprite, n): 0 x (with MSB), 1 y, 2 speed (no engine: 0)
rspposf:
        ldx spr_n
        lda exprlo
        cmp #1
        beq _rsppos_y
        bcs _rsppos_spd
        txa
        asl a
        tay
        lda $d000,y
        sta exprlo
        lda $d010
        and sprbit,x
        beq +
        lda #1
+       sta exprhi
        rts
_rsppos_y:
        txa
        asl a
        tay
        lda $d001,y
        sta exprlo
        lda #0
        sta exprhi
        rts
_rsppos_spd:
        ldx spr_n
        lda mo_speed,x
        sta exprlo
        lda #0
        sta exprhi
        rts

; RSPRITE(sprite, n): 0 on, 1 colour, 2 priority, 3 expx, 4 expy, 5 mc
rspritef:
        ldx spr_n
        lda exprlo
        bne +
        lda $d015
        bra _rsprite_bit
+       cmp #1
        bne +
        lda $d027,x
        and #$0f
        bra _rsprite_val
+       cmp #2
        bne +
        lda $d01b
        and sprbit,x
        beq _rsprite_front
        lda #0
        bra _rsprite_val
_rsprite_front:
        lda #1
        bra _rsprite_val
+       cmp #3
        bne +
        lda $d01d
        bra _rsprite_bit
+       cmp #4
        bne +
        lda $d017
        bra _rsprite_bit
+       lda $d01c
_rsprite_bit:
        and sprbit,x
        beq _rsprite_val
        lda #1
_rsprite_val:
        sta exprlo
        lda #0
        sta exprhi
        rts

rspcolorf:
        lda exprlo
        cmp #2
        beq _rspcolor_2
        lda $d025
        bra +
_rspcolor_2:
        lda $d026
+       and #$0f
        sta exprlo
        lda #0
        sta exprhi
        rts

; MOVSPR motion engine: per-sprite 8.8 fixed-point velocities applied
; each frame in the IRQ tick. angle#speed converts through SIN/COS at
; statement time (0 degrees = up, clockwise, speed in pixels/frame);
; TO-interpolation computes a per-frame vector and a frame count, then
; snaps to the target and stops. Absolute/relative placement cancels
; any running motion for that sprite.
cdeg2rad:
        .byte $7b, $0e, $fa, $35, $13
c256f:
        .byte $89, $00, $00, $00, $00

; A = value in FAC -> signed 8.8 in exprlo/exprhi (value * 256, qint)
sprfix88:
        lda #<c256f
        ldy #>c256f
        jsr fldca
        jsr fmul
        jmp qint

; angle#speed: angle staged by sprsetx (integer degrees), speed in
; exprlo; compute vx = s*sin(a), vy = -s*cos(a)
sprgoang:
        jsr sndinit             ; motion runs on the IRQ tick
        lda exprlo
        sta spr_spd
        ldx spr_n
        sta mo_speed,x
        lda spr_x               ; angle -> radians in FAC
        sta exprlo
        lda spr_x+1
        sta exprhi
        jsr float16
        lda #<cdeg2rad
        ldy #>cdeg2rad
        jsr fldca
        jsr fmul
        ldx #14
        jsr fsavb               ; radians in buffer 2
        jsr sinf
        jsr _sprspeedmul        ; FAC = sin(a) * speed
        jsr sprfix88
        ldx spr_n
        lda exprlo
        sta mo_vxl,x
        lda exprhi
        sta mo_vxh,x
        ldx #14
        jsr frstb
        jsr cosf
        jsr _sprspeedmul
        lda facsgn              ; vy = -speed*cos(a)
        eor #$ff
        sta facsgn
        jsr sprfix88
        ldx spr_n
        lda exprlo
        sta mo_vyl,x
        lda exprhi
        sta mo_vyh,x
        jsr sprsyncpos
        lda #1                  ; endless velocity mode
        sta mo_mode,x
        rts

_sprspeedmul:
        jsr fpush
        lda spr_spd
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jsr fpoparg
        jmp fmul

; TO-interpolation: target staged in spr_tx/spr_ty, speed in exprlo;
; frames = max(|dx|,|dy|) / speed (at least 1), v = delta/frames
sprgoto:
        lda exprlo
        bne +
        lda #1                  ; speed 0 would never arrive
        sta exprlo
+       jsr sndinit             ; motion runs on the IRQ tick
        lda exprlo
        sta spr_spd
        ldx spr_n
        sta mo_speed,x
        jsr sprsyncpos
        ; dx = tx - x (16-bit signed), dy = ty - y
        ldx spr_n
        sec
        lda spr_tx
        sbc mo_xw,x
        sta spr_dx
        lda spr_tx+1
        sbc mo_xwh,x
        sta spr_dx+1
        sec
        lda spr_ty
        sbc mo_yw,x
        sta spr_dy
        lda spr_dy+1
        lda #0
        sbc #0
        sta spr_dy+1
        lda spr_ty+1
        beq +
+       ; frames = sqrt(dx*dx + dy*dy) / speed -- the ROM's speed is
        ; pixels per frame along the path (user-measured: 233px at
        ; speed 4 took 1.18s interpreted)
        lda spr_dx
        sta exprlo
        lda spr_dx+1
        sta exprhi
        jsr float16
        jsr fmovaf
        jsr fmul                ; dx*dx
        ldx #7
        jsr fsavb
        lda spr_dy
        sta exprlo
        lda spr_dy+1
        sta exprhi
        jsr float16
        jsr fmovaf
        jsr fmul                ; dy*dy
        ldx #7
        jsr fargb
        jsr fadd
        jsr sqrf                ; path length
        jsr fpush
        lda spr_spd
        sta exprlo
        lda #0
        sta exprhi
        jsr float16
        jsr fpoparg
        jsr fdiv                ; frames = dist / speed
        jsr qint
        inc exprlo              ; ceil-ish, and never zero
        bne +
        inc exprhi
+       ldx spr_n
        lda exprlo
        sta mo_cntl,x
        lda exprhi
        sta mo_cnth,x
        sta spr_fr+1
        lda exprlo
        sta spr_fr
        ; vx = dx*256/frames, vy = dy*256/frames (signed 8.8)
        lda spr_dx
        sta exprlo
        lda spr_dx+1
        sta exprhi
        jsr float16
        jsr _spr_divfr
        ldx spr_n
        lda exprlo
        sta mo_vxl,x
        lda exprhi
        sta mo_vxh,x
        lda spr_dy
        sta exprlo
        lda spr_dy+1
        sta exprhi
        jsr float16
        jsr _spr_divfr
        ldx spr_n
        lda exprlo
        sta mo_vyl,x
        lda exprhi
        sta mo_vyh,x
        lda spr_tx
        sta mo_txl,x
        lda spr_tx+1
        sta mo_txh,x
        lda spr_ty
        sta mo_ty,x
        lda #2                  ; counted interpolation mode
        sta mo_mode,x
        rts

; FAC = FAC * 256 / frames -> signed 8.8 int
_spr_divfr:
        lda #<c256f
        ldy #>c256f
        jsr fldca
        jsr fmul
        jsr fpush
        lda spr_fr
        sta exprlo
        lda spr_fr+1
        sta exprhi
        jsr float16
        jsr fpoparg
        jsr fdiv
        jmp qint

; copy the sprite's current VIC position into the motion state
sprsyncpos:
        ldx spr_n
        txa
        asl a
        tay
        lda $d000,y
        sta mo_xw,x
        lda #0
        sta mo_xwh,x
        lda $d010
        and sprbit,x
        beq +
        lda #1
        sta mo_xwh,x
+       lda $d001,y
        sta mo_yw,x
        lda #0
        sta mo_xf,x
        sta mo_yf,x
        rts

; TO/velocity targets staged before sprgoto
sprsettx:
        lda exprlo
        sta spr_tx
        lda exprhi
        sta spr_tx+1
        rts

sprsetty:
        lda exprlo
        sta spr_ty
        lda exprhi
        sta spr_ty+1
        rts

; relative placement: add the current position to the staged value
sprsetxr:
        jsr sprsyncpos
        ldx spr_n
        clc
        lda exprlo
        adc mo_xw,x
        sta spr_x
        lda exprhi
        adc mo_xwh,x
        sta spr_x+1
        rts

sprsetyr:
        ldx spr_n
        clc
        lda exprlo
        adc mo_yw,x
        sta exprlo
        rts

; the per-frame tick: advance moving sprites, write the VIC registers
spr_tick:
        ldx #7
_sprt_loop:
        lda mo_mode,x
        beq _sprt_next
        clc                     ; x += vx (16.8)
        lda mo_xf,x
        adc mo_vxl,x
        sta mo_xf,x
        lda mo_xw,x
        adc mo_vxh,x
        sta mo_xw,x
        lda mo_vxh,x
        bmi _sprt_xneg
        lda mo_xwh,x
        adc #0
        bra _sprt_xstore
_sprt_xneg:
        lda mo_xwh,x
        adc #$ff
_sprt_xstore:
        and #1                  ; wrap into the 9-bit VIC range
        sta mo_xwh,x
        clc                     ; y += vy (8.8, wraps as a byte)
        lda mo_yf,x
        adc mo_vyl,x
        sta mo_yf,x
        lda mo_yw,x
        adc mo_vyh,x
        sta mo_yw,x
        ; write the VIC position
        txa
        asl a
        tay
        lda mo_xw,x
        sta $d000,y
        lda mo_yw,x
        sta $d001,y
        lda mo_xwh,x
        beq _sprt_msboff
        lda sprbit,x
        ora $d010
        sta $d010
        bra _sprt_count
_sprt_msboff:
        lda sprbit,x
        eor #$ff
        and $d010
        sta $d010
_sprt_count:
        lda mo_mode,x
        cmp #2
        bne _sprt_next
        lda mo_cntl,x           ; counted mode: arrive and snap
        bne +
        dec mo_cnth,x
+       dec mo_cntl,x
        lda mo_cntl,x
        ora mo_cnth,x
        bne _sprt_next
        lda mo_txl,x            ; snap to the exact target
        sta mo_xw,x
        lda mo_txh,x
        and #1
        sta mo_xwh,x
        lda mo_ty,x
        sta mo_yw,x
        txa
        asl a
        tay
        lda mo_xw,x
        sta $d000,y
        lda mo_yw,x
        sta $d001,y
        lda mo_xwh,x
        beq _sprt_smsboff
        lda sprbit,x
        ora $d010
        sta $d010
        bra _sprt_stop
_sprt_smsboff:
        lda sprbit,x
        eor #$ff
        and $d010
        sta $d010
_sprt_stop:
        lda #0
        sta mo_mode,x
_sprt_next:
        dex
        bpl _sprt_loop
        rts

; COLLISION type[,line]: the IRQ tick latches VIC collision bits into
; pending flags; colcheck (emitted at each line start when the program
; uses COLLISION) dispatches a compiled GOSUB to the armed handler.
; Only one handler runs at a time, per the book.
colsett:
        ldx exprlo
        dex
        cpx #3
        bcc +
        ldx #0
+       stx col_t
        rts

; arm type col_t with the handler address staged in coltmp
colarm:
        lda $d01e               ; reading re-arms the VIC latches and
        lda $d01f               ; discards collisions from before arming
        lda #0
        sta col_acc1
        sta col_acc2
        ldx col_t
        lda coltmp
        sta col_vlo,x
        lda coltmp+1
        sta col_vhi,x
        jsr sndinit             ; needs the IRQ tick (clobbers X!)
        ldx col_t
        lda colbit,x
        ora col_armed
        sta col_armed
        rts

coloff:
        ldx col_t
        lda colbit,x
        eor #$ff
        and col_armed
        sta col_armed
        rts

colbit:
        .byte 1, 2, 4

; from the IRQ tick: poll the collision registers directly -- the VIC
; only re-arms them on read, so the $d019 flags go stale if a previous
; program left the latch set. Reads accumulate for BUMP.
col_tick:
        lda #0
        sta col_new
        lda $d01e               ; sprite-sprite (read re-arms)
        beq +
        ora col_acc1
        sta col_acc1
        lda #1                  ; type 1 pending
        sta col_new
+       lda $d01f               ; sprite-data
        beq +
        ora col_acc2
        sta col_acc2
        lda col_new
        ora #2
        sta col_new
+       lda $d019
        and #%00001000          ; light pen flag
        beq +
        sta $d019
        lda col_new
        ora #4
        sta col_new
+       lda col_new
        and col_armed
        ora col_pending
        sta col_pending
        rts

; between lines: run at most one pending handler as a GOSUB
colcheck:
        lda col_active
        bne _colcheck_done
        lda col_pending
        beq _colcheck_done
        ldx #0
_colcheck_scan:
        lda colbit,x
        and col_pending
        bne _colcheck_fire
        inx
        cpx #3
        bne _colcheck_scan
_colcheck_done:
        rts
_colcheck_fire:
        lda colbit,x
        eor #$ff
        and col_pending
        sta col_pending
        lda #1
        sta col_active
        lda col_vlo,x
        sta col_jmp
        lda col_vhi,x
        sta col_jmp+1
        jsr _colcheck_call
        lda #0
        sta col_active
        rts
_colcheck_call:
        jmp (col_jmp)

; MOUSE driver: 1351 proportional deltas decoded per frame in the IRQ
; tick; the pointer sprite follows. Left button = fire line (bit 7 of
; RMOUSE's status), right button = up line (bit 0), per the 1351 wiring.
mousetp:
        lda exprlo
        cmp #1
        bne _mousetp_p2
        lda #$40
        bra _mousetp_sel
_mousetp_p2:
        lda #$80                ; port 2 default; port 3 reads port 2 too
_mousetp_sel:
        sta mou_psel
        lda exprlo
        sta mou_port
        rts

mousets:
        lda exprlo
        and #7
        sta mou_spr
        rts

mousetx:
        lda exprlo
        sta mou_x
        lda exprhi
        sta mou_x+1
        rts

mousety:
        lda exprlo
        sta mou_y
        rts

; built-in arrow, installed into the C65 sprite area so MOUSE ON
; shows a pointer with no setup, like the ROM's default
mouarrow:
        .byte $80, $00, $00, $c0, $00, $00, $e0, $00, $00
        .byte $f0, $00, $00, $f8, $00, $00, $fc, $00, $00
        .byte $fe, $00, $00, $f8, $00, $00, $d8, $00, $00
        .byte $8c, $00, $00, $0c, $00, $00, $06, $00, $00
        .byte $06, $00, $00, $00, $00, $00, $00, $00, $00
        .byte $00, $00, $00, $00, $00, $00, $00, $00, $00
        .byte $00, $00, $00, $00, $00, $00, $00, $00, $00

mouseon:
        jsr sndinit             ; shares the IRQ hook
        ldy #62
_mou_shape:
        lda mouarrow,y
        sta $0600,y             ; sprite slot 24
        dey
        bpl _mou_shape
        ldx mou_spr
        lda #24
        sta $07f8,x             ; both candidate pointer homes
        sta $0ff8,x
        ldx mou_spr
        lda sprbit,x
        ora $d015               ; the pointer sprite turns on
        sta $d015
        lda $d419               ; prime the delta history
        sta mou_old
        lda $d41a
        sta mou_old+1
        lda #1
        sta mou_on
        rts

mouseoff:
        lda #0
        sta mou_on
        ldx mou_spr
        lda sprbit,x
        eor #$ff
        and $d015
        sta $d015
        rts

; per-frame tick, called from the sound ISR (registers already saved)
mouse_tick:
        lda mou_on
        bne +
        rts
+       lda mou_psel
        sta $dc00
        ldy #16
_mou_settle:
        dey
        bne _mou_settle
        lda $d419               ; X axis
        tay
        sec
        sbc mou_old
        sty mou_old
        jsr _mou_sign
        clc
        adc mou_x
        sta mou_x
        lda mou_d
        bpl _mou_xpos
        lda mou_x+1
        adc #$ff
        bra _mou_xstore
_mou_xpos:
        lda mou_x+1
        adc #0
_mou_xstore:
        sta mou_x+1
        bpl _mou_xclamphi       ; negative: clamp to 0
        lda #0
        sta mou_x
        sta mou_x+1
_mou_xclamphi:
        lda mou_x+1
        beq _mou_ydelta
        lda mou_x
        cmp #<319
        lda mou_x+1
        sbc #>319
        bcc _mou_ydelta
        lda #<319
        sta mou_x
        lda #>319
        sta mou_x+1
_mou_ydelta:
        lda $d41a               ; Y axis: pot up = mouse up = smaller y
        tay
        sec
        sbc mou_old+1
        sty mou_old+1
        jsr _mou_sign           ; signed delta in mou_d
        ldx #0                  ; sign-extend for a 16-bit subtract:
        lda mou_d               ; a plain borrow check clamps every
        bpl +                   ; downward (negative-delta) move to 0
        ldx #$ff
+       stx mou_dh
        lda mou_y
        sec
        sbc mou_d
        tay
        lda #0
        sbc mou_dh
        beq _mou_yrange
        bmi _mou_yzero
        ldy #199                ; went past the bottom
        bra _mou_ystore
_mou_yzero:
        ldy #0                  ; went past the top
        bra _mou_ystore
_mou_yrange:
        cpy #200
        bcc _mou_ystore
        ldy #199
_mou_ystore:
        sty mou_y
        lda #$ff
        sta $dc00               ; restore keyboard scanning
        ; move the pointer sprite: visible origin offsets 24,50
        ldx mou_spr
        txa
        asl a
        tay
        lda mou_x
        clc
        adc #24
        sta $d000,y
        lda mou_x+1
        adc #0
        beq _mou_msboff
        lda sprbit,x
        ora $d010
        sta $d010
        bra _mou_sy
_mou_msboff:
        lda sprbit,x
        eor #$ff
        and $d010
        sta $d010
_mou_sy:
        lda mou_y
        clc
        adc #50
        sta $d001,y
        rts

; 1351 delta decode: A = raw difference -> signed delta, also in mou_d
_mou_sign:
        clc
        adc #64
        and #127
        sec
        sbc #64
        sta mou_d
        rts

; RMOUSE snapshot: -1 everywhere when the driver is off
rmousef:
        lda mou_on
        bne _rmousef_live
        lda #$ff
        sta mourx
        sta mourx+1
        sta moury
        sta moury+1
        sta mourb
        sta mourb+1
        rts
_rmousef_live:
        sei
        lda mou_x
        sta mourx
        lda mou_x+1
        sta mourx+1
        lda mou_y
        sta moury
        cli
        lda #0
        sta moury+1
        sta mourb+1
        sta mourb
        lda mou_port
        cmp #1
        beq _rmousef_b1
        lda $dc00
        bra _rmousef_btn
_rmousef_b1:
        lda $dc01
_rmousef_btn:
        tay
        and #$10                ; fire line = left button
        bne +
        lda #128
        sta mourb
+       tya
        and #$01                ; up line = right button
        bne +
        lda mourb
        ora #1
        sta mourb
+       rts

; voice register offsets from $d400: SID2 voices 1-3, SID4 voices 4-6
snd_regoff:
        .byte $20, $27, $2e, $60, $67, $6e

; waveform control values, gate on: triangle, sawtooth, square, noise
snd_wftab:
        .byte $11, $21, $41, $81

; FILTER sid[,freq,lp,bp,hp,res]: sid 1 = $d400, 2 = $d440 (PLAY's
; SIDs). Mode/volume and resonance/routing share registers, so shadows
; hold the filter half; volsnd and the X directive recombine them.
fltoff:
        .byte $00, $40

fltsetn:
        ldx exprlo
        dex
        cpx #2
        bcc +
        ldx #0
+       stx flt_n
        rts

fltsetf:
        ldx flt_n
        ldy fltoff,x
        lda exprlo
        and #7
        sta $d415,y
        lda exprhi              ; FC_hi = value >> 3: high byte << 5,
        and #$07                ; not << 4 -- every cutoff >= 256 was
        asl a                   ; mis-scaled (the timbre discrepancy)
        asl a
        asl a
        asl a
        asl a
        sta flt_tmp
        lda exprlo
        lsr a
        lsr a
        lsr a
        ora flt_tmp
        sta $d416,y
        rts

fltsetlp:
        lda #$10
        bra fltmodebit
fltsetbp:
        lda #$20
        bra fltmodebit
fltsethp:
        lda #$40

; set or clear the mode bit in A per exprlo, then rewrite mode|volume
fltmodebit:
        ldx flt_n
        sta flt_tmp
        lda exprlo
        beq _fltmode_clear
        lda flt_mode,x
        ora flt_tmp
        bra _fltmode_wr
_fltmode_clear:
        lda flt_tmp
        eor #$ff
        and flt_mode,x
_fltmode_wr:
        sta flt_mode,x
        ora snd_vol
        ldy fltoff,x
        sta $d418,y
        rts

fltsetres:
        ldx flt_n
        lda exprlo
        asl a
        asl a
        asl a
        asl a
        sei
        sta flt_res,x
        ora flt_rout,x
        ldy fltoff,x
        sta $d417,y
        cli
        rts

; VOL affects all voices (SOUND and PLAY), so write all four SIDs
volsnd:
        lda exprlo
        and #$0f
        sta snd_vol
volsndall:
        sta $d438
        sta $d478
        ora flt_mode
        sta $d418
        lda snd_vol
        ora flt_mode+1
        sta $d458
        rts

sndsetv:
        lda exprlo
        sec
        sbc #1                  ; voices are 1-6
        cmp #6
        bcc +
        lda #0
+       sta snd_v
        rts

sndsetf:
        lda exprlo
        sta snd_f
        lda exprhi
        sta snd_f+1
        rts

sndsetd:
        lda exprlo
        sta snd_d
        lda exprhi
        sta snd_d+1
        rts

sndsetdr:
        lda exprlo
        cmp #3
        bcc +
        lda #0
+       sta snd_dir
        rts

sndsetm:
        lda exprlo
        sta snd_m
        lda exprhi
        sta snd_m+1
        rts

sndsets:
        lda exprlo
        sta snd_s
        lda exprhi
        sta snd_s+1
        rts

sndsetw:
        lda exprlo
        and #3
        sta snd_w
        rts

sndsetp:
        lda exprlo
        sta snd_p
        lda exprhi
        sta snd_p+1
        rts

sndgo:
        jsr sndinit
        lda snd_vol
        jsr volsndall
        ldx snd_v
        ldy snd_regoff,x
        sei
        lda #0                  ; gate off, reset envelope
        sta $d404,y
        lda snd_f
        sta snd_frq_lo,x
        sta snd_pmax_lo,x
        sta $d400,y
        lda snd_f+1
        sta snd_frq_hi,x
        sta snd_pmax_hi,x
        sta $d401,y
        lda snd_p
        sta $d402,y
        lda snd_p+1
        and #$0f
        sta $d403,y
        lda #$0a                ; default envelope: fast attack, some decay
        sta $d405,y
        lda #$f8                ; full sustain, medium release
        sta $d406,y
        lda snd_m
        sta snd_pmin_lo,x
        lda snd_m+1
        sta snd_pmin_hi,x
        lda snd_s
        sta snd_pswp_lo,x
        lda snd_s+1
        sta snd_pswp_hi,x
        lda snd_dir
        sta snd_pdir,x
        lda #0
        sta snd_phase,x
        ldy snd_w
        lda snd_wftab,y
        sta snd_ctrl,x
        ldy snd_regoff,x
        sta $d404,y
        lda snd_d
        sta snd_dur_lo,x
        lda snd_d+1
        sta snd_dur_hi,x
        cli
        ; reset optional parameters for the next SOUND statement
        lda #2
        sta snd_w               ; square default
        lda #0
        sta snd_p
        sta snd_dir
        sta snd_m
        sta snd_m+1
        sta snd_s
        sta snd_s+1
        lda #$08
        sta snd_p+1             ; 50% pulse default
        rts


snd_hooked:   .byte 0
snd_oldirq:   .byte 0,0
snd_vol:      .byte $0f
snd_v:        .byte 0
snd_f:        .byte 0,0
snd_d:        .byte 0,0
snd_w:        .byte 2   ; square default
snd_p:        .byte 0,$08 ; 50% pulse default
snd_dir:      .byte 0
snd_m:        .byte 0,0
snd_s:        .byte 0,0
snd_ctrl:     .fill 6, 0
snd_dur_lo:   .fill 6, 0
snd_dur_hi:   .fill 6, 0
snd_frq_lo:   .fill 6, 0
snd_frq_hi:   .fill 6, 0
snd_pmax_lo:  .fill 6, 0
snd_pmax_hi:  .fill 6, 0
snd_pmin_lo:  .fill 6, 0
snd_pmin_hi:  .fill 6, 0
snd_pswp_lo:  .fill 6, 0
snd_pswp_hi:  .fill 6, 0
playarg:     .byte 0
play_acc:     .byte 0
play_dot:     .byte 0
play_octw:    .byte 0
play_frq:     .byte 0,0
play_ad:      .byte 0
play_sr:      .byte 0
play_wv:      .byte 0
play_cplen:   .byte 0
flt_n:        .byte 0
flt_tmp:      .byte 0
flt_tmp2:     .byte 0
flt_mode:     .byte 0,0
flt_res:      .byte 0,0
flt_rout:     .byte 0,0
spr_spd:      .byte 0
spr_dx:       .byte 0,0
spr_dy:       .byte 0,0
spr_tx:       .byte 0,0
spr_ty:       .byte 0,0
spr_fr:       .byte 0,0
mo_mode:      .fill 8, 0
mo_xw:        .fill 8, 0
mo_xwh:       .fill 8, 0
mo_xf:        .fill 8, 0
mo_yw:        .fill 8, 0
mo_yf:        .fill 8, 0
mo_vxl:       .fill 8, 0
mo_vxh:       .fill 8, 0
mo_vyl:       .fill 8, 0
mo_vyh:       .fill 8, 0
mo_txl:       .fill 8, 0
mo_txh:       .fill 8, 0
mo_ty:        .fill 8, 0
mo_cntl:      .fill 8, 0
mo_cnth:      .fill 8, 0
mo_speed:     .fill 8, 0
col_t:        .byte 0
coltmp:      .byte 0,0
col_new:      .byte 0
col_acc1:     .byte 0
col_acc2:     .byte 0
col_armed:    .byte 0
col_pending:  .byte 0
col_active:   .byte 0
col_jmp:      .byte 0,0
col_vlo:      .fill 3, 0
col_vhi:      .fill 3, 0
mou_on:       .byte 0
mou_port:     .byte 2
mou_psel:     .byte $80
mou_spr:      .byte 0
mou_x:        .byte 160,0
mou_y:        .byte 100
mou_old:      .byte 0,0
mou_d:        .byte 0
mou_dh:       .byte 0
mourx:       .byte 0,0
moury:       .byte 0,0
mourb:       .byte 0,0
play_xt1:     .byte 0
play_xt2:     .byte 0
play_envn:    .byte 0
play_tdiv:    .byte 0
play_tacc:    .byte 0,0
play_tq:      .byte 0
play_act:     .fill 6, 0
play_pos:     .fill 6, 0
play_rem:     .fill 6, 0
play_dur:     .fill 6, 0
play_oct:     .fill 6, 0
play_env:     .fill 6, 0
play_loop:    .fill 6, 0
play_ctrl:    .fill 6, 0
play_buf:     .fill 6*PLAY_TRACK_LEN, 0
spr_n:        .byte 0
spr_x:        .byte 0,0
.fi

rtendsound:

        .cerror * > progbase, "runtime overflows into program area at progbase"

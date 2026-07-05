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
;   $2012-$4fff   runtime code and storage (guarded by .cerror below)
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

progbase     = $5000
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
        lda progbase+2
        sta rtvheapend
        lda progbase+3
        sta rtvheapend+1
        lda progbase+4
        sta rtdatastart
        lda progbase+5
        sta rtdatastart+1
        lda progbase+6
        sta rtdataend
        lda progbase+7
        sta rtdataend+1
        lda progbase+8
        sta rtstrroots
        lda progbase+9
        sta rtstrroots+1
        lda progbase+10
        sta rtfltinit
        lda progbase+11
        sta rtfltinit+1
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
        jsr fltinit             ; convert float literals (needs the above)
        lda $dc04               ; seed RND from the CIA timer
        sta rndseed
        eor #$b5
        sta rndseed+2
        lda $dc05
        sta rndseed+1
        eor #$2f
        sta rndseed+3
        ; bank the C65 BASIC and editor ROMs out of $8000-$cfff so large
        ; programs can execute there; the KERNAL stays mapped at $e000 for
        ; CHROUT and friends, and the ROM bits are restored before returning
        ; to the BASIC SYS caller
        tsx
        stx rtspsave
        lda $d030
        sta rtd030save
        and #%11000111
        sta $d030
        jsr rtcallprog
        jsr rtsndshut
        lda rtd030save
        sta $d030
        rts
rtcallprog:
        jmp (progbase)

; END/STOP from any GOSUB depth: unwind the stack to the pre-program mark,
; restore the ROM mapping, and return to the BASIC SYS caller
rtexit:
        jsr rtsndshut
        ldx rtspsave
        txs
        lda rtd030save
        sta $d030
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

; TI: the 24-bit jiffy clock as a float
rdti:
        jsr kernalrdtim         ; A = low, X = mid, Y = high
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
        jsr stralloc
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
        jsr stralloc
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
        jsr stralloc
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

strgc:
        lda #<strheaptop
        sta strdstlo
        lda #>strheaptop
        sta strdsthi
        lda rtstrroots
        sta rtptr
        lda rtstrroots+1
        sta rtptr+1
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
        lda gcoldlo
        sta strsrc1lo
        lda gcoldhi
        sta strsrc1hi
        jsr setstrptrsrc1
        ldz #0
        lda [varptr],z
        sta strlen1
        jsr strgcallocdst
        lda strdsthi
        cmp strsrc1hi
        bcc strgccopyfwd
        bne strgccopyback
        lda strdstlo
        cmp strsrc1lo
        bcc strgccopyfwd
        beq strgcupdateroot
strgccopyback:
        lda strlen1
        sta stridx
strgccopybackloop:
        jsr setstrptrsrc1
        ldz stridx
        lda [varptr],z
        pha
        jsr setstrptrdst
        ldz stridx
        pla
        sta [varptr],z
        lda stridx
        beq strgcupdateroot
        dec stridx
        jmp strgccopybackloop
strgccopyfwd:
        lda #0
        sta stridx
strgccopyfwdloop:
        jsr setstrptrsrc1
        ldz stridx
        lda [varptr],z
        pha
        jsr setstrptrdst
        ldz stridx
        pla
        sta [varptr],z
        lda stridx
        cmp strlen1
        beq strgcupdateroot
        inc stridx
        jmp strgccopyfwdloop
strgcupdateroot:
        lda gcslotlo
        sta varptr
        lda gcslothi
        sta varptr+1
        jsr setstrptrbank
        ldz #0
        lda strdstlo
        sta [varptr],z
        ldz #1
        lda strdsthi
        sta [varptr],z
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
        clc
        lda rtptr
        adc #4
        sta rtptr
        lda rtptr+1
        adc #0
        sta rtptr+1
        jmp strgcroot
strgcdone:
        lda strdstlo
        sta strheaplo
        lda strdsthi
        sta strheaphi
        rts
strgcloadroot:
        lda gcslotlo
        sta varptr
        lda gcslothi
        sta varptr+1
        jsr setstrptrbank
        ldz #0
        lda [varptr],z
        sta gcoldlo
        ldz #1
        lda [varptr],z
        sta gcoldhi
        rts
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
rtd030save:   .byte 0
rtspsave:     .byte 0
snd_shutptr:  .word rtshutnop

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


rtsndshut:
        jmp (snd_shutptr)
rtshutnop:
        rts

rtendcore:

.weak
RT_SOUND = 1                    ; OUT.ASM sets 0 when the program uses no sound
.endweak

.if RT_SOUND != 0

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
        lda snd_vol
        sta $d418
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
        sta $d418
        sta $d458
        bra _ptick_scan
+       cmp #$58                ; X, M, P: consume the digit, ignore
        beq _ptick_skiparg
        cmp #$4d
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
        lda $d01e
        bra _bump_done
_bump_data:
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

; voice register offsets from $d400: SID2 voices 1-3, SID4 voices 4-6
snd_regoff:
        .byte $20, $27, $2e, $60, $67, $6e

; waveform control values, gate on: triangle, sawtooth, square, noise
snd_wftab:
        .byte $11, $21, $41, $81

; VOL affects all voices (SOUND and PLAY), so write all four SIDs
volsnd:
        lda exprlo
        and #$0f
        sta snd_vol
volsndall:
        sta $d418
        sta $d438
        sta $d458
        sta $d478
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

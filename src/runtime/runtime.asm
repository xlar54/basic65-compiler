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
;   $2012-$3fff   runtime code and storage (guarded by .cerror below)
;   $4000         program header vectors, then the compiled program:
;                   progbase+0  .word start        (program entry)
;                   progbase+2  .word varheapend   (bank-1 clear limit)
;                   progbase+4  .word datastart    (DATA table start)
;                   progbase+6  .word dataend      (DATA table end)
;                   progbase+8  .word strroots     (string GC root table)
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

varptr = $f7
rtptr  = $fb

progbase     = $4000
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
        jsr varinit
        jsr strinit
        jsr datainit
        jmp (progbase)

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
; Tagged numeric variable runtime
;=======================================================================================

loadnumvar:
        ldz #0
        lda [varptr],z
        beq loadnumint
        lda #0
        sta exprlo
        sta exprhi
        rts
loadnumint:
        ldz #1
        lda [varptr],z
        sta exprlo
        ldz #2
        lda [varptr],z
        sta exprhi
        rts

storenumvar:
        ldz #0
        lda #0
        sta [varptr],z
        ldz #1
        lda exprlo
        sta [varptr],z
        ldz #2
        lda exprhi
        sta [varptr],z
        rts

storefloatref:
        ldz #0
        lda #1
        sta [varptr],z
        ldz #1
        lda rtptr
        sta [varptr],z
        ldz #2
        lda rtptr+1
        sta [varptr],z
        rts

printnumvar:
        ldz #0
        lda [varptr],z
        beq printnumint
        ldz #1
        lda [varptr],z
        sta rtptr
        ldz #2
        lda [varptr],z
        sta rtptr+1
        jmp printfloatref
printnumint:
        jsr loadnumvar
        jmp printuint

printfloatref:
        lda rtptr
        ora rtptr+1
        beq printfloatdone
        ldy #0
        lda (rtptr),y
        cmp #'-'
        beq printfloatbody
        lda #' '
        jsr printch
printfloatbody:
        jsr printstr
        lda #' '
        jsr printch
printfloatdone:
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
        cmp #$0d
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
        beq inputadvance
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
        lda #<odm
        sta rtptr
        lda #>odm
        sta rtptr+1
        jsr printstr
        lda #$0d
        jsr printch
        rts

tm:
        lda #<tmm
        sta rtptr
        lda #>tmm
        sta rtptr+1
        jsr printstr
        lda #$0d
        jsr printch
        rts

odm:
        .byte $4f,$55,$54,$20,$4f,$46,$20,$44,$41,$54,$41,$00
tmm:
        .byte $54,$59,$50,$45,$20,$4d,$49,$53,$4d,$41,$54,$43,$48,$00

;=======================================================================================
; Array runtime
;=======================================================================================

arraybounds:
        lda #$41
        jsr printch
        lda #$52
        jsr printch
        lda #$52
        jsr printch
        lda #$41
        jsr printch
        lda #$59
        jsr printch
        lda #$20
        jsr printch
        lda #$42
        jsr printch
        lda #$4f
        jsr printch
        lda #$55
        jsr printch
        lda #$4e
        jsr printch
        lda #$44
        jsr printch
        lda #$53
        jsr printch
        lda #$0d
        jsr printch
        rts

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
        lda #0
        sta exprlo
        sta exprhi
        lda #$4f
        jsr printch
        lda #$55
        jsr printch
        lda #$54
        jsr printch
        lda #$20
        jsr printch
        lda #$4f
        jsr printch
        lda #$46
        jsr printch
        lda #$20
        jsr printch
        lda #$53
        jsr printch
        lda #$54
        jsr printch
        lda #$52
        jsr printch
        lda #$49
        jsr printch
        lda #$4e
        jsr printch
        lda #$47
        jsr printch
        lda #$0d
        jsr printch
        sec
        rts

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

        .cerror * > progbase, "runtime overflows into program area at progbase"

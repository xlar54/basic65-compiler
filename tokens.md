# BASIC65 Token Support Matrix

Status of every BASIC65 token in the compiler. Byte values verified
empirically against petcat (VICE 3.6.1) detokenization plus the known
MEGA65 ROM reassignments petcat predates (WPOKE, WPEEK, DECBIN,
STRBIN$, CHDIR — see `tools/fix-basic65-petcat-tokens.ps1`).
Compiler-side status extracted from the dispatch tables in
`src/basic65c.asm`.

Last full sweep: 2026-07-06 — 43/43 fixtures compile on the MEGA65
with byte-identical native output (negative fixture rejected, 3
interactive fixtures skipped). Statuses below reflect that build.
Open runtime defects that cut across tokens (notably string-heap
corruption under heavy GC churn in large programs) are tracked in
[KNOWN-ISSUES.md](KNOWN-ISSUES.md), not per-row here.

Legend:
- ✅ compiled — full runtime support, interpreter parity
- ⚠️ partial — compiles with documented caveats
- 🔧 syntax — consumed inside a host statement, not standalone
- ❌ unsupported — fatal "unsupported statement/token" compile error
- ✖ n/a — direct-mode/editor command, meaningless in a compiled program
  (still a compile error today; listed separately for honesty about
  what could never be supported vs. what is simply not done yet)

## Totals

| Group | Total tokens | ✅/⚠️ supported | 🔧 syntax | ❌/✖ unsupported |
|---|---|---|---|---|
| Single-byte $80–$FF | 125 (+3 prefix bytes) | 82 | 7 | 36 |
| $CE-prefixed functions | 18 | 16 | — | 2 |
| $FE-prefixed statements | 72 | 47 | 2 (OFF, BIT) | 23 |
| $E0-prefixed (CHAR family) | 1 (CHARDEF) | 1 | — | bare CHAR ❌ |
| Reserved-variable keywords | 9 | 9 | — | — |

## Single-byte tokens ($80–$FF)

| Hex | Token | Status | Notes |
|---|---|---|---|
| $80 | END | ✅ | |
| $81 | FOR | ✅ | |
| $82 | NEXT | ✅ | |
| $83 | DATA | ✅ | |
| $84 | INPUT# | ✅ | |
| $85 | INPUT | ✅ | |
| $86 | DIM | ✅ | |
| $87 | READ | ✅ | |
| $88 | LET | ✅ | |
| $89 | GOTO | ✅ | |
| $8A | RUN | ✖ | direct-mode |
| $8B | IF | ✅ | |
| $8C | RESTORE | ✅ | |
| $8D | GOSUB | ✅ | |
| $8E | RETURN | ✅ | |
| $8F | REM | ✅ | |
| $90 | STOP | ✅ | compiles as END |
| $91 | ON | ✅ | ON GOTO / ON GOSUB; also MOUSE ON argument |
| $92 | WAIT | ✅ | |
| $93 | LOAD | ❌ | |
| $94 | SAVE | ❌ | |
| $95 | VERIFY | ❌ | |
| $96 | DEF | ✅ | DEF FN name(param)=expr, float params, body compiled in place as a subroutine; byte also tails CHARDEF ($E0 $96) |
| $97 | POKE | ✅ | |
| $98 | PRINT# | ✅ | |
| $99 | PRINT | ✅ | PRINT USING not supported ($FB) |
| $9A | CONT | ✖ | direct-mode |
| $9B | LIST | ✖ | direct-mode |
| $9C | CLR | ✅ | plus CLR TI (timer reset) and CLRBIT ($9C $FE $4E) forms |
| $9D | CMD | ❌ | |
| $9E | SYS | ✅ | |
| $9F | OPEN | ✅ | |
| $A0 | CLOSE | ✅ | |
| $A1 | GET | ✅ | GETKEY ($A1 $F9, GET+KEY) waits for a key -- string and numeric targets |
| $A2 | NEW | ✖ | direct-mode |
| $A3 | TAB( | 🔧 | inside PRINT |
| $A4 | TO | 🔧 | FOR / GO TO / MOVSPR |
| $A5 | FN | ✅ | FN name(arg): numeric arg to FAC, calls the DEF body; the DEF must appear textually before the first call |
| $A6 | SPC( | 🔧 | inside PRINT |
| $A7 | THEN | 🔧 | inside IF |
| $A8 | NOT | ✅ | |
| $A9 | STEP | 🔧 | inside FOR |
| $AA | + | ✅ | add / string concat |
| $AB | - | ✅ | subtract / unary minus |
| $AC | * | ✅ | |
| $AD | / | ✅ | |
| $AE | ^ | ✅ | |
| $AF | AND | ✅ | logical and bitwise |
| $B0 | OR | ✅ | logical and bitwise |
| $B1 | > | ✅ | |
| $B2 | = | ✅ | |
| $B3 | < | ✅ | |
| $B4 | SGN | ✅ | |
| $B5 | INT | ✅ | |
| $B6 | ABS | ✅ | |
| $B7 | USR | ⚠️ | register calling convention, not ROM FAC (documented divergence) |
| $B8 | FRE | ⚠️ | FRE(0)/FRE(-1) return 0 |
| $B9 | POS | ✅ | |
| $BA | SQR | ✅ | |
| $BB | RND | ✅ | sequence differs from ROM by design |
| $BC | LOG | ✅ | |
| $BD | EXP | ✅ | |
| $BE | COS | ✅ | |
| $BF | SIN | ✅ | |
| $C0 | TAN | ✅ | |
| $C1 | ATN | ✅ | |
| $C2 | PEEK | ✅ | |
| $C3 | LEN | ✅ | |
| $C4 | STR$ | ✅ | e-notation print threshold differs for small floats |
| $C5 | VAL | ✅ | |
| $C6 | ASC | ✅ | |
| $C7 | CHR$ | ✅ | factor support (assignments/concat) added 2026-07-07; was PRINT-item only before |
| $C8 | LEFT$ | ✅ | |
| $C9 | RIGHT$ | ✅ | |
| $CA | MID$ | ✅ | |
| $CB | GO | ✅ | GO TO |
| $CC | RGRAPHIC | ⚠️ | (screen,param) 0-10 per the book, mapped to FCM internals: 4 = (2^depth)-1, 5/6 = 15 when the canvas claims bank 4/5, 9/10 = 0 until DMODE/DPAT; book example prints identically |
| $CD | RCOLOR | ✅ | sources 0-3: background, text, highlight, border |
| $CE | — | prefix | extended functions, see below |
| $CF | JOY | ✅ | |
| $D0 | RPEN | ✅ | reads pens 0-2 |
| $D1 | DEC | ✅ | no space allowed before "(" (ROM rule) |
| $D2 | HEX$ | ✅ | |
| $D3 | ERR$ | ✅ | |
| $D4 | INSTR | ✅ | |
| $D5 | ELSE | ✅ | |
| $D6 | RESUME | ⚠️ | RESUME line only; bare RESUME / RESUME NEXT rejected |
| $D7 | TRAP | ✅ | bare TRAP disarms |
| $D8 | TRON | ✖ | debugger |
| $D9 | TROFF | ✖ | debugger |
| $DA | SOUND | ✅ | SID2+SID4, distinct from PLAY voices |
| $DB | VOL | ✅ | |
| $DC | AUTO | ✖ | editor |
| $DD | PUDEF | ❌ | |
| $DE | GRAPHIC | ⚠️ | CLR form only |
| $DF | PAINT | ⚠️ | repaints the seed pixel’s colour region (mode 0); modes 1/2 fall back to the same |
| $E0 | CHAR | ✅ | col,row,h,w,dir,string[,charset] with scaling + 4 directions (ROM fonts $29000/$29800/$2D000/$3D000); CHARDEF ($E0 $96) ✅ |
| $E1 | BOX | ✅ | both forms: two diagonal corners and the 4-corner path (+solid; path fill is row-span based -- exact for convex quads) |
| $E2 | CIRCLE | ✅ | fill, arcs (start/stop degrees), legs suppress, combs, filled pies |
| $E3 | PASTE | ✅ | pastes the GCOPY buffer at x,y (raw pixels, clipped) |
| $E4 | CUT | ✅ | x,y,w,h: GCOPY the region then fill it with the current pen; same buffer/budget as GCOPY (w*h*depth < 8192), over-budget cuts nothing |
| $E5 | LINE | ✅ | 1 pair draws a pixel; 2+ pairs draw a connected path |
| $E6 | MERGE | ✖ | editor |
| $E7 | COLOR | ✅ | text colour, same handler as FOREGROUND |
| $E8 | SCNCLR | ✅ | bare = text clear; SCNCLR colour fills the graphics bitmap |
| $E9 | XOR | ✅ | |
| $EA | HELP | ✖ | direct-mode |
| $EB | DO | ✅ | with WHILE/UNTIL clauses |
| $EC | LOOP | ✅ | with WHILE/UNTIL clauses |
| $ED | EXIT | ✅ | DO-loop exit |
| $EE | DIR | ✖ | direct-mode (no CATALOG either) |
| $EF | DSAVE | ❌ | |
| $F0 | DLOAD | ❌ | |
| $F1 | HEADER | ✅ | |
| $F2 | SCRATCH | ✅ | |
| $F3 | COLLECT | ✅ | |
| $F4 | COPY | ✅ | |
| $F5 | RENAME | ✅ | |
| $F6 | BACKUP | ❌ | |
| $F7 | DELETE | ✖ | editor (deletes program lines) |
| $F8 | RENUMBER | ✖ | editor |
| $F9 | KEY | ⚠️ | KEY number,string only (rewrites the $1000/$1010 editor table, probe-verified); bare/ON/OFF/LOAD/SAVE rejected |
| $FA | MONITOR | ✖ | direct-mode |
| $FB | USING | ❌ | PRINT USING queued |
| $FC | UNTIL | 🔧 | inside DO/LOOP |
| $FD | WHILE | 🔧 | inside DO/LOOP |
| $FE | — | prefix | extended statements, see below |
| $FF | π (pi) | ✅ | classic CBM packed value, full float precision |

## $CE-prefixed extended functions

| Bytes | Token | Status | Notes |
|---|---|---|---|
| $CE $02 | POT | ✅ | |
| $CE $03 | BUMP | ✅ | works with our COLLISION engine (VIC latch polling) |
| $CE $04 | LPEN | ✅ | |
| $CE $05 | RSPPOS | ✅ | |
| $CE $06 | RSPRITE | ✅ | |
| $CE $07 | RSPCOLOR | ✅ | |
| $CE $08 | LOG10 | ✅ | |
| $CE $09 | RWINDOW | ⚠️ | 0/1 window dims (tracked from the WINDOW command; raw ESC windows untracked), 2/3 live screen cols/rows from $D031 |
| $CE $0A | POINTER | ❌ | |
| $CE $0B | MOD | ✅ | |
| $CE $0C | PIXEL | ⚠️ | reads a pixel colour; stages through the DMA arg slots, so not usable inside a DMA statement argument list |
| $CE $0D | RPALETTE | ❌ | |
| $CE $0E | RSPEED | ❌ | |
| $CE $0F | RPLAY | ✅ | |
| $CE $10 | WPEEK | ✅ | MEGA65 addition; petcat gap, fixer rewrites |
| $CE $11 | DECBIN | ✅ | MEGA65 addition; petcat gap, fixer rewrites |
| $CE $12 | STRBIN$ | ✅ | MEGA65 addition; petcat gap, fixer rewrites |
| $CE $13 | HASBIT | ⚠️ | -1/0 bit test with SETBIT address rules; flat (>= $10000) addresses affected by KNOWN-ISSUES #6 |
| $CE $14 | RPT$ | ✅ | repeat string; >255 chars = STRING TOO LONG; petcat gap, fixer rewrites |

## $FE-prefixed extended statements

| Bytes | Token | Status | Notes |
|---|---|---|---|
| $FE $02 | BANK | ⚠️ | banks 0-127 = far 28-bit PEEK/POKE/WPEEK/WPOKE; >=128 = CPU view (default). LOAD/SAVE/SYS/WAIT stay CPU-view |
| $FE $03 | FILTER | ✅ | timbre parity verified 2026-07-06 |
| $FE $04 | PLAY | ✅ | M (modulation) / P (portamento) string directives parsed-ignored |
| $FE $05 | TEMPO | ✅ | |
| $FE $06 | MOVSPR | ✅ | angle#speed + TO interpolation, ROM-calibrated speed; ROM leaks motion across RUNs, we halt at exit (deliberate) |
| $FE $07 | SPRITE | ✅ | |
| $FE $08 | SPRCOLOR | ✅ | |
| $FE $09 | RREG | ✅ | A,X,Y,Z,S captured after every SYS |
| $FE $0A | ENVELOPE | ✅ | |
| $FE $0B | SLEEP | ✅ | frame-granular, rounds to nearest, min 1 frame |
| $FE $0C | CATALOG | ✖ | direct-mode |
| $FE $0D | DOPEN | ✅ | ,D/,U unit arguments unsupported |
| $FE $0E | APPEND | ✅ | |
| $FE $0F | DCLOSE | ✅ | |
| $FE $10 | BSAVE | ✅ | |
| $FE $11 | BLOAD | ✅ | |
| $FE $12 | RECORD | ❌ | |
| $FE $13 | CONCAT | ✅ | DOS combine form with explicit 0: source prefixes (CBDOS silently skips the append without them); SEQ files only (DOS rule) |
| $FE $14 | DVERIFY | ❌ | |
| $FE $15 | DCLEAR | ✅ | |
| $FE $16 | SPRSAV | ⚠️ | sprite#/string$ both directions (64-byte C64-style shapes, pointers read at screen+$3F8, VIC bank 0); array-cell targets rejected |
| $FE $17 | COLLISION | ✅ | first working implementation on the platform — the ROM's is unfinished |
| $FE $18 | BEGIN | ✅ | |
| $FE $19 | BEND | ✅ | |
| $FE $1A | WINDOW | ⚠️ | left,top,right,bottom[,clear] via editor ESC T/B; CHR$(19)×2 resets like the ROM. No range validation (ROM raises ILLEGAL QUANTITY on bad coords) |
| $FE $1B | BOOT | ⚠️ | BOOT filename$ chain-loads a PRG to its header address via a $1e00 trampoline and jumps; SYS/bare/,B/,P/,D/,U forms unsupported |
| $FE $1C | FREAD# | ❌ | |
| $FE $1D | WPOKE | ✅ | MEGA65 reassignment (petcat's table still says SPRDEF here); fixer rewrites |
| $FE $1E | FWRITE# | ❌ | |
| $FE $1F | DMA | ✅ | legacy 1MB form, mapped onto the enhanced engine |
| $FE $21 | EDMA | ⚠️ | copy/mix/swap/fill with 28-bit addresses (float args convert); hex literals stay 16-bit — write big addresses in decimal or expressions |
| $FE $23 | MEM | ❌ | |
| $FE $24 | OFF | 🔧 | argument keyword (MOUSE OFF) |
| $FE $25 | FAST | ❌ | MEGA65 runs full speed compiled anyway |
| $FE $26 | SPEED | ❌ | |
| $FE $27 | TYPE | ✖ | direct-mode |
| $FE $28 | BVERIFY | ❌ | |
| $FE $29 | (DIR)ECTORY | ✖ | direct-mode |
| $FE $2A | ERASE | ✅ | |
| $FE $2B | FIND | ✖ | editor |
| $FE $2C | CHANGE | ✖ | editor |
| $FE $2D | SET | ⚠️ | only as SETBIT ($FE $2D $FE $4E): set one bit, BANK-aware <=64K, flat 28-bit above |
| $FE $2E | SCREEN | ⚠️ | all forms: [s,]w,h,d, CLR c, DEF, OPEN [s][,resultvar], SET d,v (attic-backed double buffering), CLOSE [s] (view-aware: hidden screens close without leaving graphics); 320x200 and 640x200 at 256 colours (VIC-IV FCM, not bitplanes); 400-line modes need more chip RAM than exists at 8bpp |
| $FE $2F | POLYGON | ⚠️ | regular n-gon from xrad (yrad/drawsides/subtend accepted, ignored); angle + solid work |
| $FE $30 | ELLIPSE | ✅ | fill, arcs (start/stop degrees), legs suppress, combs, filled pies |
| $FE $31 | VIEWPORT | ❌ | graphics queued |
| $FE $32 | GCOPY | ✅ | copies x,y,w,h to the buffer; ROM budget honoured (w*h*depth/8 < 1KB, declared depth); over-budget empties the buffer instead of erroring |
| $FE $33 | PEN | ✅ | pens 0-2 stored per the book (1/2 are latent in default jam1 mode, same as the ROM; they become visible only under DMODE, unsupported) |
| $FE $34 | PALETTE | ⚠️ | screen,c,r,g,b and COLOR c,r,g,b; RESTORE unsupported |
| $FE $35 | DMODE | ❌ | graphics queued |
| $FE $36 | DPAT | ❌ | graphics queued |
| $FE $37 | FORMAT | ✅ | HEADER alias (same ROM routine, same compile path) |
| $FE $38 | GENLOCK | ✖ | C65 genlock hardware never existed on the MEGA65; no book reference page, dead token |
| $FE $39 | FOREGROUND | ✅ | 0–15; ≥16 raises ILLEGAL QUANTITY (matches ROM V920413, despite book saying 0–31) |
| $FE $3B | BACKGROUND | ✅ | 0–255 |
| $FE $3C | BORDER | ✅ | 0–255 |
| $FE $3D | HIGHLIGHT | ❌ | |
| $FE $3E | MOUSE | ✅ | MOUSE ON/OFF; position pair rejected (ROM rejects it too) |
| $FE $3F | RMOUSE | ✅ | 1351 IRQ driver with built-in pointer sprite |
| $FE $40 | DISK | ⚠️ | DISK cmd$ (raw DOS command) and bare DISK (prints fresh status); ,U unit unsupported |
| $FE $41 | CURSOR | ⚠️ | positioning only: CURSOR [col][,row] via KERNAL PLOT; ON/OFF/style forms rejected; no range validation (ROM raises ILLEGAL QUANTITY) |
| $FE $42 | RCURSOR | ✅ | RCURSOR colvar,rowvar (zero-based) |
| $FE $43 | LOADIFF | ❌ | |
| $FE $44 | SAVEIFF | ❌ | |
| $FE $45 | EDIT | ✖ | editor |
| $FE $46 | FONT | ❌ | |
| $FE $47 | FGOTO | ✅ | computed jump via emitted line table (header vector 7); miss raises UNDEF'D STATEMENT |
| $FE $48 | FGOSUB | ✅ | computed call, same table |
| $FE $4E | (BIT) | 🔧 | second half of SETBIT/CLRBIT; newer ROM token, petcat gap, fixer rewrites |
| $FE $4B | CHDIR | ✅ | MEGA65 addition; petcat gap |

| $FE $54 | VSYNC | ✅ | waits for the 9-bit raster line; newer ROM token, petcat gap, fixer rewrites |

Unlisted second bytes ($FE $20, $22, $3A, $49, $4A, $4C+) are mostly
unassigned; VSYNC at $54 shows newer ROMs do extend the range.

## Reserved-variable keywords (not tokens — recognized by name)

| Name | Status | Notes |
|---|---|---|
| TI | ✅ | jiffy clock read as seconds; CLR TI resets |
| TI$ | ✅ | RTC as "hh:mm:ss" |
| ST | ✅ | KERNAL status byte |
| DS | ✅ | drive status number |
| DS$ | ✅ | drive status text |
| ER | ✅ | last error number |
| EL | ✅ | last error line |
| T@&(c,r) | ✅ | screen-code array, read/write, dynamic SCRNPTR |
| C@&(c,r) | ✅ | colour array, read/write, dynamic COLPTR |

# BASIC65 Token Support Matrix

Status of every BASIC65 token in the compiler. Byte values verified
empirically against petcat (VICE 3.6.1) detokenization plus the known
MEGA65 ROM reassignments petcat predates (WPOKE, WPEEK, DECBIN,
STRBIN$, CHDIR — see `tools/fix-basic65-petcat-tokens.ps1`).
Compiler-side status extracted from the dispatch tables in
`src/basic65c.asm`.

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
| Single-byte $80–$FF | 125 (+3 prefix bytes) | 68 | 7 | 50 |
| $CE-prefixed functions | 17 | 12 | — | 5 |
| $FE-prefixed statements | 70 | 26 | 1 (OFF) | 43 |
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
| $96 | DEF | ❌ | DEF FN queued; byte also tails CHARDEF ($E0 $96) |
| $97 | POKE | ✅ | |
| $98 | PRINT# | ✅ | |
| $99 | PRINT | ✅ | PRINT USING not supported ($FB) |
| $9A | CONT | ✖ | direct-mode |
| $9B | LIST | ✖ | direct-mode |
| $9C | CLR | ✅ | plus CLR TI special form (timer reset) |
| $9D | CMD | ❌ | |
| $9E | SYS | ✅ | |
| $9F | OPEN | ✅ | |
| $A0 | CLOSE | ✅ | |
| $A1 | GET | ✅ | |
| $A2 | NEW | ✖ | direct-mode |
| $A3 | TAB( | 🔧 | inside PRINT |
| $A4 | TO | 🔧 | FOR / GO TO / MOVSPR |
| $A5 | FN | ❌ | DEF FN queued |
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
| $C7 | CHR$ | ✅ | |
| $C8 | LEFT$ | ✅ | |
| $C9 | RIGHT$ | ✅ | |
| $CA | MID$ | ✅ | |
| $CB | GO | ✅ | GO TO |
| $CC | RGRAPHIC | ❌ | graphics queued |
| $CD | RCOLOR | ❌ | graphics queued |
| $CE | — | prefix | extended functions, see below |
| $CF | JOY | ✅ | |
| $D0 | RPEN | ❌ | |
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
| $DE | GRAPHIC | ❌ | graphics queued |
| $DF | PAINT | ❌ | graphics queued |
| $E0 | CHAR | prefix | bare CHAR ❌; CHARDEF ($E0 $96) ✅ |
| $E1 | BOX | ❌ | graphics queued |
| $E2 | CIRCLE | ❌ | graphics queued |
| $E3 | PASTE | ❌ | |
| $E4 | CUT | ❌ | |
| $E5 | LINE | ❌ | graphics queued |
| $E6 | MERGE | ✖ | editor |
| $E7 | COLOR | ✅ | text colour, same handler as FOREGROUND |
| $E8 | SCNCLR | ❌ | use PRINT CHR$(147) |
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
| $F9 | KEY | ❌ | |
| $FA | MONITOR | ✖ | direct-mode |
| $FB | USING | ❌ | PRINT USING queued |
| $FC | UNTIL | 🔧 | inside DO/LOOP |
| $FD | WHILE | 🔧 | inside DO/LOOP |
| $FE | — | prefix | extended statements, see below |
| $FF | π (pi) | ❌ | use 3.14159265 or ATN(1)*4 |

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
| $CE $09 | RWINDOW | ❌ | |
| $CE $0A | POINTER | ❌ | |
| $CE $0B | MOD | ✅ | |
| $CE $0C | PIXEL | ❌ | graphics queued |
| $CE $0D | RPALETTE | ❌ | |
| $CE $0E | RSPEED | ❌ | |
| $CE $0F | RPLAY | ✅ | |
| $CE $10 | WPEEK | ✅ | MEGA65 addition; petcat gap, fixer rewrites |
| $CE $11 | DECBIN | ✅ | MEGA65 addition; petcat gap, fixer rewrites |
| $CE $12 | STRBIN$ | ✅ | MEGA65 addition; petcat gap, fixer rewrites |

## $FE-prefixed extended statements

| Bytes | Token | Status | Notes |
|---|---|---|---|
| $FE $02 | BANK | ❌ | |
| $FE $03 | FILTER | ✅ | timbre parity verified 2026-07-06 |
| $FE $04 | PLAY | ✅ | M (modulation) / P (portamento) string directives parsed-ignored |
| $FE $05 | TEMPO | ✅ | |
| $FE $06 | MOVSPR | ✅ | angle#speed + TO interpolation, ROM-calibrated speed; ROM leaks motion across RUNs, we halt at exit (deliberate) |
| $FE $07 | SPRITE | ✅ | |
| $FE $08 | SPRCOLOR | ✅ | |
| $FE $09 | RREG | ❌ | |
| $FE $0A | ENVELOPE | ✅ | |
| $FE $0B | SLEEP | ✅ | frame-granular, rounds to nearest, min 1 frame |
| $FE $0C | CATALOG | ✖ | direct-mode |
| $FE $0D | DOPEN | ✅ | ,D/,U unit arguments unsupported |
| $FE $0E | APPEND | ✅ | |
| $FE $0F | DCLOSE | ✅ | |
| $FE $10 | BSAVE | ✅ | |
| $FE $11 | BLOAD | ✅ | |
| $FE $12 | RECORD | ❌ | |
| $FE $13 | CONCAT | ❌ | |
| $FE $14 | DVERIFY | ❌ | |
| $FE $15 | DCLEAR | ✅ | |
| $FE $16 | SPRSAV | ❌ | queued |
| $FE $17 | COLLISION | ✅ | first working implementation on the platform — the ROM's is unfinished |
| $FE $18 | BEGIN | ✅ | |
| $FE $19 | BEND | ✅ | |
| $FE $1A | WINDOW | ❌ | |
| $FE $1B | BOOT | ❌ | |
| $FE $1C | FREAD# | ❌ | |
| $FE $1D | WPOKE | ✅ | MEGA65 reassignment (petcat's table still says SPRDEF here); fixer rewrites |
| $FE $1E | FWRITE# | ❌ | |
| $FE $1F | DMA | ❌ | |
| $FE $21 | EDMA | ❌ | |
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
| $FE $2D | SET | ❌ | |
| $FE $2E | SCREEN | ❌ | graphics queued |
| $FE $2F | POLYGON | ❌ | graphics queued |
| $FE $30 | ELLIPSE | ❌ | graphics queued |
| $FE $31 | VIEWPORT | ❌ | graphics queued |
| $FE $32 | GCOPY | ❌ | graphics queued |
| $FE $33 | PEN | ❌ | graphics queued |
| $FE $34 | PALETTE | ❌ | graphics queued |
| $FE $35 | DMODE | ❌ | graphics queued |
| $FE $36 | DPAT | ❌ | graphics queued |
| $FE $37 | FORMAT | ❌ | |
| $FE $38 | GENLOCK | ❌ | |
| $FE $39 | FOREGROUND | ✅ | 0–15; ≥16 raises ILLEGAL QUANTITY (matches ROM V920413, despite book saying 0–31) |
| $FE $3B | BACKGROUND | ✅ | 0–255 |
| $FE $3C | BORDER | ✅ | 0–255 |
| $FE $3D | HIGHLIGHT | ❌ | |
| $FE $3E | MOUSE | ✅ | MOUSE ON/OFF; position pair rejected (ROM rejects it too) |
| $FE $3F | RMOUSE | ✅ | 1351 IRQ driver with built-in pointer sprite |
| $FE $40 | DISK | ❌ | |
| $FE $41 | CURSOR | ❌ | |
| $FE $42 | RCURSOR | ❌ | |
| $FE $43 | LOADIFF | ❌ | |
| $FE $44 | SAVEIFF | ❌ | |
| $FE $45 | EDIT | ✖ | editor |
| $FE $46 | FONT | ❌ | |
| $FE $47 | FGOTO | ❌ | |
| $FE $48 | FGOSUB | ❌ | |
| $FE $4B | CHDIR | ✅ | MEGA65 addition; petcat gap |

Unlisted second bytes ($FE $20, $22, $3A, $49, $4A, $4C+) are unassigned
in the ROM as far as we know.

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

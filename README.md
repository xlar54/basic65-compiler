# BASIC65C

`basic65c.asm` is a MEGA65-native bootstrap compiler that reads a tokenized
BASIC PRG from disk and writes 64tass-compatible 45GS02 assembly as a SEQ file.

## Build

Run:

```bat
build.bat
```

This creates `target\basic65c.d81` containing:

- `basic65c` - the compiler PRG
- `source.prg` - a tiny tokenized BASIC PRG fixture built from `basic\source.bas`
- `out.prg` - the assembled compiler output, when `target\out.asm.seq` exists

The fixture is tokenized with:

```bat
petcat.exe -w65 -l 2001 -o target\source.prg -- basic\source.bas
```

Keep BASIC keywords lowercase in `basic\source.bas`; this `petcat` build
matches lowercase keywords when tokenizing.

## Run

Boot the D81, then:

```basic
LOAD"BASIC65C",8
RUN
```

The compiler raw-loads `SOURCE.PRG` into bank 4 at offset `$0000`, parses the
tokenized BASIC from RAM, and writes `OUT.ASM,S,W` on the same D81. Before
opening the output file it sends `S0:OUT.ASM` on the command channel, matching
the safer scratch-then-write pattern used elsewhere in the MEGA65 projects.
When the SEQ is exported back to the PC, keep it as `target\out.asm.seq`.

## Token Reference

Token values come from the project-provided BASIC65 keyword/token charts,
transcribed in `docs/basic65-tokens.md`. Extended BASIC65 tokens are represented
as two-byte `CE xx` and `FE xx` tokens.

## Runtime Direction

The generated programs are meant to stand on their own. The compiler may use
KERNAL calls for disk and console I/O, and generated programs may use KERNAL
where appropriate, but generated code should not call BASIC ROM routines.

The current generated runtime is deliberately small and organized around integer
work first:

- expression accumulator: `exprlo:exprhi`
- left-hand operand scratch: `lhslo:lhshi`
- math helpers: `mul16`, `div16`
- decimal output helper: `printuint`
- variable pointer: `varptr`, a 4-byte zero-page pointer used with 45GS02
  `[varptr],z` banked indirect addressing
- variable heap: bank 1 offset `$2000` through `$F7FF`
- variable descriptors: 16 bytes each, with current scalar integer data at
  descriptor offset `+8`

The generated variable heap deliberately avoids reserved bank-1 regions:

- physical `$10000-$11FFF` / bank-1 `$0000-$1FFF`: C65 KERNAL DOS variables
- physical `$1F800-$1FFFF` / bank-1 `$F800-$FFFF`: shared with color RAM mirror

## Current Compiler Passes

The compiler currently uses two passes over the tokenized source. `SOURCE.PRG`
is staged in bank 4 with the two-byte load address at offset `$0000`, and the
tokenized BASIC line chain starts at offset `$0002`:

```text
load address, then repeated:
  next-line pointer
  binary line number
  tokenized statement bytes
  $00 line terminator
final $0000 pointer
```

It emits line labels as hexadecimal BASIC line numbers, for example line 10
becomes `l000a:`.

Pass 1 records:

- source line numbers for label validation
- referenced `GOTO`, `GO TO`, `GOSUB`, and numeric `THEN` branch targets
- scalar variable descriptors for one- and two-character variable names

Pass 2 emits the 64tass-compatible assembly and validates branch targets against
the pass-1 line table. Missing or malformed branch targets become compiler
warnings and assembly comments instead of undefined assembler labels.

Supported BASIC today:

- one- and two-character integer variables
- integer arrays with `DIM`, up to 6 dimensions
- array indexes are zero-based and `DIM A(10)` allocates elements `A(0)` through `A(10)`
- array indexes are checked at runtime and print `ARRAY BOUNDS` on failure
- implicit assignment, for example `A=1+2`
- `LET` assignment
- 16-bit integer expressions with decimal and `$` hex literals
- expression operators `+`, `-`, `*`, `/`, unary `-`, and parentheses
- signed 16-bit integer comparisons in `IF`: `=`, `<>`, `<`, `<=`, `>`, `>=`
- `IF ... THEN line-number`
- `IF ... THEN` inline statements for the rest of the current BASIC line
- compound lines with `:` statement separators
- integer `FOR`/`NEXT` loops
- optional integer `STEP` in `FOR` loops
- integer `DATA` constants
- integer `READ` into scalar variables and array elements
- `RESTORE` back to the start of the generated data table
- `PRINT` string literals and integer expressions with comma/semicolon separators
  (comma advances to the next 10-column print zone)
- integer `PRINT` uses BASIC-style sign/trailing spacing
- `GOTO`, `GO TO`
- `GOSUB`
- `RETURN`
- `END`, `STOP`
- `SYS`
- `POKE` with expression address and expression value
- `REM`
- non-integer `DATA` fields are skipped for now

Unsupported statements are emitted as assembly comments so `OUT.ASM` remains
readable and assemblable while the compiler grows. Unsupported `CE xx` and
`FE xx` statements are reported with their full two-byte token value.

## Notes

- The compiler prints progress while it runs: loading source, scanning source,
  opening output, then `compiling line N`.
- `OUT.ASM` is emitted without an in-file `.cpu` directive, because the MEGA65
  disk text path may uppercase strings and 64tass treats the `45gs02` CPU name
  case-sensitively. Assemble it with
  `64tass --cbm-prg --m45gs02 target\out.asm.seq -o target\out.prg`.
- Numeric arguments can be decimal or hex with a `$` prefix.
- `SYS` currently accepts a literal 16-bit address.
- Generated code calls the KERNAL `CHROUT` vector for compiled `PRINT` output.
- The compiler and generated code avoid using `STZ` as "store zero"; on 45GS02
  `STZ` stores the Z register.
- Keep all readable BASIC test fixtures in `basic\`.

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

It also assembles `src\runtime\runtime.asm` standalone as a syntax/size check
and publishes its label map to `target\runtime.lbl`. The runtime is not
shipped on the D81; it is linked with the compiler's output on the PC side.

The BASIC fixtures are tokenized with `petcat`, then patched for known BASIC65
token gaps such as `WPOKE` and `WPEEK`:

```bat
petcat.exe -w65 -l 2001 -o target\source.prg -- basic\source.bas
powershell -NoProfile -ExecutionPolicy Bypass -File tools\fix-basic65-petcat-tokens.ps1 target\source.prg
```

Keep BASIC keywords lowercase in `basic\source.bas`; this `petcat` build
matches lowercase keywords when tokenizing.
`basic\source.bas` is organized as selectable subroutine tests. Set `ts` on
line 10 to `0` for all tests, or a feature-group number for one test group.
Negative fixtures live in `basic\` too. For example, `basic\bad_data.bas`
contains `DATA $2A`, which should halt compilation with a line-numbered error.
Build it onto the D81 as `SOURCE.PRG` with `build.bat basic\bad_data.bas`.

## Run

Boot the D81, then:

```basic
LOAD"BASIC65C",8
RUN
```

The compiler raw-loads `SOURCE.PRG` into bank 4 at offset `$0000`, parses the
tokenized BASIC from RAM, and writes both `OUT.ASM,S,W` (64tass source) and a
natively generated `OUT.PRG` on the same D81. The native program is produced
without any assembler: a size pass computes every address, then an emit pass
streams the runtime image from `RUNTIME.PRG` and the compiled machine code
(see `docs\native-backend.md`). `OUT.PRG` is byte-identical to what 64tass
assembles from `OUT.ASM`, and the test harness verifies that on every run.
Before opening the output file it sends `S0:OUT.ASM` on the command channel,
matching the safer scratch-then-write pattern used elsewhere in the MEGA65
projects. When the SEQ is exported back to the PC, keep it as
`target\out.asm.seq`; `build.bat` links it with the runtime into
`target\out.prg`:

```bat
64tass --cbm-prg --m45gs02 src\runtime\runtime.asm target\out.asm.seq -o target\out.prg
```

## Automated Testing

`tools\emu-test.ps1` runs a fixture end-to-end without touching the emulator:

```bat
powershell -File tools\emu-test.ps1 -Fixture basic\strings.bas
powershell -File tools\emu-test.ps1 -All
```

It builds the D81, boots xemu with `tools\bootstrap.bas` (which answers the
source-file prompt through the `$D619` PETSCII keyboard-injection register and
chain-loads the compiler), polls the D81 until `OUT.ASM` appears, links it
with the runtime, then chain-loads `OUT.PRG` with `tools\bootstrap-run.bas`
and captures the final screen. `bad_data.bas` is treated as a negative test
(it must fail to compile), and `ioarray.bas` is skipped because it blocks on
`INPUT`. Fixture output containing `FAIL` marks the fixture suspect; the exit
code is nonzero when anything fails.

Point `-Xemu` at your `xmega65.exe` if it is not at
`C:\Emulation\Mega65\xmega65.exe`.

## Token Reference

Token values come from the project-provided BASIC65 keyword/token charts,
transcribed in `docs/basic65-tokens.md`. Extended BASIC65 tokens are represented
as two-byte `CE xx` and `FE xx` tokens.

## Runtime Direction

The generated programs are meant to stand on their own. The compiler may use
KERNAL calls for disk and console I/O, and generated programs may use KERNAL
where appropriate, but generated code should not call BASIC ROM routines.

The runtime library lives in `src\runtime\runtime.asm` as real,
standalone-assemblable source. The compiler emits only the program: a header
vector table at `$4000` (`start`, `varheapend`, `datastart`, `dataend`,
`strroots`), the compiled statements, the string pool, the DATA table, the
string GC roots, and FOR/NEXT storage. The runtime occupies `$2001-$3fff`
(BASIC stub, `rtinit` entry at `$2012`, runtime code and storage) and never
references program symbols directly: `rtinit` copies the header vectors into
runtime variables, initializes the variable heap, string heap, and DATA
pointer, then jumps through the `start` vector. This keeps the runtime
program-independent so it can later ship as a fixed binary blob under a native
code generator.

The current generated runtime is deliberately small and organized around integer
work first:

- expression accumulator: `exprlo:exprhi`
- left-hand operand scratch: `lhslo:lhshi`
- math helpers: `mul16`, `div16`
- decimal output helper: `printuint`
- string literal output helper: `printstr`
- variable pointer: `varptr`, a 4-byte zero-page pointer used with 45GS02
  `[varptr],z` banked indirect addressing
- variable heap: bank 1 offset `$2000` through `$F7FF`
- variable descriptors: 16 bytes each, with current scalar numeric/string data at
  descriptor offset `+8`
- plain numeric scalar slots are tagged as integer values or decimal literal
  references; `%` variables continue to use raw 16-bit integer slots
- string heap: bank 1 offset `$F7FF` downward, using `$F800` as the
  one-past-top pointer so the reserved/color RAM mirror range is not used

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
- scalar variable descriptors for one- and two-character variable names,
  including type suffix identity

Pass 2 emits the 64tass-compatible assembly and validates branch targets against
the pass-1 line table. Missing or malformed branch targets are fatal compile
errors.

Supported BASIC today:

- one- and two-character numeric and string variables
- `A`, `A%`, and `A$` are separate symbols; plain numeric `A` uses tagged
  scalar storage, while `A%` uses raw 16-bit integer storage
- decimal float literal assignment and direct printing, for example `F=1.5`,
  `PRINT F`, and `PRINT 3.75`; float arithmetic/comparison is not implemented yet
- numeric and string arrays with `DIM`, up to 6 dimensions
- `A()`, `A%()`, and `A$()` are separate array symbols
- array indexes are zero-based and `DIM A(10)` allocates elements `A(0)` through `A(10)`
- array indexes are checked at runtime and print `ARRAY BOUNDS` on failure
- implicit assignment, for example `A=1+2`
- `LET` assignment
- 16-bit integer expressions with decimal and `$` hex literals
- expression operators `+`, `-`, `*`, `/`, unary `-`, and parentheses
- unary `NOT`, returning `1` for zero and `0` for nonzero
- signed 16-bit integer comparisons in `IF`: `=`, `<>`, `<`, `<=`, `>`, `>=`
- truthy integer `IF expr THEN`, where nonzero is true
- boolean `IF` conditions with comparisons joined by `AND` and `OR`
- `IF ... THEN line-number`
- `IF ... THEN` inline statements for the rest of the current BASIC line
- `IF ... THEN ... : ELSE ...` inline branches
- compound lines with `:` statement separators
- `DO`/`LOOP` structured loops
- `DO WHILE`, `DO UNTIL`, `LOOP WHILE`, and `LOOP UNTIL`
- `EXIT` from the innermost active `DO`/`LOOP`
- `EXIT FOR` from the innermost active `FOR`/`NEXT`
- integer `FOR`/`NEXT` loops
- optional integer `STEP` in `FOR` loops
- signed decimal integer and quoted string `DATA` constants
- mixed integer/string `DATA` streams with runtime type checks
- `READ` into scalar variables and array elements, for both numeric values and strings
- `RESTORE` back to the start of the generated data table
- `RESTORE line-number` for DATA lines
- `PRINT` string literals and integer expressions with comma/semicolon separators
  (comma advances to the next 10-column print zone)
- `PRINT CHR$(integer-expression)` for single-character/control-code output
- quoted `PRINT` literals are emitted once into a generated `strXXXX` string pool
  and printed through `printstr`; duplicate literals reuse the same pool entry
- heap-backed string variables with literal assignment, variable assignment,
  and string concatenation using `+`, for example `A$="HELLO"`, `B$=A$`,
  `C$=A$+" WORLD"`, and `PRINT C$`
- heap-backed string arrays with assignment, expression access, and direct
  `PRINT`, for example `DIM A$(2)`, `A$(0)="HELLO"`, and `PRINT A$(0)`
- string comparisons in `IF` conditions with `=`, `<>`, `<`, `<=`, `>`, and `>=`
- `LEN(string-expression)` inside integer expressions and conditions
- `VAL(string-expression)` inside integer expressions and conditions
- `LEFT$(string-expression, integer-expression)`,
  `RIGHT$(string-expression, integer-expression)`, and
  `MID$(string-expression, start-expression[, length-expression])`
- `STR$(integer-expression)` inside string expressions, using BASIC-style
  positive leading-space and negative minus-sign formatting
- string heap entries use one-byte lengths in this first pass, so an individual
  generated string is limited to 255 bytes
- `INPUT` into scalar numeric and string variables
- comma-delimited `INPUT` fields from one typed line, for example
  `INPUT "ENTER 42,-3,12345";N,M,Q$`
- quoted `INPUT` prompts
- `GET` into scalar numeric variables as a non-blocking PETSCII/key byte
- `GET` into scalar string variables as `""` when no key is waiting or a
  one-character heap string when a key is available
- integer `PRINT` uses BASIC-style sign/trailing spacing
- `GOTO`, `GO TO`
- `GOSUB`
- `ON integer-expression GOTO`
- `ON integer-expression GOSUB`
- `RETURN`
- `END`, `STOP`, terminating from any `GOSUB` depth via the runtime's `rtexit`
  stack unwind (falling off the end of the program behaves the same way)
- `SYS`
- `POKE` with expression address and expression value
- `REM`
- unsupported `DATA` fields, including hex-style fields such as `$2A`, are
  fatal compile errors for now

Unsupported or malformed statements are fatal compile errors with BASIC line
numbers. `OUT.ASM` is only replaced after a clean compile.

## Notes

- The compiler prints progress while it runs: loading source, scanning source,
  opening output, then line numbers side-by-side after `compiling:`.
- Fatal errors print the BASIC line number and halt. Generated source is written
  to `OUT.TMP` first and renamed to `OUT.ASM` only after a clean compile.
- `OUT.ASM` is emitted without an in-file `.cpu` directive, because the MEGA65
  disk text path may uppercase strings and 64tass treats the `45gs02` CPU name
  case-sensitively. Link it with the runtime:
  `64tass --cbm-prg --m45gs02 src\runtime\runtime.asm target\out.asm.seq -o target\out.prg`.
- Numeric arguments can be decimal or hex with a `$` prefix.
- `SYS` currently accepts a literal 16-bit address.
- Generated code calls the KERNAL `CHROUT` vector for compiled `PRINT` output.
- The runtime banks the C65 BASIC and editor ROMs out of `$8000-$cfff` while
  the program runs (VIC-III `$D030` ROM bits, restored on exit), so programs
  can grow to `$d000`. The compiler emits a `.cerror` guard that fails the
  PC-side assembly if a program would cross into I/O space.
- The compiler and generated code avoid using `STZ` as "store zero"; on 45GS02
  `STZ` stores the Z register.
- Keep all readable BASIC test fixtures in `basic\`.

## Benchmarks

Same program, same MEGA65 at 40MHz, interpreted vs compiled
(xemu, PAL; timed with CLR TI / PRINT TI):

| Benchmark | Workload | Interpreted | Compiled | Speedup |
|---|---|---|---|---|
| `basic/mandel.bas` | float multiply/add (Mandelbrot escape loop) | 4.87 s | 0.04 s | ~122x |
| `basic/sieve.bas` | integer + array (Byte Sieve, 3x8191 flags) | 21.13 s | 0.26 s | ~81x |
| `basic/ahl.bas` | SQR and ^ (Ahl's Simple Benchmark) | 0.78 s | 0.02 s | ~39x |

Ahl's accuracy figure: 2.27e-04 compiled vs 3.11e-04 interpreted --
the compiler's MFLP math lands slightly closer to the true value than
the ROM's float code.

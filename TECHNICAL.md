# BASIC65C Technical Reference

Build system, running the compiler, the automated test harness, and
the architecture of the runtime and compiler. For what BASIC65
language surface is supported, see [tokens.md](tokens.md) — it is the
maintained matrix and supersedes any feature list here.

## Build

```bat
build.bat [basic\fixture.bas]
```

creates `target\basic65c.d81` containing:

- `basic65c` — the MEGA65-native compiler with native output and an
  optional ASM export prompt
- `source.prg` — the tokenized BASIC fixture (default
  `basic\source.bas`, or the fixture named on the command line)
- `gfx` — the banked graphics blob (loaded to bank 5 at runtime by
  graphics programs)
- `out.prg` — the previous PC-side linked output, when present

It also assembles `src\runtime\runtime.asm` standalone as a
syntax/size check and publishes its label map to `target\runtime.lbl`,
from which `tools\gen-bin-templates.py` regenerates the native
backend's binary templates (`src\gen\bin-templates.inc`) and the
blob's shared addresses (`src\gfx\gfxshared.inc`).

BASIC fixtures are tokenized with `petcat`, then patched for known
BASIC65 token gaps (WPOKE, WPEEK, DECBIN, STRBIN$, CHDIR, HASBIT,
RPT$ — see `tools\fix-basic65-petcat-tokens.ps1`). Keep BASIC
keywords lowercase in fixture sources; this petcat build matches
lowercase keywords when tokenizing. Fixtures live in `basic\`;
negative fixtures (programs that must fail to compile, like
`basic\bad_data.bas`) live there too.

## Run

Boot the D81, then:

```basic
RUN"BASIC65C"
```

The compiler raw-loads `SOURCE.PRG` into bank 4, parses the tokenized
BASIC from RAM, prompts for an output base name, and writes a natively
generated PRG on the same D81. If the ASM prompt is answered `Y`, it
also writes the matching 64tass source as `<output>.ASM`. The native
program is produced without any assembler: a size pass computes every
address, then an emit pass streams the runtime image from
`RUNTIME.PRG` and the compiled machine code (see
`docs\native-backend.md`). When ASM export is enabled, the native PRG
is byte-identical to what 64tass assembles from the emitted source,
and the test harness verifies that on every run.

Before opening the ASM output it sends `S0:<output>.ASM` on the
command channel (scratch-then-write); generated source goes to
`OUT.TMP` first and is renamed to `<output>.ASM` only after a clean
compile. The native output uses the same scratch-and-rename discipline
for `<output>`. Disk errors are read back from the drive's DS channel
and reported (for example a write-protected disk).

To link on the PC side, export the SEQ as `target\out.asm.seq`:

```bat
64tass --cbm-prg --m45gs02 src\runtime\runtime.asm target\out.asm.seq -o target\out.prg
```

`OUT.ASM` is emitted without an in-file `.cpu` directive because the
MEGA65 disk text path may uppercase strings and 64tass treats the
`45gs02` CPU name case-sensitively.

## Automated testing

`tools\emu-test.ps1` runs a fixture end-to-end:

```bat
powershell -File tools\emu-test.ps1 -Fixture basic\strings.bas
powershell -File tools\emu-test.ps1 -Fixture basic\strings.bas -SkipRun
powershell -File tools\emu-test.ps1 -All
```

Phase 1 builds the D81, boots xemu with `tools\bootstrap.bas` (which
answers the input, output, and ASM prompts through the `$D619`
PETSCII keyboard-injection register and chain-loads `BASIC65C`),
polls the D81 until `OUT.ASM` appears, extracts the native program
file `OUT`, links `OUT.ASM` with the runtime on the PC, and
byte-compares the two
programs. Phase 2 (skipped with `-SkipRun`) writes the compiled
program to the D81 as `AUTOBOOT.C65`, boots it directly, and captures
the final screen.

Negative fixtures (must fail to compile) and interactive fixtures
(skipped: they block on keyboard input) are listed at the top of the
script. Point `-Xemu` at your `xmega65.exe` if it is not at
`C:\Emulation\Mega65\xmega65.exe`. Phase 1 occasionally times out on
an xemu boot stall — rerun the fixture (KNOWN-ISSUES #1).

## Token reference

Token values come from the MEGA65 book's BASIC65 keyword/token
charts, transcribed in `docs/basic65-tokens.md` and verified
empirically (monitor dumps of tokenized lines). Extended tokens are
two-byte `CE xx` and `FE xx` sequences. Per-token support status
lives in [tokens.md](tokens.md).

## Runtime architecture

Generated programs stand on their own: the compiler may use KERNAL
calls for disk and console I/O, and generated code may use KERNAL
where appropriate, but never BASIC ROM routines.

The runtime lives in `src\runtime\runtime.asm` as real,
standalone-assemblable source and never references program symbols
directly: the program carries a header vector table (`start`,
`varheapend`, `datastart`, `dataend`, `strroots`, float literals,
line table, graphics flag) that `rtinit` copies into runtime
variables before jumping through the `start` vector.

Memory map of a compiled program:

- `$2001` BASIC stub, `rtinit` entry at `$2012`
- runtime code and storage up to `progbase = $7100` (guarded by
  `.cerror`); the header vector table sits at the address recorded in
  the generated source (`rtpb`)
- compiled program: `$7100` up to `$D000` (`.cerror` guard in the
  emitted source **and** enforced natively by the size pass; graphics
  programs cap at `$C000`, where the 640-mode screen codes live)
- variable heap: bank 1 `$2000` upward — 16-byte descriptors, scalar
  value at descriptor offset `+8`; plain numeric scalars use tagged
  slots (integer or float reference), `%` variables raw 16-bit
- string heap: bank 1 from `$F7FF` downward with a compacting,
  attic-staged GC; individual strings cap at 255 bytes (one-byte
  lengths)
- reserved bank-1 regions the heap avoids: `$0000-$1FFF` (C65 KERNAL
  DOS variables) and `$F800-$FFFF` (color RAM mirror)
- bank 4: staged source during compilation; pixel data for graphics
  programs (`$40000+`, 640-wide spills through bank 5)
- attic RAM (`$8000000+`): graphics screen buffers, the blob image
  and swap stash, the GCOPY/CUT buffer, and the GC staging mirror

The runtime banks the C65 BASIC/editor ROMs out of `$8000-$CFFF`
while the program runs (VIC-III `$D030` ROM bits, restored on exit).
Runtime sections are emitted by level (`rtlevel`: core, +fio, +math,
+sound) so programs only carry what they use; the graphics library is
a separate 16KB blob DMA-swapped into `$8000-$BFFF` per call (see the
comments in `src\gfx\gfx.asm`).

## Compiler passes

`SOURCE.PRG` is staged in bank 4 (load address at offset `$0000`,
tokenized line chain from `$0002`: next-line pointer, binary line
number, tokenized bytes, `$00` terminator, final `$0000` pointer).

1. **Scan pass:** records line numbers for branch validation,
   registers every variable (name, type suffix, scalar/array), and
   flags which runtime subsystems the program needs (fio, math,
   sound, graphics, far memory, computed jumps).
2. **Branch validation:** every `GOTO`/`GOSUB`/`THEN` target must
   exist in the line table.
3. **Native size pass:** compiles everything with output suppressed
   to compute every address and the final program size (enforcing the
   memory-window cap).
4. **Emit passes:** text backend writes `<output>.ASM`; the native
   backend streams the program file (plus `<output>.NN` segment files
   for overlay programs) using binary templates patched with the
   addresses the size pass computed.

Line labels are hexadecimal BASIC line numbers (`l000a:` for line
10). Unsupported or malformed statements are fatal compile errors
with BASIC line numbers; the compiler prints progress (loading,
scanning, then line numbers) while it runs.

## Conventions

- Numeric arguments in fixtures can be decimal or hex with `$`.
- The compiler and generated code avoid `STZ` as "store zero" — on
  the 45GS02 it stores the Z register.
- Keep all readable BASIC test fixtures in `basic\`.

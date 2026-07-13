# BASIC65C

A MEGA65-native BASIC65 compiler. It runs on the MEGA65 itself, reads
a tokenized BASIC PRG from disk, and produces a ready-to-run
machine-language program named exactly what you choose (plus
`<output>.NN` overlay segments for programs larger than one memory
window, and optional 64tass-compatible 45GS02 assembly as
`<output>.ASM` for inspection or PC-side verification).
The native binary is generated without any assembler and is
byte-identical to what 64tass produces from the emitted source, which
the test harness verifies on every run.

Compiled programs stand on their own: a self-contained runtime
(integer and decimal-float math, strings with a compacting GC,
disk/file I/O, sound and PLAY, sprites, and a banked 256-colour FCM
graphics library) with no BASIC ROM calls. Interpreter parity is the
guiding principle — fixtures must behave identically interpreted and
compiled, and divergences are documented.

## Quick start

```bat
build.bat
```

builds `target\basic65c.d81`. Boot it and:

```basic
RUN"BASIC65C"
```

Keep the three companion files on the compiler disk: `+b65tpl` for ASM
templates, `+b65rtm` for native output, and `+b65gfx` for compiled
programs that use graphics.

Enter the input filename, output filename, and whether to generate
the ASM file. For example, `SOURCE.PRG`, `GAME`, and `Y` write the
runnable program `GAME` and its assembly `GAME.ASM` back to the same
disk; choosing `N` skips the ASM file. Output names are capped at 12
characters so every derived name fits the DOS 16-character limit; a
program too large for one memory window also writes overlay segments
`GAME.00`, `GAME.01`, ... which must accompany the program on disk. See [TECHNICAL.md](TECHNICAL.md) for the full
build, run, and test-harness documentation.

## Performance

Same program, same MEGA65 at 40MHz, interpreted vs compiled
(xemu, PAL; timed with CLR TI / PRINT TI). The figures below are from the 0.1s-resolution timer:

| Benchmark | Workload | Interpreted | Compiled | Speedup |
|---|---|---|---|---|
| `basic/mandel.bas` | float multiply/add (Mandelbrot escape loop) | 4.87 s | 1.8 s | ~2.7x |
| `basic/primes.bas` | integer MOD trial division up to 5000 | 8.20 s | 1.5 s | ~5.5x |
| `basic/sieve.bas` | integer + array (Byte Sieve, 3x8191 flags) | 21.13 s | 6.8 s | ~3.1x |
| `basic/ahl.bas` | SQR and ^ (Ahl's Simple Benchmark) | 0.78 s | 0.4 s | ~2x |
| `basic/gfxcircles.bas` | graphics (500 random CIRCLEs, 320x200x4) | 10.83 s | 2.5 s | ~4.3x |
| `basic/gfxboxes.bas` | graphics (200 filled 40x40 BOXes, 320x200x4) | 16.28 s | 1.1 s | ~15x |
| `basic/gfxlines.bas` | graphics (300 random LINEs, 320x200x4) | 2.08 s | 1.5 s | ~1.4x |
| `basic/gfxmandel.bas` | graphics + float (Mandelbrot, 320x200) | 752.7 s | 272.3 s | ~2.8x |
| `basic/gfxsurface.bas` | 3D hidden-line surface plot (sin(r)/r, 120x100 grid, 640x200) | 44.11 s | 32.3 s | ~1.4x |

Prime benchmark check values: 669 primes up to 5000, checksum 23136.

Ahl's accuracy figure: 2.27e-04 compiled vs 3.11e-04 interpreted --
the compiler's MFLP math lands slightly closer to the true value than
the ROM's float code.

Graphics timing convention: CLR TI right after SCREEN opens, TI read
after SCREEN CLOSE -- the figures cover rendering plus the return to
text. The graphics rows had a history: the compiled side originally
LOST these (28.5 s circles) because the FCM mode switch was silently
dropping the CPU to 3.5 MHz -- an absolute write to $D054 cleared the
VFAST bit. With the speed preserved, horizontal spans drawn through a
one-address cell walk, lines walked with incremental Bresenham
addressing, and table-based pixel addressing (no hardware-multiplier
round trips), compiled graphics beat the interpreter across the
board. What remains in the compiled figures is mostly per-statement
overhead (argument staging plus the 4x16KB graphics-blob DMA swap per
drawing statement) -- shrinking the swap is the next lever if it ever
matters.

## Documentation

- [tokens.md](tokens.md) — the full BASIC65 token support matrix:
  every token, its status, and documented divergences
- [TECHNICAL.md](TECHNICAL.md) — build system, running the compiler,
  the automated test harness, runtime architecture and memory map,
  compiler passes
- [KNOWN-ISSUES.md](KNOWN-ISSUES.md) — open defects and current
  capacity limits
- [docs/native-backend.md](docs/native-backend.md) — how the
  assembler-less native PRG generation works

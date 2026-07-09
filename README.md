# BASIC65C

A MEGA65-native BASIC65 compiler. It runs on the MEGA65 itself, reads
a tokenized BASIC PRG from disk, and produces both 64tass-compatible
45GS02 assembly (`OUT.ASM`) and a ready-to-run machine-language
program (`OUT.PRG`) — the native binary is generated without any
assembler and is byte-identical to what 64tass produces from the
emitted source, which the test harness verifies on every run.

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

Answer the source-file prompt (RETURN compiles the bundled
`SOURCE.PRG`), and the compiler writes `OUT.ASM` and `OUT.PRG` back
to the same disk. See [TECHNICAL.md](TECHNICAL.md) for the full
build, run, and test-harness documentation.

## Performance

Same program, same MEGA65 at 40MHz, interpreted vs compiled
(xemu, PAL; timed with CLR TI / PRINT TI):

| Benchmark | Workload | Interpreted | Compiled | Speedup |
|---|---|---|---|---|
| `basic/mandel.bas` | float multiply/add (Mandelbrot escape loop) | 4.63 s | 0.16 s | ~29x |
| `basic/primes.bas` | integer MOD trial division up to 5000 | 7.87 s | 0.02 s | ~394x |
| `basic/sieve.bas` | integer + array (Byte Sieve, 3x8191 flags) | 20.13 s | 0.26 s | ~77x |
| `basic/ahl.bas` | SQR and ^ (Ahl's Simple Benchmark) | 0.758 s | <0.02 s | >45x |
| `basic/circles.bas` | graphics (100 random CIRCLEs, 640x200x4) | 2.23 s | 3.44 s | ~0.6x |

Prime benchmark check values: 669 primes up to 5000, checksum 23136.

Ahl's accuracy figure: 2.27e-04 compiled vs 3.11e-04 interpreted --
the compiler's MFLP math lands slightly closer to the true value than
the ROM's float code.

The circles row is an honest loss: the compiled graphics library
draws through a per-pixel plotter (two hardware multiplies per pixel
for the FCM cell address) plus a DMA blob swap per statement, while
the ROM's CIRCLE uses optimized bitplane span code. Span-based shape
rendering in the blob is the known fix if graphics throughput starts
to matter.

## Documentation

- [tokens.md](tokens.md) — the full BASIC65 token support matrix:
  every token, its status, and documented divergences
- [TECHNICAL.md](TECHNICAL.md) — build system, running the compiler,
  the automated test harness, runtime architecture and memory map,
  compiler passes
- [KNOWN-ISSUES.md](KNOWN-ISSUES.md) — open defects and current
  capacity limits
- [docs/native-backend.md](docs/native-backend.md) — how the
  assembler-less native OUT.PRG generation works

# Native code generation roadmap

The end goal: `basic65c` writes `OUT.PRG` directly on the MEGA65, with no
64tass round trip. 64tass then retires to a verification role. This document
records the design the runtime extraction was shaped around.

## Where the current architecture already points

- **The memory contract is frozen and binary-friendly.** The runtime owns
  `$2001-$3fff` (stub + `rtinit` at `$2012`) and never references program
  symbols; programs start at `$4000` with a five-vector header and may grow to
  `$d000`. A native backend emits the assembled runtime image as the fixed
  first bytes of every `OUT.PRG` and appends the program.
- **`src\runtime\runtime.asm` assembles to that image today.** `build.bat`
  already produces it standalone (`target\runtime.prg` plus `runtime.lbl`,
  which gives the backend every runtime entry address as a constant).
- **Codegen is deterministic template expansion.** Every `emit_*` routine in
  `basic65c.asm` writes a fixed text shape with a few substituted bytes
  (hex operands, label ids). Each text template has an exact binary
  equivalent with fixed size and fixed patch offsets.

## Plan

1. **Byte templates beside text templates.** For each `out_*` text blob the
   compiler emits into programs, add a binary record: length, opcode bytes,
   and patch descriptors (offset + kind: expr-lo/hi, varptr address, label
   ref, runtime entry). The `emit_*` call sites do not change; each emitter
   routine gains a binary path selected by a backend mode flag.
2. **Address resolution without backpatching.** Because template sizes are
   fixed, run the existing pass-2 walk twice in binary mode:
   - *size pass*: execute the emitters in "count only" mode, recording each
     BASIC line's start address in the line table (pass 1 already proves all
     branch targets exist), plus final addresses for the string pool, DATA
     table, GC roots, and FOR storage;
   - *emit pass*: stream the finished bytes; every `jmp l000a` and label
     reference is already known. No fixups, no output buffer.
3. **Runtime image embedding.** Ship the assembled runtime image (from
   `runtime.asm`) with the compiler (on the D81, loaded like the old
   overlays but as opaque binary), copy it to `OUT.PRG` first, then stream
   the program. Runtime entry addresses come from `runtime.lbl` at compiler
   build time, generated into an include so they can never drift.
4. **Differential verification.** In dual mode the compiler emits both
   `OUT.ASM` and `OUT.PRG`. The PC side assembles `OUT.ASM` with 64tass and
   byte-compares against the native `OUT.PRG` for every fixture
   (`tools\emu-test.ps1` already automates compile/extract/link/run). Any
   divergence is a backend bug at an exact offset. When the corpus matches,
   the text path becomes an optional debug mode.

## Order of work

1. Generate `src\runtime\runtime.inc` (entry-point constants) from
   `target\runtime.lbl` during `build.bat`; make the compiler use symbolic
   entries so text and binary paths share one source of truth.
2. Add the backend mode flag and the size-pass plumbing to the pass-2 walk.
3. Convert templates in slices, byte-diffing fixture output after each slice:
   expression/variable codegen first, then control flow, then strings/IO
   statement bodies, then the tail tables (pool, DATA, roots, FOR storage).
4. Write `OUT.PRG` on the MEGA65 (`,P,W` channel), embed the runtime image,
   and flip the default; keep `OUT.ASM` behind an option as the debug/oracle
   mode.

## Invariants to preserve

- Template sizes must stay deterministic: no emitter may vary its binary
  length based on operand values (hex formatting width is already fixed).
- The `$4000` header vector layout and `$d000` ceiling are load-bearing for
  both backends; change them only in `runtime.asm` and the header emitters
  together.
- `rtinit`/`rtexit` own all ROM banking; generated code must never touch
  `$d030`.

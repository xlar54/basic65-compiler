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

1. **Byte templates derived from the text templates.** The `out_*` text
   blobs stay the single source of truth. A PC-side generator
   (`tools\gen-bin-templates.py`) extracts every emitted blob from
   `basic65c.asm`, assembles it with 64tass against `target\runtime.lbl`
   (so runtime entry addresses are baked into the bytes -- the compiler
   never needs a runtime address table), and writes an include of binary
   records: length + opcode bytes. Prefix fragments that end mid-operand
   (`lda #$`) are completed with a dummy operand and recorded with their
   patch offset; comment-only templates record as empty. Hand-maintaining
   parallel byte templates would recreate the dual-representation trap the
   overlays were, so nothing binary is written by hand.
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
   the program. Runtime addresses never appear in compiler code: the
   template generator bakes them into the derived byte templates, so the
   compiler and runtime cannot drift (a stale template include fails the
   byte-diff immediately).
4. **Differential verification.** In dual mode the compiler emits both
   `OUT.ASM` and `OUT.PRG`. The PC side assembles `OUT.ASM` with 64tass and
   byte-compares against the native `OUT.PRG` for every fixture
   (`tools\emu-test.ps1` already automates compile/extract/link/run). Any
   divergence is a backend bug at an exact offset. When the corpus matches,
   the text path becomes an optional debug mode.

## Emission ops (binary mode)

The text path is built from a handful of primitives; each gets a binary
meaning, so the `emit_*` call sites stay untouched:

- `out_zstr(template)` -> copy the template's derived byte record
- `out_hex_byte(A)` after an operand-prefix template -> emit A raw (1 byte)
- label-reference builders (`out_line_ref`, `out_if_ref`, ...) -> emit the
  resolved 16-bit address little-endian (from the size-pass tables)
- label definitions (`emit_line_label`, `emit_label_suffix`) -> record the
  current PC in the matching table; emit nothing
- `out_cr`, comment templates -> emit nothing
- relative branches to generated labels (`bne if0001` built from prefix +
  id) -> rel8 patch computed from the size-pass label table
- header/pool/DATA/roots/FOR-storage directive templates -> small special
  cases in the tail emitters (write vector words / raw bytes directly)

## Order of work

1. Build `tools\gen-bin-templates.py` and wire it into `build.bat`;
   validate the derived records against hand-checked known templates.
2. Add the backend mode flag and the size-pass plumbing to the pass-2 walk,
   plus address tables for generated labels (line table already exists).
3. Convert the emission primitives to mode dispatch in slices, byte-diffing
   fixture output after each slice: expression/variable codegen first, then
   control flow, then strings/IO statement bodies, then the tail tables.
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

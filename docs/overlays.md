# Program Overlays

Compiled programs larger than the program window are split into
segments that swap through the window on demand — the same mechanism
the graphics blob already uses (attic storage, DMA swap, resident
trampoline), pointed at program code instead of library code.

## Invariants

- **Programs that fit are untouched.** Segmentation engages only when
  the size pass finds the program past the window cap. A
  non-segmented compile stays byte-for-byte identical to today's
  output; the harness byte-diff enforces this.
- **Interpreter parity is unchanged.** Segmentation is invisible at
  the BASIC level except for speed (a segment crossing costs ~1-2ms).
- **Byte-diff discipline holds.** The text backend emits segments as
  64tass `.logical` blocks laid out consecutively, producing one
  verification image; the harness concatenates the native outputs
  (the program file + <output>.00 + <output>.01 + ...) and byte-compares against it.

## Memory layout (segmented program)

Bank 0:

```
$2001-$71FF  runtime (unchanged)
$7200-       resident block: header, overlay trampoline + DMA list +
             segment stack, segment loader, string literal pool, DATA
             table, float literals, FOR/NEXT slots, GC roots, line
             table (all mutable or shared emitted artifacts)
segbase      = page-aligned end of the resident block
segbase-$BFFF (graphics) / -$CFFF: the swap window; every segment
             assembles at segbase
```

Attic: segment n is stored at `$81B0000 + n*$8000` (32KB stride;
after the GCOPY buffer at $81A0000). Segment 0 is also stored there —
the window is pure swap space, no resident code lives in it.

Disk: the program file (runtime + resident block) plus <output>.00, <output>.01... (segment files named from the chosen output base)
(one per segment). rtinit-driven emitted loader reads them through
the DOS data channel into attic, exactly like the GFX blob load
(KERNAL LOAD cannot reach the high banks). Small programs remain a
single program file.

## Why nothing mutable lives in segments

Segments are pure code. All mutable emitted state (FOR slots) and all
shared read-only artifacts (literals, DATA, line table) live in the
resident block. Therefore a segment swap is **one inbound DMA copy —
no copy-back** — and no state is ever lost by evicting a segment.

## Cut rules

The size pass may cut only at a line boundary where `for_sp`,
`do_sp`, and `begin_sp` are all zero (no open FOR/DO/BEGIN block), so
every structured branch (NEXT/LOOP back-edges, BEND targets, IF/ELSE
intra-line labels) stays segment-local. A single structure larger
than the whole window is a compile error. When the running size
crosses the window cap, the cut lands at the last eligible boundary.

## Control flow across segments

All cross-segment transfers resolve through the line table, whose
records gain a segment id (compile-time records in bank 4; the
emitted FGOTO table format is extended only in segmented mode).

- **GOTO / THEN line / ELSE line:** same segment emits today's
  `jmp l_xxxx`. Cross-segment emits `jsr seggoto` + inline
  `.word addr / .byte seg`: the trampoline discards the return
  address, DMA-swaps the target segment, updates cur_seg, jumps.
- **GOSUB:** cross-segment emits `jsr seggosub` + inline operands.
  The trampoline records (caller_seg, resume) on a small segment
  stack in the resident block, swaps, and `jsr`s the target; when the
  callee's plain RTS unwinds back into the trampoline, it swaps the
  caller's segment back and jumps to resume. Same-segment GOSUB/
  RETURN keep the plain jsr/rts. Nesting composes naturally; GOTO
  out of a subroutine leaves stale entries exactly as plain GOSUB
  leaves stale stack (rtexit unwinds at END).
- **Fall-through at a cut:** the compiler ends the segment with a
  `jsr seggoto` hop to the next segment's first line.
- **ON GOTO/GOSUB:** each arm is an ordinary line reference and takes
  the same-seg/cross-seg form independently.

## Cross-segment control flow (working)

Every line-number transfer in a segmented program (GOTO, GOSUB, THEN,
ELSE, ON..GOTO/GOSUB, RESUME line) emits `jsr seglgoto`/`jsr
seglgosub` with the **line number** as the inline operand. The runtime
resolves address + segment through the emitted line table — segmented
tables always exist and carry 5-byte records (line, addr, segment) —
and swaps segments when needed; `seglgosub` shares `seggosub`'s frame
so the callee's plain RETURN restores the caller's segment. Same-
segment transfers use the identical path: one deterministic size plan,
no per-reference classification (a sticky-bit optimizer for hot
same-segment jumps is sketched in-tree, inert). FGOTO/FGOSUB dispatch
through core pointers (`fgdptr`/`fgsptr`) that the startup stub
repoints at the overlay-aware forms, keeping core runtime bytes
level-invariant for the byte-diff discipline.

Hazard notes earned during bring-up: never probe the DOS status
channel while an output file is open (closing the command channel
closes every file on the unit), and the segment base must add the
segmented line-table growth to the plain-pass artifact measurement.

## v1 restrictions (loud compile errors, lifted later)

- TRAP in a segmented program (the trap vector must learn segments;
  same line-table resolution as seglgoto would lift it).
- DEF FN in a segmented program (FN bodies are non-line labels; the
  clean lift is forcing DEF bodies into the resident block).
- COLLISION with a handler line (the armed handler address is jumped
  between statements regardless of the current segment).

## Runtime cost: zero bytes

The runtime is full ($71FF/$7200). The trampoline, DMA list, segment
stack, and loader are **emitted into the resident block as templates**
only when the program is segmented; the loader uses the runtime's
existing fio primitives (a segmented program sets fio_used). The
resident runtime does not grow.

## Compiler pass structure

Artifact addresses move ahead of the code, so segmented compiles run
one extra sizing iteration:

1. size pass A: full compile, artifacts counted, segmentation planned
   (cut points chosen against a provisional segbase)
2. size pass B: segbase fixed, addresses final
3. emit passes (text + native), emission switching output files at
   each cut

## Milestones

1. **Planner** (this branch, first): the size pass tracks cut
   eligibility and, when a program exceeds the window, reports the
   segmentation plan (`OVERLAY PLAN: n SEGMENTS`) — no output changes.
2. Resident-block emission reorder + segbase plumbing.
3. Trampolines + cross-segment reference emission, both backends.
4. Segment file output + emitted loader; harness concatenated
   byte-diff.
5. lcp.bas end-to-end on hardware.

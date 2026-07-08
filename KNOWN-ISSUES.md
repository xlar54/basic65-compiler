# Known Issues

Open defects, tracked with their investigation state. Documented
divergences from the interpreter (by design or ROM quirk) live in
[tokens.md](tokens.md) and docs/interpreted-sweep.md instead.

## 1. String corruption after heavy GC churn (PARTIALLY FIXED)

**Fixed 2026-07-07:** compiled code parked string descriptors on the
CPU stack across nested string operations (concat, LEFT$/RIGHT$/MID$,
INSTR, string compares, RENAME/COPY stashes) -- invisible to the GC
root walk, so a mid-expression collection recycled them. All those
sites now park in a GC-visible temp-slot block inside the runtime
image, walked as the GC's synthetic first region. This was the source
of the original random garbage/black-text symptom (verified: zero
control bytes through the print path across the full suite).

**Still open -- compaction ordering:** the copying GC visits strings
in root-table order while the destination frontier descends from the
heap top, so a string's destination can overwrite a NOT-YET-VISITED
string's source. Rare with few live strings; guaranteed under
source.bas-scale churn (test 11 prints array cells containing churn
fragments). Fix design: stage the compaction in an attic mirror
($800xxxx = final address) so pass 1 never touches the heap, then
copy the packed block back; a first attempt corrupted memory via the
EDMA writeback and was reverted -- verify EDMA-from-GC in isolation
(or use a CPU copy-back loop) next session. The temp-slot machinery,
attic relocation map, and bank-aware synthetic-region walker are all
in place and committed.

## 2. Program-shape-dependent false "UNSUPPORTED TOKEN" at compile

**Symptom:** a reduced variant of the test suite (source.bas with
most gosubs removed from line 20) fails to compile with
"ERROR LINE 12040: UNSUPPORTED TOKEN" pointing at a WPOKE statement
whose tokenized bytes are verified correct ($FE $1D). Supersets of
the same file compile fine. Something about program size/label
population desynchronizes the compiler before that line.

**Status (2026-07-06):** reproducible; not yet bisected. The affected
statement compiles correctly in every shipped fixture.

## 3. Harness phase-1 timeout on large fixtures

**Symptom:** `tools/emu-test.ps1` reports "no OUT.ASM in 240 s" for
source.bas-sized fixtures even though the same compile succeeds in a
manual xemu run (~2-3 min). The polling copy of the D81 appears to
race the emulated writes.

**Workaround:** manual chain — `build.bat basic\X.bas`, boot xemu
with `-prg target\bootstrap.prg -dumpscreen`, extract OUT.PRG with
c1541, write it back as AUTOBOOT.C65, boot again with `-dumpscreen`.

## 4. ~~CHR$ unusable outside PRINT~~ (FIXED 2026-07-07)

CHR$ was only handled as a PRINT item; assignments and concatenation
(`k$="dir"+chr$(13)`) failed with the generic BAD-expression error.
No fixture had ever exercised it. Fixed by adding the CHR$ string
factor (chrstrf shares GET's one-byte-string tail); covered by
basic/key.bas.

## 5. BANK far-PEEK reads the wrong memory for banks >= 4

Observed 2026-07-08 while bringing up banked graphics: with the GFX
blob proven present at $50000 (xemu -dumpmem ground truth), `BANK 5 :
PEEK(0)` returned 255,133,0,32 -- and `BANK 1`/`BANK 4` PEEKs of low
addresses returned the same leading bytes, which look like CPU-visible
zero-page, not the target bank. POKE/PEEK round-trip fixtures pass, so
the write side may be broken symmetrically (round trips cancel out).
Suspect peekbk/bankptr far-pointer setup. Verify with -dumpmem after a
BANK 4 POKE to a fresh address.

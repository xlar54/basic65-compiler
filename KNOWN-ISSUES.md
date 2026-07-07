# Known Issues

Open defects, tracked with their investigation state. Documented
divergences from the interpreter (by design or ROM quirk) live in
[tokens.md](tokens.md) and docs/interpreted-sweep.md instead.

## 1. String corruption after heavy GC churn in large programs

**Symptom:** compiled source.bas (and similar large programs) can
print string variables containing recycled heap bytes after the GC
stress tests; stray control bytes among them change the KERNAL text
colour (screen text turns black/odd colours mid-run and stays that
way at READY). The interpreter runs the same program clean.

**Status (2026-07-06):** mechanism proven — a heap string printed via
`printheapstr` holds stale content after compaction. Two real GC
hazards were found and fixed along the way (commit 21454ab: register
roots for sources held across stralloc, and an old→new relocation map
for multiply-referenced strings), but the symptom persists, so a
third defect remains. Prime suspect: the emitted STRROOTS table may
omit some string variables in variable-heavy programs (unrooted slots
are never updated by compaction), but a minimal mixed-DIM probe emits
all roots correctly — the bug needs the full program context.
`basic/strarrgc.bas` (arrays + INPUT + churn) passes and does NOT
reproduce. Diagnostic tooling and next steps are recorded in the
project memory (string-corruption-hunt).

**Workaround:** none needed for small/medium programs; only observed
with source.bas-scale variable counts plus thousands of string
allocations.

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

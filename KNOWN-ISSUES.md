# Known Issues

Open defects, tracked with their investigation state. Documented
divergences from the interpreter (by design or ROM quirk) live in
[tokens.md](tokens.md) and docs/interpreted-sweep.md instead.
Resolved issues are removed from this file; their write-ups live in
the git history (this file's log and the fixing commits' messages).

## 1. Program-shape-dependent false "UNSUPPORTED TOKEN" at compile

**Symptom:** a reduced variant of the old test suite (source.bas with
most gosubs removed from line 20) failed to compile with
"ERROR LINE 12040: UNSUPPORTED TOKEN" pointing at a WPOKE statement
whose tokenized bytes are verified correct ($FE $1D). Supersets of
the same file compiled fine. Something about program size/label
population desynchronizes the compiler before that line.

**Status (2026-07-09):** reproducible at last attempt (2026-07-06);
not yet bisected. The affected statement compiles correctly in every
shipped fixture. Note: the variable scanner's silent failure path now
prints "cannot resolve variable (out of symbols?)" (added with DEF
FN) -- if this phantom was actually a table-limit overflow, the next
repro will say so instead of pointing at an innocent token.

## 2. Harness phase-1 timeout (boot stall)

**Symptom:** `tools/emu-test.ps1` occasionally reports "no OUT.ASM in
240 s" even though the same fixture compiles in ~2-3 min; the same
invocation passes on retry (most recently input.bas, 2026-07-09).
Believed to be the xemu boot-banner stall; the manual autoboot chain
retries up to 3x for the same reason, the harness does not retry.

**Workaround:** rerun the fixture. Manual chain if needed:
`build.bat basic\X.bas`, boot xemu with `-prg target\bootstrap.prg
-dumpscreen`, extract OUT.PRG with c1541.

## 3. BSAVE with P(expr) address forms halts silently

**Symptom:** BSAVE using computed P(expr) start/end addresses halts
the compiled program without an error message. Literal P addresses
(as in disk.bas) work. Not yet investigated.

## Capacity watch (not defects, but current hard limits)

- **Runtime core is full:** rtendsound = $70FA vs progbase = $7100 --
  6 bytes of headroom (guarded by .cerror). The next runtime addition
  forces the graphics-trampoline carve-out (~250 bytes), sectioned
  emission, or a progbase bump (costs every program 256 bytes of the
  24KB window).
- **Checked compiler:** valued content ends $BE32 (~460 bytes below
  the $C000 guard) after squeeze round 2 (string/data-line scratch
  moved into the $C000 tail, SYM_MAX 96 -> 64; fixture peak is ~44
  symbols).
- **Graphics blob:** ~14.1KB of the 16KB bank-5 budget (~2.3KB free).
- **Program window:** any single program is bound by $7100-$D000
  (~24KB emitted). Program overlays (attic segments + line-table
  trampoline) are the plan when a real program outgrows it.

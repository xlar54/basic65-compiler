# Known Issues

Open defects, tracked with their investigation state. Documented
divergences from the interpreter (by design or ROM quirk) live in
[tokens.md](tokens.md) and docs/interpreted-sweep.md instead.
Resolved issues are removed from this file; their write-ups live in
the git history (this file's log and the fixing commits' messages).

## 2. Graphics-idle KERNAL crash (gfxclock)

**Symptom:** a compiled program that stays in graphics mode while
looping (gfxclock) dies after a couple of seconds with an unhandled
memory write to colour RAM + a huge offset (e.g. $FF88E90, PC=$EBB6
inside the C65 KERNAL editor's clear/scroll far-store `sta [$e0],z`).
Reproduces in xemu and on real hardware; chain-started runs sometimes
survive where a manually typed RUN crashes. The bitmap itself was
verified pixel-perfect -- this is display/IRQ-side state, not drawing.

**State:** the KERNAL IRQ's screen service writes through pointers
whose recomputation goes insane in graphics mode; the $CC cursor
save/disable at rtinit did not stop it. Suspects: editor line-link /
logical-screen state interacting with the FCM mode switch. Not caused
by GET or TI$ (bisected away). Open.

## 1. Harness phase-1 timeout (boot stall)

**Symptom:** `tools/emu-test.ps1` occasionally reports "no OUT.ASM in
240 s" even though the same fixture compiles in ~2-3 min; the same
invocation passes on retry (2026-07-09: input.bas once, then deffn
and gfxtest back-to-back -- the rate is not negligible).
Believed to be the xemu boot-banner stall; the manual autoboot chain
retries up to 3x for the same reason, the harness does not retry.

**Workaround:** rerun the fixture. Manual chain if needed:
`build.bat basic\X.bas`, boot xemu with `-prg target\bootstrap.prg
-dumpscreen`, extract OUT.PRG with c1541.

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

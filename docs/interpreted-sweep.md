# Interpreted fixture sweep checklist

The interpreter is the reference implementation: every fixture should
run under BASIC65 unless noted, and print the same OK lines as its
compiled build. Load each `basic/*.bas` (tokenized copies are on the
D81 by name) and RUN. Check the box when the interpreted output
matches the compiled output.

## Full parity expected (same OKs both ways)

- [ ] source.bas       (the 15-test suite; run with TS=0 for all tests)
- [ ] expr.bas, data.bas, fact.bas, endsub.bas, gc.bas, intfunc.bas,
      mem.bas, strarray.bas, strings.bas, types.bas, floats.bas
- [ ] tier1a.bas .. tier1f.bas   (RND/bitwise/^/BEGIN/file I/O/TRAP)
- [ ] math.bas         (SIN..EXP, 10 asserts)
- [ ] bin.bas          (DECBIN/STRBIN$ -- verified 2026-07-06)
- [ ] cheap.bas        (XOR/MOD/LOG10/FRE/ERR$/SLEEP/WAIT/readers/TI$)
- [ ] disk.bas         (DOPEN/RENAME/COPY/SCRATCH/DS$/BSAVE/BLOAD)
- [x] concat.bas       (CONCAT -- interpreter verified 2026-07-06)
- [ ] cursor.bas       (CURSOR positioning + RCURSOR; compiled run
      verified 2026-07-06, interpreted run pending. Note: CURSOR
      ON/OFF/style unsupported compiled -- positioning only.)
- [ ] sprite.bas       (register round-trips)
- [ ] mandel.bas, sieve.bas, ahl.bas
      (same output; note interpreted vs compiled SECONDS for the table;
      Ahl ACCURACY should be close, RANDOM differs by design)

## Parity with known caveats

- [ ] motion.bas -- relative/TO/angle forms; TO arrival now calibrated
      to ROM speed. Caveat: the ROM leaks running motion across RUNs,
      so interpreted results are only clean on the FIRST run after
      loading. (Compiled halts motion at exit -- deliberate.)
- [x] sound.bas, play.bas, play2.bas, filter.bas -- run to completion
      both ways; audio comparison by ear. FILTER timbre verified by ear
      2026-07-06 (cutoff scaling + PLAY/FILTER mode-bit fixes). Caveat:
      FOR-loop delays pace faster compiled, so sweeps run a bit quicker.
- [ ] sprdemo.bas -- visual: sprite sweep, healthy READY after.
- [ ] usr.bas -- runs interpreted but "USR OK" only prints compiled
      (register vs FAC calling convention, documented divergence).

## Interactive (manual input needed, no strict pass text)

- [ ] ioarray.bas (INPUT), joydemo.bas (joystick), mouse.bas (mouse)
- [ ] input.bas (INPUT regression for the KERNAL zp-clobber crash;
      type the prompted values when running interactively. Unattended
      compiled runs pass because CHRIN consumes the prompt line.)

## Compiled-only (do not expect interpreted parity)

- coll.bas, colprobe.bas -- the ROM's COLLISION is unimplemented
  ("will be available in a future BASIC 65 update"); ours works.
- bad_data.bas -- negative compile fixture; interpreted it errors by
  design (OUT OF DATA).

## Known divergences to NOT report as bugs

- E-notation print threshold differs for small floats.
- Extended functions need no space before "(" compiled; ROM requires
  none (fixtures already comply).
- FRE(0)/FRE(-1) return 0 compiled. DLOAD/DSAVE/MKDIR/RECORD and
  ,D/,U arguments unsupported. MOUSE pos pair rejected by the ROM.

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
- [ ] bits.bas         (SETBIT/CLRBIT incl flat 28-bit form; compiled
      run verified 2026-07-07)
- [ ] sprsav.bas       (SPRSAV string/sprite round trip; compiled run
      verified 2026-07-07 and re-verified 2026-07-12 after the pointer
      bounds fix. The MEGA65 default sprite pointer table is screen+$7F8;
      stale/dangerous pointer bytes are bounded to the post-screen area.)
- [ ] boot.bas         (BOOT chain-load; booted stub paints BOOT OK
      into screen RAM and freezes by design -- no READY. Compiled run
      verified 2026-07-07.)
- [ ] bankrreg.bas     (BANK far peek/poke + RREG capture + VSYNC;
      compiled run verified 2026-07-07)
- [ ] dma.bas          (EDMA fill/copy/far + legacy DMA; compiled run
      verified 2026-07-07)
- [ ] fgoto.bas        (FGOTO/FGOSUB computed jumps; compiled run
      verified 2026-07-07)
- [ ] pidisk.bas       (pi constant + DISK command/status; compiled
      run verified 2026-07-07)
- [ ] key.bas          (KEY n,string table rewrite + CHR$ factor;
      compiled run verified 2026-07-07. Caveat: bare KEY/ON/OFF/
      LOAD/SAVE unsupported compiled.)
- [ ] window.bas       (WINDOW + T@& readback; compiled run verified
      2026-07-06, interpreted run pending. Caveat: compiled does no
      coordinate validation, ROM raises ILLEGAL QUANTITY.)
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

- [ ] gfxtest.bas      (GRAPHIC CLR/SCREEN/PEN/LINE incl. polyline/
      BOX/CIRCLE/ELLIPSE/PAINT/PALETTE/SCNCLR colour/PIXEL()/RPEN(),
      ends with SCREEN CLOSE + printed PIXEL/RPEN assertions (4/6/3);
      compiled run verified 2026-07-08 incl. an FCM bitmap decode.
      Caveats: 320x200x256 only; PAINT is mode-0 semantics; PALETTE
      redefinitions land in $D100 hardware registers.)
- [ ] gfxmin.bas       (GRAPHIC CLR + PEN only -- the cheap blob-load
      and DMA-swap dispatch regression check; compiled run verified
      2026-07-08)

- [ ] testline.bas     (the book's SCREEN example verbatim --
      SCREEN/PEN/LINE/GETKEY/CLOSE; INTERACTIVE (GETKEY). Also the
      compile-diagnostics reproducer: on a write-protected disk the
      compiler now echoes the DOS status, e.g. 26,WRITE PROTECT ON.)
- [ ] penrpen.bas      (PEN pens 0-2 + RPEN readback round trips,
      independence of the three slots; prints PEN OK; compiled run
      verified 2026-07-09.)
- [ ] gfxcopy.bas      (GCOPY/PASTE: the book's box example with a
      red centre, pasted and probed (2/1/0), plus an over-budget
      GCOPY asserting the buffer empties; prints GCOPY OK; compiled
      run verified 2026-07-09 incl. bitmap decode. Divergence: the
      ROM errors on over-budget, we silently empty the buffer.)
- [ ] rpt.bas          (RPT$: both book examples plus length,
      zero-count and empty-source cases; prints RPT OK; compiled run
      verified 2026-07-09.)
- [ ] rwindow.bas      (RWINDOW 0-3: screen cols/rows from $D031,
      window dims tracked through the WINDOW command; prints RWINDOW
      OK with a 16x6 window; compiled run verified 2026-07-09.
      Divergence: windows set by raw ESC sequences are not tracked.)
- [ ] gfxbox4.bas      (BOX 4-corner path form: filled diamond +
      parallelogram outline; PIXEL probes 3/5/0 + BOX4 OK; compiled
      run verified 2026-07-08 incl. bitmap decode. Note: path fill is
      min/max row spans -- convex quads exact, bow-tie fills may
      differ from the ROM.)
- [ ] gfxchar.bas      (CHAR text on the graphics screen: normal,
      2x2, 3x-tall scaling and the down direction; sgn-sum PIXEL row/
      column probes assert ink present (35/44/7 + CHAR OK); compiled
      run verified 2026-07-08 incl. bitmap decode, user-confirmed.)
- [ ] getkey.bas       (GETKEY string + numeric targets; INTERACTIVE
      -- blocks for keypresses, run by hand both ways. Compiled
      byte-diff verified 2026-07-08; on the harness skip list.)
- [ ] gfxarc.bas       (CIRCLE/ELLIPSE arcs: start/stop degrees with
      legs, legs-suppress flag, filled pie sector; PIXEL readbacks
      1/0/5/0 + ARC OK; compiled run verified 2026-07-08 incl. bitmap
      decode. Note: pie fill is a chord+fan render -- a few rim-edge
      pixels may differ from the ROM's fill.)
- [ ] gfx640.bas       (SCREEN 640,200,8: filled box/circle spanning
      the 256/512 x-boundaries, full-width line, PIXEL readbacks
      3/7/0/5 + 640 OK; compiled run verified 2026-07-08 incl. bitmap
      decode. Divergences: circles are NOT aspect-corrected in 640
      -- the book says they render as ellipses; graphics programs cap
      at $c000 because 80-col screen codes live there.)
- [ ] gfxdbl.bas       (SCREEN DEF/OPEN/SET double buffering across
      attic-backed screens 0-3 + SCREEN CLR; PIXEL readbacks assert
      draw-to-hidden, flip, canvas-preservation and clear (5/5/2/6 +
      DBL OK); compiled run verified 2026-07-08. Divergences: every
      screen is 320x200x256 FCM -- DEF flags are bookkeeping; depths
      1-8 render as the 256-colour superset; buffers live in attic,
      not banks 4/5.)
- [ ] rcolor.bas       (RCOLOR sources 0-3 with poked border/bg and
      CHR$(5) text colour; prints RCOLOR OK; compiled run verified
      2026-07-08)
- [ ] gcstorm.bas      (GC compaction integrity: ~41k string allocs
      through the heap with per-string readback, prints FAILS: 0 +
      GC STORM OK; compiled run verified 2026-07-08)
- [x] gfxclip.bas      (COMPILE-ONLY robustness check -- do not run
      interpreted, the ROM raises ILLEGAL QUANTITY on its deliberate
      out-of-range coordinates. Compiled: silently clips, PIXEL
      out-of-range reads 0, DS$ stays 00,OK. Verified 2026-07-08.)

## Added since the last sweep (2026-07-12) -- not yet checked

Full parity expected:
- [ ] deffn.bas        (DEF FN definitions + calls)
- [ ] log2.bas         (LOG2 against known values)
- [ ] lineinp.bas      (LINE INPUT# from disk; lineinkb.bas is the
      interactive keyboard variant)
- [ ] bsavep.bas       (BSAVE with P(expr) addresses)
- [ ] condcmp.bas      (string compares inside compound AND/OR
      conditions -- the qint/FAC-clobber regression fixture)
- [ ] flow.bas, loops.bas, get.bas, scrarr.bas, strarrgc.bas,
      attrs.bas, bitprobe.bas, bankpk.bas, temp.bas, primes.bas,
      bench.bas, bench2.bas
- [ ] big.bas, bigx.bas (overlay fixtures: interpreted runs print the
      same SUM/S totals; compiled builds segment into <name>.NN files)
- [ ] lcp.bas          (Little Computer People house; segmented
      compiled)

Graphics (renamed with the gfx prefix; the old plain names were the
same programs): gfxboxes, gfxcircles, gfxlines, gfxmandel, gfxsurf,
gfxsurface, gfxg640clr, gfxgraphic640 -- benchmarks/demos, compare
visually + timings. Also new:
- [ ] rgraphic.bas     (RGRAPHIC readback)
- [ ] cut.bas          (GCOPY/CUT clear-source semantics)
- [ ] viewport.bas     (VIEWPORT clipping)
- [ ] gfxclock.bas     (analog RTC clock; interactive, any key exits.
      KNOWN-ISSUES #2: compiled build crashes after a few seconds in
      graphics-idle -- do not chase as a parity bug)
- [ ] wallprobe.bas    (t@&/c@& wall-adjacency probe)

Compiled-verification fixtures (interpreted parity not the point):
- movtest2.bas (sprite glide vs SPRSAV/COLLISION/SOUND isolation
  phases; runs both ways but exists to probe the compiled runtime)
- pacman.bas (playable game, interactive, endless -- on the harness
  skip list; the fixture that surfaced the 2026-07-12 sprite fixes)

## Known divergences to NOT report as bugs

- E-notation print threshold differs for small floats.
- Extended functions need no space before "(" compiled; ROM requires
  none (fixtures already comply).
- FRE(0)/FRE(-1) return 0 compiled. DLOAD/DSAVE/MKDIR/RECORD and
  ,D/,U arguments unsupported. MOUSE pos pair rejected by the ROM.
- Out-of-range graphics coordinates: the ROM raises ILLEGAL QUANTITY;
  compiled programs silently clip (plot guard + wrapper high-byte
  rejects) and PIXEL reads 0 off-screen.

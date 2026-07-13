# Known Issues

Open defects, tracked with their investigation state. Documented
divergences from the interpreter (by design or ROM quirk) live in
[tokens.md](tokens.md) and docs/interpreted-sweep.md instead.
Resolved issues are removed from this file; their write-ups live in
the git history (this file's log and the fixing commits' messages).

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

- **Runtime sections are page-rounded by need:** current section ends
  are core `$56D5`, FIO `$5B41`, math `$5EEA`, sound/sprite/graphics
  `$7372`, and overlay `$7654`. Their generated program bases are
  `$5700`, `$5C00`, `$5F00`, `$7400`, and `$7700`, respectively. The
  tightest low-tier slack is math at 22 bytes; the heavy sound/graphics
  tier has 142 bytes before `$7400`; the overlay tier has 172 bytes
  before `$7700`.
- **Compiler resident bank:** valued compiler content ends at `$B30D`,
  leaving 3314 bytes (`$0CF2`) below the `$C000` DOS/editor guard.
  ASM text templates now live in the companion `+b65tpl` file and are
  loaded to bank 5 only when ASM export is enabled.
- **Graphics blob:** the banked graphics helper ends at `$BB00`, leaving
  1279 bytes (`$04FF`) below its `$C000` 16KB window guard.
- **Program window:** native program space starts at the selected
  runtime base above and runs to `$D000` for ordinary programs. Graphics
  programs that need the `$C000` screen-code area use the lower `$C000`
  cap. Program overlays are implemented for larger programs, with the
  current v1 restrictions documented in `docs/overlays.md`.

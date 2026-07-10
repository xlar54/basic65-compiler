#!/usr/bin/env python3
"""Derive binary code templates from the compiler's text templates.

Parses every emitted `out_*` text blob in src/basic65c.asm, assembles it with
64tass against target/runtime.lbl (so runtime entry addresses are baked into
the bytes), and writes:

  target/bin-templates.inc     64tass include with one record per template
  target/bin-templates.txt     human-readable report

Record format (consumed by the future binary backend):

  bt_<name>:
          .byte <kind>, <length>
          .byte <bytes...>          ; patch slots filled with $00

Patch slots always sit at the END of a record because open fragments only
ever end mid-operand. Kinds:

  0 code        complete instructions, copy verbatim
  1 patch_byte  last byte is an 8-bit operand supplied at the call site
  2 patch_word  last two bytes are a 16-bit address (little-endian)
  3 patch_lo    last byte is the low byte of a resolved label address
  4 patch_hi    last byte is the high byte of a resolved label address
  5 patch_rel8  last byte is a rel8 branch displacement to a resolved label

Text templates remain the single source of truth: never edit the generated
include by hand. Label-name fragments (forend/iftrue/...) and the tail
directive templates (header vectors, DATA table, string pool, GC roots,
FOR storage, comments) are engine special cases and are intentionally not
represented here; they are listed in the report for bookkeeping.
"""

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "src" / "basic65c.asm"
RUNTIME_LBL = REPO / "target" / "runtime.lbl"
OUT_INC = REPO / "src" / "gen" / "bin-templates.inc"
OUT_TXT = REPO / "target" / "bin-templates.txt"
GFX_INC = REPO / "src" / "gfx" / "gfxshared.inc"
TASS = REPO / "64tass.exe"

KIND_CODE, KIND_BYTE, KIND_WORD, KIND_LO, KIND_HI, KIND_REL8, KIND_NAME = range(7)
KIND_NAMES = ["code", "patch_byte", "patch_word", "patch_lo", "patch_hi",
              "patch_rel8", "name"]

# directive prefixes emitted byte-at-a-time; records defined by hand because
# they are not assemblable on their own (patch slots only, no code bytes)
SYNTHETIC = {
    "out_data_byte_prefix": (KIND_BYTE, b"\x00"),   # ".byte $" + hex
    "out_data_byte_sep": (KIND_BYTE, b"\x00"),      # ",$" + hex
    "out_data_word_prefix": (KIND_WORD, b"\x00\x00"),  # ".word " + label ref
    "out_for_word_storage": (KIND_CODE, b"\x00\x00"),  # ":  .byte 0,0"
    "out_word_hex_prefix": (KIND_WORD, b"\x00\x00"),   # ".word $" + hex word
}

# open fragments: completed with a dummy operand, patch slot at the end
OPEN_BYTE = {
    "out_lda_imm_hex", "out_adc_imm_hex", "out_cmp_imm_hex",
    "out_cmp_exprhi_imm", "out_cmp_exprlo_imm",
}
OPEN_WORD = {"out_jsr_abs", "out_sta_abs"}
OPEN_LABEL = {"out_jmp_label", "out_jsr_label", "out_lda_label", "out_sta_label"}
OPEN_LABEL_LO = {"out_lda_label_lo_imm"}
OPEN_LABEL_HI = {"out_lda_label_hi_imm"}
OPEN_BRANCH = {
    "out_bne_label", "out_beq_label", "out_bcc_label", "out_bcs_label",
    "out_bpl_label", "out_bmi_label", "out_array_check_start",
}

# label-name fragments: mapped as kind=name/len=0 so a size/emit pass can
# pass through them without disturbing the pending patch armed by the
# preceding instruction-prefix record
NAME_FRAGMENTS = {
    "out_forend_prefix", "out_forstep_prefix",
    "out_fortop_prefix", "out_forneg_prefix", "out_forinitneg_prefix",
    "out_forcont_prefix", "out_fordone_prefix", "out_dotop_prefix",
    "out_dodone_prefix", "out_iftrue_prefix", "out_ifskip_prefix",
    "out_ifend_prefix", "out_ifelse_prefix", "out_iftmp_prefix",
    "out_arrayok_prefix", "out_arraynonneg_prefix", "out_arrayhieq_prefix",
    "out_onnext_prefix", "out_ondone_prefix", "out_fnlab_prefix",
}
# handled by mode branches in their calling emitters, never sent to the
# binary path through out_zstr
SPECIALS = {
    "out_header_pre", "out_header_post", "out_rtlevel_pre",
    "out_rtpb_pre", "out_rtpb_post",
    "out_varheapend_def", "out_comment_load_addr",
    "out_plus_one_cr",
    "out_linetab_label", "out_word_pre", "out_lineref_sep",
    "out_gfxflag_pre",
}
# emitted text that vanishes in binary (comments, labels whose addresses are
# captured separately, and PC-side directives)
COMMENTS = {
    "out_rem", "out_data_comment", "out_dim_comment", "out_size_guard",
    "out_size_guard_gfx",
    "out_string_pool_header", "out_strroots_start", "out_data_table_start",
    "out_fltinit_label",
    "out_data_table_end", "out_for_storage_header",
    "out_start_line", "out_seg_here", "out_seg_log", "out_seg_log2",
    "out_seg_fill", "out_seg_fill2",
}


def parse_blobs(path):
    """Return {label: (text, open_tail)} for every out_* .text/.byte blob."""
    blobs = {}
    label = None
    parts = []
    terminated = True
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        m = re.match(r"^(out_[a-z0-9_]+):$", line)
        if m:
            label, parts, terminated = m.group(1), [], False
            continue
        if label is None:
            continue
        if re.match(r"^[.](if|else|fi|endif)", line):
            continue  # TEXT_EMITTER guards around blob bodies
        tm = re.match(r'^\.text\s+"(.*)"\s*$', line)
        if tm:
            parts.append(tm.group(1).replace('""', '"'))
            continue
        bm = re.match(r"^\.byte\s+(.+)$", line)
        if bm:
            done = False
            for v in (x.strip() for x in bm.group(1).split(",")):
                if v == "13":
                    parts.append("\n")
                elif v == "0":
                    done = True
                else:
                    parts.append(f"<<byte {v}>>")
            if done:
                text = "".join(parts)
                blobs[label] = (text, not text.endswith("\n"))
                label = None
            continue
        # any other line means this label was not a text blob (it was code)
        label = None
    return blobs


def assemble(source_text):
    """Assemble a snippet at $1000, return its bytes."""
    with tempfile.TemporaryDirectory() as td:
        src = Path(td) / "t.asm"
        out = Path(td) / "t.prg"
        src.write_text(source_text, encoding="ascii")
        r = subprocess.run(
            [str(TASS), "--cbm-prg", "--m45gs02", "-q", str(src), "-o", str(out)],
            capture_output=True, text=True,
        )
        if r.returncode != 0:
            raise RuntimeError(r.stderr.strip() or r.stdout.strip())
        return out.read_bytes()[2:]  # strip PRG load address


def build_record(name, text, kind):
    body = []
    for ln in text.split("\n"):
        if not ln.strip() or ln.strip().startswith(";"):
            continue
        body.append(ln)  # keep trailing spaces: open fragments end "jmp "
    if not body and kind == KIND_CODE:
        return kind, b""

    # complete an open tail
    patch_len = 0
    if kind == KIND_BYTE:
        body[-1] += "00" if body[-1].endswith("$") else "$00"
        patch_len = 1
    elif kind == KIND_WORD:
        # non-zero-page dummy so lda/sta assemble to the 3-byte absolute form
        body[-1] += "cdcd" if body[-1].endswith("$") else "$cdcd"
        patch_len = 2
    elif kind in (KIND_LO, KIND_HI):
        body[-1] += "dummyabs"
        patch_len = 1
    elif kind == KIND_REL8:
        body[-1] += "dummybr"
        patch_len = 1
    elif name in OPEN_LABEL:
        body[-1] += "dummyabs"
        kind = KIND_WORD
        patch_len = 2  # dummyabs is non-ZP so lda/sta stay absolute

    harness = [
        '        .cpu "45gs02"',
        '        .enc "none"',
        f'        .include "{RUNTIME_LBL.as_posix()}"',
        "dummyabs = $cdcd",
        "        * = $1000",
    ]
    harness += body
    if kind == KIND_REL8:
        harness.append("dummybr:")
    harness.append("")
    data = assemble("\n".join(harness))
    minimum = {KIND_BYTE: 2, KIND_WORD: 3, KIND_LO: 2, KIND_HI: 2, KIND_REL8: 2}
    if kind in minimum and len(data) < minimum[kind]:
        raise RuntimeError(
            f"assembled to {len(data)} bytes, expected at least {minimum[kind]}"
            " -- fragment completion likely mis-parsed")
    if patch_len:
        data = data[:-patch_len] + b"\x00" * patch_len
    return kind, data


def write_gfx_shared():
    """Expose the runtime addresses the banked GFX blob reads/writes."""
    text = RUNTIME_LBL.read_text(encoding="ascii", errors="replace")
    lines = ["; generated by tools/gen-bin-templates.py from runtime.lbl\n",
             "; runtime addresses the banked graphics blob shares -- do not edit\n"]
    for sym in ("dma_args", "gfx_pen", "gfxres"):
        m = re.search("^" + sym + r"\s*=\s*(\$[0-9a-fA-F]+)", text, re.M)
        if not m:
            sys.exit(f"{sym} missing from runtime.lbl (needed by src/gfx)")
        lines.append(f"{sym} = {m.group(1)}\n")
    GFX_INC.write_text("".join(lines), encoding="ascii", newline="\n")


def main():
    if not RUNTIME_LBL.exists():
        sys.exit(f"missing {RUNTIME_LBL}; assemble the runtime first (build.bat)")
    write_gfx_shared()
    blobs = parse_blobs(SRC)
    records = {}
    skipped = {"name_fragment": [], "special": [], "comment": []}
    errors = []

    for name, (text, is_open) in sorted(blobs.items()):
        if name in NAME_FRAGMENTS:
            records[name] = (KIND_NAME, b"")
            continue
        if name in SPECIALS:
            skipped["special"].append(name)
            continue
        if name in SYNTHETIC:
            records[name] = SYNTHETIC[name]
            continue
        if name in COMMENTS:
            records[name] = (KIND_CODE, b"")  # comments vanish in binary
            continue
        if name in OPEN_BYTE:
            kind = KIND_BYTE
        elif name in OPEN_WORD:
            kind = KIND_WORD
        elif name in OPEN_LABEL:
            kind = KIND_WORD
        elif name in OPEN_LABEL_LO:
            kind = KIND_LO
        elif name in OPEN_LABEL_HI:
            kind = KIND_HI
        elif name in OPEN_BRANCH:
            kind = KIND_REL8
        elif is_open:
            errors.append(f"{name}: open fragment not classified in manifest")
            continue
        else:
            kind = KIND_CODE
        try:
            records[name] = build_record(name, text, kind)
        except RuntimeError as e:
            errors.append(f"{name}: {e}")

    if errors:
        for e in errors:
            print("ERROR:", e, file=sys.stderr)
        sys.exit(1)

    OUT_INC.parent.mkdir(parents=True, exist_ok=True)
    with OUT_INC.open("w", encoding="ascii", newline="\n") as f:
        import re as _re
        _m = _re.search(r"^rtendcore\s*=\s*\$([0-9a-fA-F]+)",
                        RUNTIME_LBL.read_text(encoding="ascii", errors="replace"), _re.M)
        if not _m:
            sys.exit("rtendcore missing from runtime.lbl")
        f.write("; generated by tools/gen-bin-templates.py -- do not edit\n")
        f.write("RT_END_CORE = $%s\n" % _m.group(1))
        for _nm, _sym in (("RT_END_FIO", "rtendfio"), ("RT_END_MATH", "rtendmath"), ("RT_END_SOUND", "rtendsound")):
            _mm = _re.search("^" + _sym + r"\s*=\s*\$([0-9a-fA-F]+)",
                             RUNTIME_LBL.read_text(encoding="ascii", errors="replace"), _re.M)
            if not _mm:
                sys.exit(_sym + " missing from runtime.lbl")
            f.write("%s = $%s\n" % (_nm, _mm.group(1)))
        _m2 = _re.search(r"^rtendsound\s*=\s*\$([0-9a-fA-F]+)",
                         RUNTIME_LBL.read_text(encoding="ascii", errors="replace"), _re.M)
        if not _m2:
            sys.exit("rtendsound missing from runtime.lbl")
        _pb = (int(_m2.group(1), 16) + 0xff) & 0xff00
        f.write("RT_PROGBASE = $%04x\n\n" % _pb)
        _m3 = _re.search(r"^rtpbhi\s*=\s*\$([0-9a-fA-F]+)",
                         RUNTIME_LBL.read_text(encoding="ascii", errors="replace"), _re.M)
        if not _m3:
            sys.exit("rtpbhi missing from runtime.lbl")
        f.write("RT_PBHI = $%s\n" % _m3.group(1))
        f.write("; record: .byte kind, length, bytes... (patch slots are $00)\n")
        f.write("; kinds: 0 code, 1 patch_byte, 2 patch_word, 3 patch_lo,\n")
        f.write(";        4 patch_hi, 5 patch_rel8, 6 name fragment\n\n")
        for name, (kind, data) in records.items():
            f.write(f"bt_{name}:\n")
            f.write(f"        .byte {kind}, {len(data)}\n")
            if data:
                for i in range(0, len(data), 12):
                    chunk = ", ".join(f"${b:02x}" for b in data[i:i + 12])
                    f.write(f"        .byte {chunk}\n")
            f.write("\n")
        f.write("; text-template pointer -> binary record, 0-terminated\n")
        f.write("bt_map:\n")
        for name in records:
            f.write(f"        .word {name}, bt_{name}\n")
        f.write("        .word 0, 0\n")

    with OUT_TXT.open("w", encoding="ascii", newline="\n") as f:
        f.write("template records\n================\n")
        for name, (kind, data) in records.items():
            f.write(f"{name:<28} {KIND_NAMES[kind]:<11} {len(data):>3}  "
                    + " ".join(f"{b:02x}" for b in data) + "\n")
        for cat, names in skipped.items():
            f.write(f"\n{cat} (engine special cases)\n")
            for n in names:
                f.write(f"  {n}\n")

    total = sum(len(d) for _, d in records.values())
    print(f"{len(records)} records ({total} bytes), "
          f"{sum(len(v) for v in skipped.values())} engine specials -> {OUT_INC.name}")


if __name__ == "__main__":
    main()

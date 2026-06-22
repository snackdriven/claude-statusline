#!/usr/bin/env python3
"""check-readme.py — keep README.md honest about the producer inventory.

Two jobs, split by what can be mechanical vs what needs a human:

  --check  (default)  Every producer in buddy/producers/*.sh must have a row in
                      the README producers table, and every table row must map
                      to a real producer. Exit 1 on drift. This is the hard
                      guarantee: you can't add or remove a producer without the
                      doc following (this is the drift that bit us — pr/incoming/
                      sessions were missing). It does NOT touch the descriptions;
                      those are judgment and stay hand-written.

  --audit             The softer, judgment-needed signals that can't be auto-
                      fixed — they land in DOC-PROMOTION.md for a human to triage
                      (write the prose, or dismiss). Never blocks. Catches: a new
                      clickable region, an undocumented toggle/env var, a new
                      region-contract field, a producer whose code changed after
                      the README (description may be stale).

A producer with a `# gen:skip` line is exempt from --check (escape hatch for a
producer intentionally kept out of the table).
"""
import sys, re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent          # repo root
PROD = ROOT / "buddy" / "producers"
README = ROOT / "README.md"
QUEUE = ROOT / "DOC-PROMOTION.md"
ROW_RE = re.compile(r"^\|\s*`([\w.\-]+\.sh)`\s*\|(.*)$", re.M)


def producer_files():
    """name -> source text, for every *.sh in the producers dir."""
    return {f.name: f.read_text(errors="ignore") for f in sorted(PROD.glob("*.sh"))}


def table_rows():
    """name -> row text, parsed from the README producers table."""
    return {m.group(1): m.group(2) for m in ROW_RE.finditer(README.read_text())}


def cmd_check():
    files = producer_files()
    checkable = {n for n, t in files.items() if not re.search(r"^#\s*gen:skip", t, re.M)}
    documented = set(table_rows())
    missing = sorted(checkable - documented)       # producer exists, no row
    orphan = sorted(documented - set(files))       # row exists, no producer file
    if not missing and not orphan:
        print(f"✓ README producer table matches buddy/producers/ ({len(checkable)} producers)")
        return 0
    if missing:
        print("✗ producers MISSING a row in the README table:")
        for m in missing:
            print(f"      {m}")
        print("    → add a row to the Producers table, or mark the producer `# gen:skip`.")
    if orphan:
        print("✗ README rows with no matching producer file:")
        for o in orphan:
            print(f"      {o}")
        print("    → remove the row, or restore/rename the producer.")
    return 1


def cmd_audit():
    readme = README.read_text()
    files = producer_files()
    rows = table_rows()
    items = []  # (kind, message)

    # 1. clickable drift — producer sets `href` but the region isn't listed in the
    #    README "Clickable regions" section (that section is the canonical place).
    m = re.search(r"## Clickable regions.*?(?=\n## )", readme, re.S)
    clickable_doc = m.group(0) if m else ""
    for name, body in files.items():
        if not re.search(r"\bhref\b", body):
            continue
        idm = re.search(r'id:\s*"(\w+)"', body) or re.search(r'\bID="(\w+)"', body)
        rid = idm.group(1) if idm else name[:-3]
        if rid not in clickable_doc and name[:-3] not in clickable_doc:
            items.append(("clickable", f"`{name}` sets `href` but its region isn't in the README 'Clickable regions' section"))

    # 2. toggles / env knobs referenced in code but absent from the README
    code = ""
    for p in list(PROD.glob("*.sh")) + [ROOT / "buddy" / "render.sh", ROOT / "statusline.sh", ROOT / "buddy" / "assemble.py"]:
        try:
            code += p.read_text(errors="ignore") + "\n"
        except OSError:
            pass
    # A real toggle is read from the environment with a default — `${VAR:-...}`
    # in bash or environ.get/getenv in python. Plain `VAR=value` assignments are
    # internal vars, not knobs, so they're excluded. Scope to config prefixes.
    knobs = set(re.findall(r"\$\{([A-Z][A-Z0-9_]{3,}):-", code))
    knobs |= set(re.findall(r"(?:environ\.get|getenv)\(\"([A-Z][A-Z0-9_]{3,})\"", code))
    knobs = {k for k in knobs if any(k.startswith(p) for p in ("STATUSLINE", "CLAUDE_STATUSLINE", "QA_", "OP_", "OPERATOR"))}
    for k in sorted(knobs):
        if k not in readme:
            items.append(("toggle", f"env/toggle `{k}` is used in code but not documented in the README"))

    # 3. region-contract fields read by assemble.py but not in the README contract
    asm = (ROOT / "buddy" / "assemble.py").read_text()
    fields = set(re.findall(r"\.get\('(\w+)'", asm))
    for fld in sorted(fields):
        if fld != "text" and f"`{fld}`" not in readme:
            items.append(("contract", f"region field `{fld}` is read by assemble.py but not in the README region contract"))

    # 4. producer changed after the README was last touched — description may be stale
    try:
        rt = README.stat().st_mtime
        for p in sorted(PROD.glob("*.sh")):
            if p.stat().st_mtime > rt + 2:
                items.append(("drift", f"`{p.name}` was changed after README.md — re-check its description"))
    except OSError:
        pass

    if not items:
        print("✓ audit: no doc-promotion candidates")
        return 0

    label = {
        "contract": "Region-contract field not documented",
        "toggle": "Undocumented toggle / env var",
        "clickable": "Clickable-region drift",
        "drift": "Code changed after the README (description may be stale)",
    }
    print(f"⚠ audit: {len(items)} doc-promotion candidate(s) → DOC-PROMOTION.md")
    by = {}
    for kind, msg in items:
        by.setdefault(kind, []).append(msg)
    out = [
        "# DOC-PROMOTION — statusline doc-debt queue",
        "",
        "Auto-detected by `buddy/check-readme.py --audit`. Each item needs a HUMAN call:",
        "write the prose into the README (then the mechanical row keeps itself current via",
        "`--check`), or decide it doesn't belong and clear the line. The table inventory is",
        "enforced by `--check`; this file is the judgment residual it can't auto-write.",
        "",
    ]
    for kind in ("contract", "toggle", "clickable", "drift"):
        if kind in by:
            out.append(f"## {label[kind]}")
            for msg in by[kind]:
                print(f"      [{kind}] {msg}")
                out.append(f"- [ ] {msg}")
            out.append("")
    QUEUE.write_text("\n".join(out))
    return 0


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "--check"
    sys.exit(cmd_audit() if mode == "--audit" else cmd_check())

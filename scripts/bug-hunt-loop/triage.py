#!/usr/bin/env python3
"""Triage PACKAGE_ISSUES.md against the current code.

One-off cleanup AND callable on demand later as `python3 triage.py`.

What this does:
  1. Parse PACKAGE_ISSUES.md (mixed format: doc-audit and bug-hunt entries).
  2. Re-key entries from ISSUE-<timestamp>-<slug> to canonical ISSUE-<slug>,
     coalescing duplicates that the timestamp scheme produced across runs.
  3. Add `status:` (OPEN / CLOSED / ORPHANED), `last_verified:`, and
     `closed_at:` / `closed_reason:` fields to every entry.
  4. For every entry with a `failing test:`:
       - File exists: un-skip and run it.
           PASS -> CLOSED + closed_reason; delete the test file.
           FAIL -> OPEN  + last_verified; restore @Skip.
       - File missing: ORPHANED.
  5. Doc-audit-style entries (no failing test) become OPEN, no run.
  6. Write PACKAGE_ISSUES.md back in canonical format.

Flags:
  --dry-run  parse + report what would change, no edits.
  --verbose  print test output on failure.
"""

import argparse, datetime, os, pathlib, re, subprocess, sys


def parse_entries(text):
    """Return (header, [{'raw_id': ..., 'chunk': ...}, ...])."""
    m = re.search(r"^## ISSUE-", text, flags=re.M)
    if not m:
        return text, []
    header = text[: m.start()].rstrip() + "\n\n"
    body = text[m.start():]
    pat = re.compile(r"^## (ISSUE-[^\n]+)\n", flags=re.M)
    matches = list(pat.finditer(body))
    entries = []
    for i, mt in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(body)
        raw_id = mt.group(1).strip()
        chunk = body[mt.end():end].strip("\n")
        entries.append({"raw_id": raw_id, "chunk": chunk})
    return header, entries


def slug_from_raw_id(raw):
    """ISSUE-<slug> | ISSUE-<yyyymmdd>-<slug> | ISSUE-<yyyymmdd>-<hhmm>-<slug>."""
    s = raw[len("ISSUE-"):]
    parts = s.split("-")
    while parts and re.fullmatch(r"\d{4,}", parts[0]):
        parts = parts[1:]
    return "-".join(parts) or s


def field(chunk, name):
    m = re.search(rf"^- {re.escape(name)}:\s*(.+?)$", chunk, flags=re.M)
    if not m:
        return None
    val = m.group(1).strip()
    # Strip surrounding backticks. Loop because earlier triage versions could
    # double-wrap values; one pass per layer.
    while len(val) >= 2 and val.startswith("`") and val.endswith("`"):
        val = val[1:-1].strip()
    return val


def block_field(chunk, name):
    """For - <name>:\\n```\\n...\\n``` blocks."""
    m = re.search(rf"^- {re.escape(name)}:\s*\n", chunk, flags=re.M)
    if not m:
        return None
    rest = chunk[m.end():]
    code = re.search(r"```[a-z]*\n(.*?)```", rest, flags=re.S)
    return code.group(1).strip() if code else None


def package_for_test(test_path):
    m = re.match(r"packages/([^/]+)/test/", test_path)
    return m.group(1) if m else None


def has_skip_header(abs_path):
    src = abs_path.read_text()
    return any(line.startswith("@Skip(") for line in src.splitlines()[:5])


def strip_skip_header(abs_path):
    """Remove leading @Skip / library; / blank lines. Returns original text for restore."""
    src = abs_path.read_text()
    lines = src.splitlines()
    i = 0
    while i < min(len(lines), 5):
        s = lines[i].strip()
        if lines[i].startswith("@Skip(") or s == "library;" or s == "":
            i += 1
            continue
        break
    abs_path.write_text("\n".join(lines[i:]) + "\n")
    return src


def restore_text(abs_path, original):
    abs_path.write_text(original)


def run_test(repo_root, pkg, rel_test, timeout=240):
    """Returns (exit_code, output)."""
    rel_to_pkg = rel_test[len(f"packages/{pkg}/"):]
    try:
        proc = subprocess.run(
            ["flutter", "test", "--reporter=expanded", rel_to_pkg],
            cwd=str(repo_root / "packages" / pkg),
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return proc.returncode, proc.stdout + proc.stderr
    except subprocess.TimeoutExpired as e:
        return -1, (e.stdout or "") + (e.stderr or "") + "\n[TIMEOUT]"


def classify_test_output(rc, out):
    """'PASS' | 'FAIL' | 'SKIP' | 'ERROR'."""
    if rc == -1:
        return "ERROR"
    if re.search(r"All tests skipped|^00:\d+ \+0 ~\d+ -0:", out, flags=re.M):
        return "SKIP"
    if rc == 0:
        return "PASS"
    if re.search(r"loading .* \[E\]|Failed to load|Compilation failed|No such file", out):
        return "ERROR"
    return "FAIL"


def coalesce(entries):
    """Deduplicate by canonical slug. Earlier discovered wins."""
    by_slug = {}
    for e in entries:
        slug = slug_from_raw_id(e["raw_id"])
        rec = {
            "slug": slug,
            "discovered": field(e["chunk"], "discovered") or "unknown",
            "source": field(e["chunk"], "source file"),
            "test": field(e["chunk"], "failing test"),
            "doc_ref": field(e["chunk"], "doc reference"),
            "summary": field(e["chunk"], "summary") or "",
            "repro": field(e["chunk"], "repro"),
            "severity": field(e["chunk"], "severity") or "MEDIUM",
            "red": block_field(e["chunk"], "red excerpt"),
            "rediscovered": [],
            "raw_id": e["raw_id"],
            # Preserve existing status across triage runs. Without this, an
            # entry that was CLOSED + had its test deleted would re-OPEN as
            # "doc-audit entry (no failing test)" the next time triage ran.
            "prior_status": field(e["chunk"], "status"),
            "closed_at": field(e["chunk"], "closed_at"),
            "closed_reason": field(e["chunk"], "closed_reason"),
        }
        if slug not in by_slug:
            by_slug[slug] = rec
            continue
        canon = by_slug[slug]
        # Prefer fuller info from later entries.
        for k in ("test", "source", "red", "repro", "doc_ref"):
            if not canon[k] and rec[k]:
                canon[k] = rec[k]
        # Preserve terminal states (CLOSED, WONTFIX) across triage runs.
        # WONTFIX is sticky like CLOSED: a maintainer rejected the fix, so we
        # don't want triage to "rediscover" the bug and re-open it.
        if rec["prior_status"] in ("CLOSED", "WONTFIX"):
            canon["prior_status"] = rec["prior_status"]
            canon["closed_at"] = canon["closed_at"] or rec["closed_at"]
            canon["closed_reason"] = canon["closed_reason"] or rec["closed_reason"]
        canon["rediscovered"].append(rec["discovered"])
    return list(by_slug.values())


def verify(repo_root, rec, verbose):
    """Returns ('CLOSED' | 'OPEN' | 'ORPHANED', reason_str)."""
    test = rec["test"]
    if not test:
        return ("OPEN", "doc-audit entry (no failing test)")
    pkg = package_for_test(test)
    if not pkg:
        return ("OPEN", f"cannot derive package from {test}")
    abs_path = repo_root / test
    if not abs_path.exists():
        return ("ORPHANED", "test file missing")
    was_skipped = has_skip_header(abs_path)
    backup = strip_skip_header(abs_path) if was_skipped else abs_path.read_text()
    try:
        rc, out = run_test(repo_root, pkg, test)
        kind = classify_test_output(rc, out)
        if verbose and kind in ("FAIL", "ERROR"):
            print("    output tail:")
            for line in out.splitlines()[-15:]:
                print(f"      {line}")
        if kind == "PASS":
            abs_path.unlink()
            return ("CLOSED", "test now passes; bug resolved")
        if kind == "ERROR":
            restore_text(abs_path, backup)
            return ("OPEN", "test failed to load/compile; manual review needed")
        # FAIL or SKIP-after-strip (defensive)
        restore_text(abs_path, backup)
        return ("OPEN", "test still fails; bug confirmed open")
    except Exception as ex:  # noqa: BLE001
        restore_text(abs_path, backup)
        return ("OPEN", f"verification raised: {ex!r}")


def render_entry(rec, status, reason, last_verified, closed_at=None):
    lines = [f"## ISSUE-{rec['slug']}", ""]
    lines.append(f"- status: {status}")
    lines.append(f"- discovered: {rec['discovered']}")
    lines.append(f"- last_verified: {last_verified}")
    if status in ("CLOSED", "ORPHANED"):
        lines.append(f"- closed_at: {closed_at}")
        lines.append(f"- closed_reason: {reason}")
    if rec["source"]:
        lines.append(f"- source file: `{rec['source']}`")
    if rec["test"] and status not in ("CLOSED", "ORPHANED"):
        lines.append(f"- failing test: `{rec['test']}`")
    if rec["doc_ref"]:
        lines.append(f"- doc reference: `{rec['doc_ref']}`")
    if rec["summary"]:
        lines.append(f"- summary: {rec['summary']}")
    if rec["repro"]:
        lines.append(f"- repro: {rec['repro']}")
    if rec["severity"]:
        lines.append(f"- severity: {rec['severity']}")
    if rec["rediscovered"]:
        lines.append(f"- rediscovered: {', '.join(rec['rediscovered'])}")
    if rec["red"] and status not in ("CLOSED",):
        lines.append("- red excerpt:")
        lines.append("")
        lines.append("```")
        for ln in rec["red"].splitlines():
            lines.append(ln)
        lines.append("```")
    return "\n".join(lines) + "\n"


CANONICAL_HEADER = """# Package Issues (auto-tracked by loops)

Canonical issue ledger for both the doc-audit and bug-hunt loops. Each entry
is keyed by a stable slug (`ISSUE-<slug>`), not a timestamp, so rediscovering
a bug updates the existing entry instead of creating duplicates.

Statuses:

- `OPEN`     - bug is real and the failing test (if any) still fails today.
- `CLOSED`   - the failing test passes against current code; bug is resolved.
- `ORPHANED` - the failing test file no longer exists; the bug may have been
               fixed but cannot be auto-verified.

Run `bash scripts/bug-hunt-loop/triage.sh` to re-verify every entry against
current code; the orchestrator also re-verifies on each loop start.

"""


def slug_from_test_filename(test_path):
    """packages/<pkg>/test/bug_hunt/iter_NN_<slug>_test.dart -> kebab slug."""
    name = pathlib.Path(test_path).stem  # iter_NN_<slug>_test
    if not name.endswith("_test"):
        return None
    body = name[:-len("_test")]  # iter_NN_<slug>
    parts = body.split("_", 2)  # ['iter', 'NN', '<slug>']
    if len(parts) < 3 or parts[0] != "iter":
        return None
    raw = parts[2]  # <slug> in snake_or_kebab form
    return raw.replace("_", "-")


def find_orphan_tests(repo_root, known_test_paths):
    """bug_hunt/*_test.dart files that have no PACKAGE_ISSUES entry yet."""
    orphans = []
    for pkg_dir in (repo_root / "packages").iterdir():
        bh = pkg_dir / "test" / "bug_hunt"
        if not bh.is_dir():
            continue
        for f in sorted(bh.glob("*_test.dart")):
            rel = str(f.relative_to(repo_root))
            if rel in known_test_paths:
                continue
            orphans.append(rel)
    return orphans


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    repo_root = pathlib.Path(__file__).resolve().parents[2]
    issues_path = repo_root / "PACKAGE_ISSUES.md"
    if not issues_path.exists():
        print(f"no PACKAGE_ISSUES.md at {issues_path}; nothing to triage")
        return 0

    text = issues_path.read_text()
    _, entries = parse_entries(text)
    print(f"parsed {len(entries)} raw entries")
    coalesced = coalesce(entries)
    print(f"coalesced into {len(coalesced)} unique slugs")

    # Phase 0: find tests under bug_hunt/ that aren't referenced by any entry.
    # These are orphans from killed/crashed iters - the test exists but no
    # issue was filed. Synthesize lightweight records so they get verified.
    known_test_paths = {rec["test"] for rec in coalesced if rec["test"]}
    orphan_tests = find_orphan_tests(repo_root, known_test_paths)
    if orphan_tests:
        print(f"found {len(orphan_tests)} orphan test(s) with no PACKAGE_ISSUES entry")
        for rel in orphan_tests:
            slug = slug_from_test_filename(rel)
            if not slug:
                continue
            coalesced.append({
                "slug": slug,
                "discovered": "orphan (synthesized by triage)",
                "source": None,
                "test": rel,
                "doc_ref": None,
                "summary": f"orphan reproducer for {slug}; auto-filed by triage",
                "repro": None,
                "severity": "MEDIUM",
                "red": None,
                "rediscovered": [],
                "raw_id": f"ISSUE-{slug}",
            })

    today = datetime.date.today().isoformat()
    rendered = [CANONICAL_HEADER]
    counts = {"OPEN": 0, "CLOSED": 0, "ORPHANED": 0}

    for rec in sorted(coalesced, key=lambda r: r["slug"]):
        print(f"  {rec['slug']} ... ", end="", flush=True)
        if args.dry_run:
            print("[dry-run; not verified]")
            counts["OPEN"] += 1
            rendered.append(render_entry(rec, "OPEN", "dry-run", today))
            continue
        # Sticky terminal states (CLOSED, WONTFIX): once an entry reaches one
        # of these, don't re-open it. CLOSED entries usually have their test
        # deleted; WONTFIX entries are maintainer-rejected by design.
        prior = rec.get("prior_status")
        if prior in ("CLOSED", "WONTFIX"):
            counts[prior] = counts.get(prior, 0) + 1
            reason = rec.get("closed_reason") or f"previously {prior.lower()} by triage"
            closed_at = rec.get("closed_at") or today
            print(f"{prior} (sticky; {reason})")
            rendered.append(render_entry(rec, prior, reason, today, closed_at))
            continue
        status, reason = verify(repo_root, rec, args.verbose)
        counts[status] += 1
        print(f"{status} ({reason})")
        closed_at = today if status in ("CLOSED", "ORPHANED") else None
        rendered.append(render_entry(rec, status, reason, today, closed_at))
        # If the test is OPEN and not yet @Skip'd, wrap it now so the suite
        # stays green. (verify() already restored the test to its original
        # state; if it was @Skip'd, no-op. If not, add a fresh @Skip.)
        if status == "OPEN" and rec["test"]:
            abs_path = repo_root / rec["test"]
            if abs_path.exists() and not has_skip_header(abs_path):
                src = abs_path.read_text()
                skip_line = f"@Skip('ISSUE-{rec['slug']}: failing reproducer kept as evidence; see PACKAGE_ISSUES.md')"
                abs_path.write_text(f"{skip_line}\nlibrary;\n\n{src}")
                print(f"    + wrapped with @Skip")

    new_text = "\n".join(rendered)
    if args.dry_run:
        print("\n[dry-run] would write {} bytes".format(len(new_text)))
    else:
        issues_path.write_text(new_text)
        print(f"\nwrote {len(new_text)} bytes to {issues_path}")

    print()
    print("===================== SUMMARY =====================")
    for k in ("OPEN", "CLOSED", "ORPHANED"):
        print(f"  {k}: {counts[k]}")
    print()
    if counts["CLOSED"]:
        print(f"deleted {counts['CLOSED']} resolved test file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

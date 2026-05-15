#!/usr/bin/env bash
# bug-hunt-loop orchestrator
#
# Runs the hunter -> test-writer -> validator -> fixer -> reviewer pipeline
# against plugin_kit, plugin_kit_dialog, and flutter_plugin_kit, with strict
# TDD enforcement: RED captured before any production edit, test file frozen
# between RED and GREEN, lib diff non-empty, full test suite green at the end.
#
# Codex agents NEVER commit. The orchestrator never commits either. Working
# state lives under WORKDIR (default: scripts/bug-hunt-loop/runs/<timestamp>).
#
# On stuck fixes: lib/ is restored from snapshot, the failing test is wrapped
# with a library-level @Skip annotation pointing at a PACKAGE_ISSUES.md entry,
# and the loop continues. The reproducer stays committed as evidence.
#
# Usage:
#   scripts/bug-hunt-loop/orchestrator.sh              # full run, cap 15
#   scripts/bug-hunt-loop/orchestrator.sh --dry-run    # build prompts only
#   scripts/bug-hunt-loop/orchestrator.sh --max 30     # cap iterations
#   scripts/bug-hunt-loop/orchestrator.sh --resume <run-dir>
#
# Read the README in this directory for the full workflow rationale.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$REPO_ROOT/scripts/bug-hunt-loop"
PROMPTS_DIR="$SCRIPT_DIR/prompts"

MAX_ITERS=15
DRY_RUN=0
RESUME_DIR=""

HUNTER_MODEL="gpt-5.4"
TEST_WRITER_MODEL="gpt-5.3-codex"
VALIDATOR_MODEL="gpt-5.4"
FIXER_MODEL="gpt-5.3-codex"
REVIEWER_MODEL="gpt-5.3-codex"

STAGE_TIMEOUT_S=1500     # 25 min per codex stage
TEST_TIMEOUT_S=600       # 10 min for one test file
SUITE_TIMEOUT_S=1200     # 20 min for full test suite

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max)     MAX_ITERS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --resume)  RESUME_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# Working directory layout
# ---------------------------------------------------------------------------

if [[ -n "$RESUME_DIR" ]]; then
  WORKDIR="$(cd "$RESUME_DIR" 2>/dev/null && pwd -P)" || WORKDIR=""
  if [[ -z "$WORKDIR" || ! -d "$WORKDIR" ]]; then
    echo "resume dir not found: $RESUME_DIR" >&2; exit 2
  fi
  IS_RESUME=1
else
  WORKDIR="$SCRIPT_DIR/runs/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$WORKDIR/iters" "$WORKDIR/state" "$WORKDIR/snapshots"
  IS_RESUME=0
fi

STATE_DIR="$WORKDIR/state"
ITERS_DIR="$WORKDIR/iters"
SNAP_DIR="$WORKDIR/snapshots"
ITER_FILE="$STATE_DIR/iteration.txt"
LATEST_LINK="$SCRIPT_DIR/runs/latest"

# Stoplist is PERSISTENT across runs so lessons compound. Lives at the loop
# directory's state/ folder (not per-run) and is appended to but never reset.
PERSISTENT_STATE_DIR="$SCRIPT_DIR/state"
mkdir -p "$PERSISTENT_STATE_DIR"
STOPLIST_FILE="$PERSISTENT_STATE_DIR/permanent-stoplist.md"
if [[ ! -f "$STOPLIST_FILE" ]]; then
  cat >"$STOPLIST_FILE" <<'EOF'
# Permanent stoplist
#
# Append-only ledger across all bug-hunt-loop runs. Each iter's outcome
# (fixed/filed/dropped/no-red/etc.) goes here so the hunter never re-raises
# a slug we already processed. To "reopen" a slug, manually delete its line.
EOF
fi

# Iter-local stoplist mirror: per-run snapshot of new entries for the iter
# logs (kept in $WORKDIR so the dashboard can show per-run context).
RUN_STOPLIST="$STATE_DIR/stoplist.md"
[[ -f "$RUN_STOPLIST" ]] || {
  cat >"$RUN_STOPLIST" <<EOF
# This run's stoplist additions (full persistent log: $STOPLIST_FILE)
EOF
}
[[ -f "$ITER_FILE" ]] || echo 0 >"$ITER_FILE"

if (( IS_RESUME == 0 )); then
  ln -sfn "$WORKDIR" "$LATEST_LINK"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD=(timeout)
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD=(gtimeout)
else
  TIMEOUT_CMD=(perl -e 'use POSIX; alarm shift; exec @ARGV')
fi

with_timeout() {
  local secs="$1"; shift
  "${TIMEOUT_CMD[@]}" "$secs" "$@"
}

log() {
  printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$WORKDIR/orchestrator.log"
}

die() { log "FATAL: $*"; exit 1; }

# Append a stoplist entry to BOTH the persistent log (which the hunter reads
# across runs) and the per-run mirror (which the dashboard reads). Stoplist
# entries follow the format "- iter N <kind>: <slug> [(<extra>)]".
stoplist_add() {
  local line="$1"
  printf '%s\n' "$line" >>"$STOPLIST_FILE"
  printf '%s\n' "$line" >>"$RUN_STOPLIST"
}

render_prompt() {
  local template="$1" out="$2"
  shift 2
  cp "$template" "$out"
  while [[ $# -gt 0 ]]; do
    local key="$1" value="$2"; shift 2
    python3 - "$out" "$key" "$value" <<'PY'
import sys, pathlib
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(path)
content = p.read_text()
content = content.replace('{{' + key + '}}', value)
p.write_text(content)
PY
  done
}

run_codex() {
  # run_codex <prompt-path> <output-path> <model> <sandbox>
  local prompt="$1" outpath="$2" model="$3" sandbox="$4"
  if (( DRY_RUN )); then
    echo "[DRY RUN] codex exec -m $model -s $sandbox prompt=$prompt out=$outpath" >&2
    {
      echo "## STATUS"
      echo "DRY_RUN"
    } >"$outpath"
    return 0
  fi
  local stderr_log="${outpath}.stderr"
  with_timeout "$STAGE_TIMEOUT_S" codex exec \
    -C "$REPO_ROOT" \
    -m "$model" \
    -s "$sandbox" \
    -c 'shell_environment_policy.inherit="all"' \
    --color never \
    --skip-git-repo-check \
    -o "$outpath" \
    "$(cat "$prompt")" 2>"$stderr_log" >>"$WORKDIR/orchestrator.log"
  local rc=$?
  if (( rc != 0 )); then
    log "codex stage failed rc=$rc (see $stderr_log)"
  fi
  return $rc
}

# Parse simple "## KEY\n<value>" or "- key: value" fields from codex output.
parse_block_after() {
  # parse_block_after <file> <header-line>
  local file="$1" header="$2"
  awk -v h="$header" '
    $0 == h {found=1; next}
    found && /^## / {exit}
    found && NF {print; exit}
  ' "$file"
}

parse_dash_field() {
  # parse_dash_field <file> <field-name>
  local file="$1" field="$2"
  grep -m1 "^- ${field}:" "$file" 2>/dev/null \
    | sed -E "s/^- ${field}:[[:space:]]*//" \
    | sed -E 's/^"(.*)"$/\1/'
}

# Run `flutter test` for the package on a single file. We always use
# `flutter test` (even for the pure-Dart plugin_kit) because plugin_kit's
# pubspec uses `resolution: workspace` and pure `dart test` trips on
# transitive Flutter SDK requirements (e.g. state_garden). `flutter test`
# resolves workspace deps cleanly and dispatches to the underlying Dart test
# runner for non-widget tests.
#
# Captures stdout+stderr, exit code, and timestamp.
run_test_single_file() {
  # run_test_single_file <package> <test-file-relpath> <output-prefix>
  local pkg="$1" test_file="$2" prefix="$3"
  local pkg_dir="$REPO_ROOT/packages/$pkg"
  local rel_test="${test_file#packages/$pkg/}"

  if (( DRY_RUN )); then
    echo "[DRY RUN] (cd packages/$pkg && flutter test $rel_test)" >"${prefix}.out"
    echo "0" >"${prefix}.exit"
    date +%s >"${prefix}.ts"
    return 0
  fi

  date +%s >"${prefix}.ts"
  (
    cd "$pkg_dir" || exit 99
    with_timeout "$TEST_TIMEOUT_S" flutter test --reporter=expanded "$rel_test"
  ) >"${prefix}.out" 2>&1
  local rc=$?
  echo "$rc" >"${prefix}.exit"
  return $rc
}

# Run the full test suite for the package. Used for the GREEN gate.
run_test_full_suite() {
  # run_test_full_suite <package> <output-prefix>
  local pkg="$1" prefix="$2"
  local pkg_dir="$REPO_ROOT/packages/$pkg"

  if (( DRY_RUN )); then
    echo "[DRY RUN] (cd packages/$pkg && flutter test)" >"${prefix}.out"
    echo "0" >"${prefix}.exit"
    date +%s >"${prefix}.ts"
    return 0
  fi

  date +%s >"${prefix}.ts"
  (
    cd "$pkg_dir" || exit 99
    with_timeout "$SUITE_TIMEOUT_S" flutter test --reporter=expanded
  ) >"${prefix}.out" 2>&1
  local rc=$?
  echo "$rc" >"${prefix}.exit"
  return $rc
}

snapshot_package_lib() {
  # snapshot_package_lib <package> <target-dir>
  local pkg="$1" target="$2"
  mkdir -p "$target"
  cp -a "$REPO_ROOT/packages/$pkg/lib" "$target/lib"
}

restore_package_lib() {
  # restore_package_lib <package> <source-dir>
  local pkg="$1" source="$2"
  [[ -d "$source/lib" ]] || { log "restore_package_lib: missing source $source/lib"; return 1; }
  rm -rf "$REPO_ROOT/packages/$pkg/lib"
  cp -a "$source/lib" "$REPO_ROOT/packages/$pkg/lib"
}

assert_lib_diff_nonempty() {
  # Returns 0 if there is at least one differing file under lib.
  #
  # NOTE: do NOT use `diff -rq ... | grep -q .` here. With `set -o pipefail`,
  # `diff -rq` exits 1 when files differ (which is the case we WANT to
  # detect), pipefail propagates that 1 as the pipeline's exit, and the
  # caller's `if ! assert_lib_diff_nonempty` then thinks "no diff" even
  # though diffs were present. Pre-2026-05-15 this bug caused every codex
  # fixer that actually edited files to be misclassified as a no-op, with
  # the fix leaking into permanent state because the empty-diff branch
  # doesn't restore the snapshot.
  local pkg="$1" snap="$2"
  local out
  out=$(diff -rq "$snap/lib" "$REPO_ROOT/packages/$pkg/lib" 2>/dev/null)
  [[ -n "$out" ]]
}

write_lib_diff() {
  # write_lib_diff <package> <snap-dir> <out-file>
  local pkg="$1" snap="$2" out="$3"
  : >"$out"
  diff -ruN "$snap/lib" "$REPO_ROOT/packages/$pkg/lib" >>"$out" 2>/dev/null || true
}

# Detect whether the RED output indicates a real test-assertion failure (good)
# or a compilation / environment failure (bad - means the test is broken, not
# proving a bug).
classify_red_output() {
  # classify_red_output <output-file>
  local out="$1"
  # Pub-resolution / environment errors. These come out before any test
  # actually runs, so we can spot them up front and reject the iter.
  if grep -qE 'version solving failed|Because [^[:space:]]+ requires|Could not find a file named "pubspec.yaml"|Failed to build' "$out"; then
    echo "COMPILE_ERROR"; return
  fi
  # Compile/load errors (codex-written test has a syntax error or missing import).
  # `flutter test` reports these as "Failed to load ... [E]" within the test stream.
  if grep -qE 'Failed to load|Compilation failed|^Error: |cannot resolve' "$out"; then
    # These can ALSO show "+0 -1: Some tests failed" because the test runner
    # counts the load failure as a failed test. Distinguish by checking if the
    # failure was a load failure vs an assertion in user code: the former
    # contains "[E]" right after "loading".
    if grep -qE 'loading .* \[E\]' "$out"; then
      echo "COMPILE_ERROR"; return
    fi
  fi
  # Genuine test failure: package:test / flutter_test prints "+N -M:" counters
  # with M>=1 and a "Some tests failed" / "Tests failed" trailer.
  if grep -qE 'Some tests failed|Tests failed|^\+[0-9]+ -[1-9][0-9]* ' "$out"; then
    echo "ASSERTION_FAIL"; return
  fi
  echo "UNKNOWN"
}

# Detect a GREEN result: all tests pass.
classify_green_output() {
  # classify_green_output <output-file>
  local out="$1"
  if grep -qE '^All tests passed|^[0-9]+ tests? passed' "$out"; then
    echo "ALL_PASS"; return
  fi
  # dart test "+N -0" with no failures.
  if grep -qE '^\+[0-9]+:|All tests passed' "$out" && ! grep -qE 'Some tests failed|Tests failed|^\+[0-9]+ -[1-9]' "$out"; then
    echo "ALL_PASS"; return
  fi
  echo "FAILURES"
}

# Wrap the failing test file with a library-level @Skip annotation so the test
# stays committed as documentation but no longer fails the suite.
wrap_test_in_skip() {
  # wrap_test_in_skip <test-file-abs-path> <issue-id>
  local file="$1" issue_id="$2"
  python3 - "$file" "$issue_id" <<'PY'
import sys, pathlib
path, issue = sys.argv[1], sys.argv[2]
p = pathlib.Path(path)
src = p.read_text()
lines = src.splitlines()

# If a @Skip is already present, do nothing.
if any(line.strip().startswith('@Skip(') for line in lines[:10]):
    sys.exit(0)

# Insert @Skip + library; at the top (idempotent: only adds library; if absent).
skip_line = f"@Skip('{issue}: failing reproducer kept as evidence; see PACKAGE_ISSUES.md')"
needs_library = not any(line.strip().startswith('library') for line in lines[:5])
prefix = [skip_line]
if needs_library:
    prefix.append('library;')
    prefix.append('')

p.write_text('\n'.join(prefix) + '\n' + src)
PY
}

# Append or update an entry in PACKAGE_ISSUES.md. Stable key is the SLUG
# (not a timestamp). If an entry with the same slug exists, last_verified
# and discovered are updated in place and the rest of the entry is left
# alone. If it doesn't exist, a new entry is appended.
#
# The orchestrator never calls this for CLOSED entries; closing happens via
# triage. So this only ever writes status: OPEN.
append_package_issue() {
  # append_package_issue <slug> <iter> <source-file> <test-file> <bug-summary> <severity> <red-snippet-file>
  local slug="$1" iter="$2" src_file="$3" test_file="$4" summary="$5" severity="$6" red_snip="$7"
  local issues="$REPO_ROOT/PACKAGE_ISSUES.md"
  local today
  today=$(date +%Y-%m-%d)
  local red_tmp
  red_tmp=$(mktemp)
  if [[ -f "$red_snip" ]]; then
    head -20 "$red_snip" >"$red_tmp"
  fi

  python3 - "$issues" "$slug" "$iter" "$src_file" "$test_file" "$summary" "$severity" "$today" "$red_tmp" <<'PY'
import pathlib, re, sys
issues, slug, iter_n, src, test, summary, sev, today, red_tmp = sys.argv[1:10]
red = pathlib.Path(red_tmp).read_text().rstrip("\n") if pathlib.Path(red_tmp).exists() else ""
p = pathlib.Path(issues)
issue_id = f"ISSUE-{slug}"

header = """# Package Issues (auto-tracked by loops)

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

text = p.read_text() if p.exists() else header

# Make sure the canonical header is on top (idempotent).
if "Package Issues (auto-tracked by loops)" not in text.split("##", 1)[0]:
    body_start = text.find("## ISSUE-")
    body_start = body_start if body_start >= 0 else len(text)
    text = header + text[body_start:]

# Find existing entry by slug.
pat = re.compile(rf"^## {re.escape(issue_id)}\n(.*?)(?=^## ISSUE-|\Z)", flags=re.M | re.S)
m = pat.search(text)

new_lines = [f"## {issue_id}", ""]
new_lines.append("- status: OPEN")
new_lines.append(f"- discovered: iter {iter_n}")
new_lines.append(f"- last_verified: {today}")
if src:
    new_lines.append(f"- source file: `{src}`")
if test:
    new_lines.append(f"- failing test: `{test}`")
if summary:
    new_lines.append(f"- summary: {summary}")
if sev:
    new_lines.append(f"- severity: {sev}")
if red:
    new_lines.append("- red excerpt:")
    new_lines.append("")
    new_lines.append("```")
    for ln in red.splitlines():
        new_lines.append(ln)
    new_lines.append("```")
new_entry = "\n".join(new_lines) + "\n\n"

if m:
    # Update in place. Preserve rediscovered list if present.
    old = m.group(0)
    redisc_match = re.search(r"^- rediscovered:\s*(.+?)$", old, flags=re.M)
    if redisc_match:
        existing = [x.strip() for x in redisc_match.group(1).split(",") if x.strip()]
    else:
        existing = []
    # If a new "discovered: iter X" differs from the canonical, log it.
    canon_match = re.search(r"^- discovered:\s*(.+?)$", old, flags=re.M)
    canon_disc = canon_match.group(1).strip() if canon_match else ""
    new_disc = f"iter {iter_n}"
    if canon_disc and canon_disc != new_disc and new_disc not in existing:
        existing.append(new_disc)
    if existing:
        # Insert rediscovered line before red excerpt block if any.
        idx = len(new_lines)
        for i, ln in enumerate(new_lines):
            if ln == "- red excerpt:":
                idx = i
                break
        new_lines.insert(idx, f"- rediscovered: {', '.join(existing)}")
        new_entry = "\n".join(new_lines) + "\n\n"
    # Replace the old entry with the new one.
    text = text[:m.start()] + new_entry + text[m.end():]
else:
    if not text.endswith("\n"):
        text += "\n"
    text += new_entry

p.write_text(text)
PY
  rm -f "$red_tmp"
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

START_TS=$(date +%s)
log "bug-hunt-loop start; workdir=$WORKDIR; max_iters=$MAX_ITERS; dry_run=$DRY_RUN"

# ---- Step 0: triage existing PACKAGE_ISSUES -----------------------------
# Verify every existing OPEN @Skip'd test against current code. Tests that
# now pass get their issue CLOSED and the test deleted; failing ones bump
# their last_verified. Prevents stale false-positives from compounding.
if (( ! DRY_RUN )); then
  if [[ -x "$SCRIPT_DIR/triage.py" ]] || [[ -f "$SCRIPT_DIR/triage.py" ]]; then
    log "step 0: triage existing PACKAGE_ISSUES"
    python3 "$SCRIPT_DIR/triage.py" >>"$WORKDIR/orchestrator.log" 2>&1 || log "  triage failed (non-fatal); continuing"
  fi
fi

last_iteration=$(cat "$ITER_FILE")
clean_streak=0

# Compute the OPEN-issues block on demand. Re-read PACKAGE_ISSUES.md fresh
# each iter so closures and additions made by the loop itself propagate to
# subsequent iters' hunter prompts. Cheap (small file, single regex pass).
compute_open_issues_blob() {
  python3 - "$REPO_ROOT/PACKAGE_ISSUES.md" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
if not path.exists():
    sys.exit(0)
text = path.read_text()
entries = re.split(r'^## (ISSUE-[^\n]+)\n', text, flags=re.M)
# entries = [pre, id1, body1, id2, body2, ...]
out = []
for i in range(1, len(entries), 2):
    issue_id = entries[i]
    body = entries[i + 1] if i + 1 < len(entries) else ""
    status_m = re.search(r'^- status:\s*(\w+)', body, re.M)
    status = status_m.group(1) if status_m else "OPEN"
    # Surface OPEN bugs so the hunter knows to avoid them. Also surface
    # WONTFIX entries: those are maintainer-rejected by design and the
    # hunter must never re-raise them as "new" bugs.
    if status not in ("OPEN", "WONTFIX"):
        continue
    summary_m = re.search(r'^- summary:\s*(.+?)$', body, re.M)
    summary = summary_m.group(1) if summary_m else ""
    src_m = re.search(r'^- source file:\s*`([^`]+)`', body, re.M)
    src = src_m.group(1) if src_m else ""
    slug = issue_id[len("ISSUE-"):]
    tag = f" [{status}]" if status != "OPEN" else ""
    if src:
        out.append(f"- {slug}{tag} ({src}): {summary}")
    else:
        out.append(f"- {slug}{tag}: {summary}")
sys.stdout.write("\n".join(out))
PY
}

for ((i = last_iteration + 1; i <= MAX_ITERS; i++)); do
  ITER_PADDED=$(printf %02d "$i")
  ITER_DIR="$ITERS_DIR/iter-$ITER_PADDED"
  mkdir -p "$ITER_DIR"
  log "==== iteration $i ===="
  echo "$i" >"$ITER_FILE"

  # ---- Stage 1: Hunter --------------------------------------------------
  log "iter $i: hunter"
  HUNT_PROMPT="$ITER_DIR/hunt.prompt.md"
  HUNT_OUT="$ITER_DIR/hunt.md"
  open_issues_blob=$(compute_open_issues_blob)
  [[ -z "$open_issues_blob" ]] && open_issues_blob="(none)"
  render_prompt "$PROMPTS_DIR/hunter.md" "$HUNT_PROMPT" \
    ITERATION "$i" \
    STOPLIST "$(cat "$STOPLIST_FILE")" \
    OPEN_ISSUES "$open_issues_blob"
  if ! run_codex "$HUNT_PROMPT" "$HUNT_OUT" "$HUNTER_MODEL" "read-only"; then
    log "iter $i: hunter failed; ending loop"
    break
  fi

  status=$(grep -m1 -E '^(HYPOTHESIS_FOUND|CLEAN|DRY_RUN)$' "$HUNT_OUT" || echo "UNKNOWN")
  if [[ "$status" == "CLEAN" ]]; then
    clean_streak=$((clean_streak + 1))
    log "iter $i: hunter reports clean (streak=$clean_streak)"
    if (( clean_streak >= 2 )); then
      log "iter $i: two consecutive clean hunts; convergence"
      echo "CONVERGED: hunter clean for 2 consecutive iters at iter $i" >"$WORKDIR/CONVERGED"
      break
    fi
    continue
  fi
  if [[ "$status" != "HYPOTHESIS_FOUND" && "$status" != "DRY_RUN" ]]; then
    log "iter $i: hunter status=$status; skipping iter"
    continue
  fi
  clean_streak=0

  PACKAGE=$(parse_dash_field "$HUNT_OUT" "package")
  SLUG=$(parse_dash_field "$HUNT_OUT" "slug")
  SOURCE_FILE=$(parse_dash_field "$HUNT_OUT" "file")
  SEVERITY=$(parse_dash_field "$HUNT_OUT" "severity")
  BUG_SUMMARY=$(parse_dash_field "$HUNT_OUT" "bug")

  if [[ "$status" == "DRY_RUN" ]]; then
    PACKAGE="${PACKAGE:-plugin_kit}"
    SLUG="${SLUG:-dry-run-stub}"
    SOURCE_FILE="${SOURCE_FILE:-packages/plugin_kit/lib/src/dummy.dart}"
    SEVERITY="${SEVERITY:-LOW}"
    BUG_SUMMARY="${BUG_SUMMARY:-dry-run hypothesis}"
  fi

  if [[ -z "$PACKAGE" || -z "$SLUG" ]]; then
    log "iter $i: hunter output missing package or slug; skipping"
    continue
  fi
  log "iter $i: hypothesis package=$PACKAGE slug=$SLUG severity=$SEVERITY"

  # ---- Stages 2-3: Test-writer (RED) + Validator, with 1 REWRITE retry --
  # The validator may decide REWRITE when the bug is real but the test is
  # the wrong shape (mocks the SUT, asserts on the wrong observable, etc.).
  # In that case we discard the current test, feed the validator's guidance
  # back into a fresh test-writer pass, and try once more. Capped at 2 total
  # attempts to keep iter cost bounded.
  TW_MAX_ATTEMPTS=2
  TW_GUIDANCE=""
  TEST_FILE=""
  RED_PREFIX=""
  red_rc=""
  iter_outcome=""  # set to one of: confirmed | skip-infeasible | skip-dry-run | skip-no-test | skip-no-red | skip-dropped | abort-loop

  for (( tw_attempt = 1; tw_attempt <= TW_MAX_ATTEMPTS; tw_attempt++ )); do
    log "iter $i: test-writer (attempt $tw_attempt/$TW_MAX_ATTEMPTS)"
    TW_PROMPT="$ITER_DIR/test-writer-${tw_attempt}.prompt.md"
    TW_OUT="$ITER_DIR/test-writer-${tw_attempt}.md"
    # The non-suffixed copies are what the dashboard reads (it has no notion
    # of attempts). Latest attempt wins.
    render_prompt "$PROMPTS_DIR/test-writer.md" "$TW_PROMPT" \
      ITERATION "$i" \
      ITERATION_PADDED "$ITER_PADDED" \
      HYPOTHESIS "$(cat "$HUNT_OUT")" \
      REWRITE_GUIDANCE "$TW_GUIDANCE"
    if ! run_codex "$TW_PROMPT" "$TW_OUT" "$TEST_WRITER_MODEL" "workspace-write"; then
      iter_outcome="abort-loop"
      break
    fi
    cp -a "$TW_OUT" "$ITER_DIR/test-writer.md"

    tw_status=$(grep -m1 -E '^(TEST_WRITTEN|INFEASIBLE|DRY_RUN)$' "$TW_OUT" || echo "UNKNOWN")
    if [[ "$tw_status" == "INFEASIBLE" ]]; then
      log "iter $i: test-writer marked INFEASIBLE; skipping iter"
      stoplist_add "- iter $i INFEASIBLE: $SLUG"
      iter_outcome="skip-infeasible"; break
    fi
    if [[ "$tw_status" == "DRY_RUN" ]]; then
      log "iter $i: dry-run; skipping rest of stages"
      iter_outcome="skip-dry-run"; break
    fi

    TEST_FILE=$(parse_block_after "$TW_OUT" "## TEST_FILE")
    TW_PACKAGE=$(parse_block_after "$TW_OUT" "## PACKAGE")
    if [[ -z "$TEST_FILE" || ! -f "$REPO_ROOT/$TEST_FILE" ]]; then
      log "iter $i: test-writer did not produce a readable test file (got '$TEST_FILE'); skipping"
      iter_outcome="skip-no-test"; break
    fi
    if [[ -n "$TW_PACKAGE" && "$TW_PACKAGE" != "$PACKAGE" ]]; then
      log "iter $i: WARNING test-writer package ($TW_PACKAGE) != hunter package ($PACKAGE); using $TW_PACKAGE"
      PACKAGE="$TW_PACKAGE"
    fi
    log "iter $i: test file -> $TEST_FILE (pkg=$PACKAGE)"

    # Snapshot the test file. Extension `.dart.snap` so the Dart analyzer
    # ignores it (it would otherwise pollute workspace analysis with
    # "imported package isn't a dependency" warnings).
    TEST_SNAP="$ITER_DIR/test-file.red.dart.snap"
    cp -a "$REPO_ROOT/$TEST_FILE" "$TEST_SNAP"

    log "iter $i: running RED test (attempt $tw_attempt)"
    RED_PREFIX="$ITER_DIR/red-${tw_attempt}"
    run_test_single_file "$PACKAGE" "$TEST_FILE" "$RED_PREFIX"
    cp -a "${RED_PREFIX}.out" "$ITER_DIR/red.out"
    cp -a "${RED_PREFIX}.exit" "$ITER_DIR/red.exit"
    cp -a "${RED_PREFIX}.ts" "$ITER_DIR/red.ts"
    red_rc=$(cat "${RED_PREFIX}.exit")
    red_kind=$(classify_red_output "${RED_PREFIX}.out")
    log "iter $i: RED exit=$red_rc kind=$red_kind"

    if (( red_rc == 0 )) || [[ "$red_kind" != "ASSERTION_FAIL" ]]; then
      log "iter $i: test did NOT fail as required (rc=$red_rc kind=$red_kind); deleting test, skipping iter"
      rm -f "$REPO_ROOT/$TEST_FILE"
      stoplist_add "- iter $i no-red: $SLUG ($red_kind)"
      iter_outcome="skip-no-red"; break
    fi

    log "iter $i: validator (attempt $tw_attempt)"
    VAL_PROMPT="$ITER_DIR/validate-${tw_attempt}.prompt.md"
    VAL_OUT="$ITER_DIR/validated-${tw_attempt}.md"
    render_prompt "$PROMPTS_DIR/validator.md" "$VAL_PROMPT" \
      ITERATION "$i" \
      TEST_FILE_PATH "$TEST_FILE" \
      TEST_FILE_CONTENTS "$(cat "$REPO_ROOT/$TEST_FILE")" \
      RED_OUTPUT "$(tail -200 "${RED_PREFIX}.out")" \
      RED_EXIT_CODE "$red_rc"
    if ! run_codex "$VAL_PROMPT" "$VAL_OUT" "$VALIDATOR_MODEL" "read-only"; then
      log "iter $i: validator failed; rolling back test and ending iter"
      rm -f "$REPO_ROOT/$TEST_FILE"
      iter_outcome="skip-dropped"; break
    fi
    cp -a "$VAL_OUT" "$ITER_DIR/validated.md"

    val_decision=$(parse_block_after "$VAL_OUT" "## DECISION")
    log "iter $i: validator decision=$val_decision (attempt $tw_attempt)"

    if [[ "$val_decision" == "CONFIRMED" ]]; then
      iter_outcome="confirmed"; break
    fi

    if [[ "$val_decision" == "REWRITE" && $tw_attempt -lt $TW_MAX_ATTEMPTS ]]; then
      TW_GUIDANCE=$(parse_dash_field "$VAL_OUT" "guidance")
      if [[ -z "$TW_GUIDANCE" ]]; then
        TW_GUIDANCE="(validator did not provide guidance; rewrite the test to use real SUT instances and assert on observable behavior, not implementation)"
      fi
      log "iter $i: validator requested REWRITE; discarding test and retrying with guidance"
      rm -f "$REPO_ROOT/$TEST_FILE"
      continue
    fi

    # DROPPED, or REWRITE-but-out-of-attempts. Stoplist and move on.
    log "iter $i: validator $val_decision (final); removing test, stoplisting"
    rm -f "$REPO_ROOT/$TEST_FILE"
    stoplist_add "- iter $i dropped: $SLUG"
    iter_outcome="skip-dropped"; break
  done

  case "$iter_outcome" in
    abort-loop)
      log "iter $i: test-writer/validator stage aborted; ending loop"
      break ;;
    skip-infeasible|skip-dry-run|skip-no-test|skip-no-red|skip-dropped)
      continue ;;
    confirmed)
      : ;;  # fall through to fixer
    *)
      log "iter $i: unexpected outcome '$iter_outcome'; skipping"
      continue ;;
  esac

  # ---- Pre-fix snapshot of the package lib ------------------------------
  LIB_SNAP="$SNAP_DIR/iter-$ITER_PADDED"
  log "iter $i: snapshot $PACKAGE/lib -> $LIB_SNAP"
  snapshot_package_lib "$PACKAGE" "$LIB_SNAP"

  # ---- Stage 4: Fixer (GREEN) -------------------------------------------
  log "iter $i: fixer"
  FIX_PROMPT="$ITER_DIR/fix.prompt.md"
  FIX_OUT="$ITER_DIR/fix-report.md"
  render_prompt "$PROMPTS_DIR/fixer.md" "$FIX_PROMPT" \
    ITERATION "$i" \
    HYPOTHESIS "$(cat "$HUNT_OUT")" \
    TEST_FILE_PATH "$TEST_FILE" \
    TEST_FILE_CONTENTS "$(cat "$REPO_ROOT/$TEST_FILE")" \
    RED_OUTPUT "$(tail -100 "${RED_PREFIX}.out")" \
    PACKAGE "$PACKAGE"
  fixer_rc=0
  if ! run_codex "$FIX_PROMPT" "$FIX_OUT" "$FIXER_MODEL" "workspace-write"; then
    fixer_rc=$?
    log "iter $i: fixer codex failed rc=$fixer_rc; treating as FIX_TOO_LARGE"
  fi

  fix_status=$(grep -m1 -E '^(FIX_APPLIED|FIX_TOO_LARGE|DRY_RUN)$' "$FIX_OUT" || echo "UNKNOWN")
  log "iter $i: fixer status=$fix_status"

  # ---- TDD gate 1: test file must be byte-unchanged ---------------------
  if ! cmp -s "$TEST_SNAP" "$REPO_ROOT/$TEST_FILE"; then
    log "iter $i: TDD VIOLATION fixer modified the test file; rolling back"
    cp -a "$TEST_SNAP" "$REPO_ROOT/$TEST_FILE"
    restore_package_lib "$PACKAGE" "$LIB_SNAP"
    stoplist_add "- iter $i tdd-violation: $SLUG (test edited)"
    continue
  fi

  if [[ "$fix_status" == "FIX_TOO_LARGE" || "$fix_status" == "UNKNOWN" ]]; then
    log "iter $i: fixer declined; filing PACKAGE_ISSUE and keeping test as @Skip"
    restore_package_lib "$PACKAGE" "$LIB_SNAP"
    ISSUE_ID="ISSUE-$SLUG"
    wrap_test_in_skip "$REPO_ROOT/$TEST_FILE" "$ISSUE_ID"
    append_package_issue "$SLUG" "$i" "$SOURCE_FILE" "$TEST_FILE" "$BUG_SUMMARY" "$SEVERITY" "${RED_PREFIX}.out"
    stoplist_add "- iter $i filed: $SLUG ($ISSUE_ID)"
    continue
  fi

  # ---- TDD gate 2: lib diff must be non-empty ---------------------------
  if ! assert_lib_diff_nonempty "$PACKAGE" "$LIB_SNAP"; then
    log "iter $i: fixer made no production-code changes; rolling back, treating as FIX_TOO_LARGE"
    # Defensive restore: if the diff genuinely is empty this is a no-op, but
    # if assert_lib_diff_nonempty ever misclassifies (or codex applied edits
    # in some delayed way), this guarantees the snapshot wins.
    restore_package_lib "$PACKAGE" "$LIB_SNAP"
    ISSUE_ID="ISSUE-$SLUG"
    wrap_test_in_skip "$REPO_ROOT/$TEST_FILE" "$ISSUE_ID"
    append_package_issue "$SLUG" "$i" "$SOURCE_FILE" "$TEST_FILE" "$BUG_SUMMARY" "$SEVERITY" "${RED_PREFIX}.out"
    stoplist_add "- iter $i empty-diff: $SLUG ($ISSUE_ID)"
    continue
  fi

  # ---- Run the full test suite for GREEN gate ---------------------------
  log "iter $i: running GREEN (full $PACKAGE suite)"
  GREEN_PREFIX="$ITER_DIR/green"
  run_test_full_suite "$PACKAGE" "$GREEN_PREFIX"
  green_rc=$(cat "${GREEN_PREFIX}.exit")
  log "iter $i: GREEN exit=$green_rc"

  if (( green_rc != 0 )); then
    log "iter $i: GREEN failed; rolling back, filing PACKAGE_ISSUE"
    restore_package_lib "$PACKAGE" "$LIB_SNAP"
    ISSUE_ID="ISSUE-$SLUG"
    wrap_test_in_skip "$REPO_ROOT/$TEST_FILE" "$ISSUE_ID"
    append_package_issue "$SLUG" "$i" "$SOURCE_FILE" "$TEST_FILE" "$BUG_SUMMARY" "$SEVERITY" "${GREEN_PREFIX}.out"
    stoplist_add "- iter $i green-failed: $SLUG ($ISSUE_ID)"
    continue
  fi

  # Save the production-code diff for the reviewer.
  DIFF_FILE="$ITER_DIR/lib.diff"
  write_lib_diff "$PACKAGE" "$LIB_SNAP" "$DIFF_FILE"

  # ---- Stage 5: Reviewer -----------------------------------------------
  log "iter $i: reviewer"
  REV_PROMPT="$ITER_DIR/review.prompt.md"
  REV_OUT="$ITER_DIR/review.md"
  render_prompt "$PROMPTS_DIR/reviewer.md" "$REV_PROMPT" \
    ITERATION "$i" \
    PACKAGE "$PACKAGE" \
    TEST_FILE_PATH "$TEST_FILE" \
    DIFF_PATH "$DIFF_FILE" \
    FIX_REPORT "$(cat "$FIX_OUT")" \
    RED_OUTPUT "$(tail -60 "${RED_PREFIX}.out")" \
    GREEN_OUTPUT "$(tail -60 "${GREEN_PREFIX}.out")"
  if ! run_codex "$REV_PROMPT" "$REV_OUT" "$REVIEWER_MODEL" "read-only"; then
    log "iter $i: reviewer codex failed; rolling back"
    restore_package_lib "$PACKAGE" "$LIB_SNAP"
    ISSUE_ID="ISSUE-$SLUG"
    wrap_test_in_skip "$REPO_ROOT/$TEST_FILE" "$ISSUE_ID"
    append_package_issue "$SLUG" "$i" "$SOURCE_FILE" "$TEST_FILE" "$BUG_SUMMARY" "$SEVERITY" "${RED_PREFIX}.out"
    stoplist_add "- iter $i reviewer-error: $SLUG ($ISSUE_ID)"
    continue
  fi

  rev_decision=$(parse_block_after "$REV_OUT" "## DECISION")
  log "iter $i: reviewer decision=$rev_decision"

  if [[ "$rev_decision" != "PASS" ]]; then
    log "iter $i: reviewer FAILED; rolling back, filing PACKAGE_ISSUE"
    restore_package_lib "$PACKAGE" "$LIB_SNAP"
    ISSUE_ID="ISSUE-$SLUG"
    wrap_test_in_skip "$REPO_ROOT/$TEST_FILE" "$ISSUE_ID"
    append_package_issue "$SLUG" "$i" "$SOURCE_FILE" "$TEST_FILE" "$BUG_SUMMARY" "$SEVERITY" "${RED_PREFIX}.out"
    stoplist_add "- iter $i review-failed: $SLUG ($ISSUE_ID)"
    continue
  fi

  # ---- Success path -----------------------------------------------------
  log "iter $i: SUCCESS - test+fix kept; stoplisting slug"
  stoplist_add "- iter $i fixed: $SLUG"

  # Drop old snapshots; we keep just the most recent for debugging.
  ls -1 "$SNAP_DIR" | sort | head -n -1 | while IFS= read -r old; do
    [[ -z "$old" ]] && continue
    rm -rf "$SNAP_DIR/$old"
  done
done

END_TS=$(date +%s)
elapsed=$((END_TS - START_TS))
log "bug-hunt-loop end; elapsed=${elapsed}s; workdir=$WORKDIR"

if [[ -f "$WORKDIR/CONVERGED" ]]; then
  cat "$WORKDIR/CONVERGED"
else
  echo "loop ended without explicit convergence; iteration cap or stage failure" \
    | tee -a "$WORKDIR/orchestrator.log"
fi

echo
echo "artifacts:"
echo "  log:            $WORKDIR/orchestrator.log"
echo "  iters:          $WORKDIR/iters/"
echo "  state:          $WORKDIR/state/"
echo "  package issues: $REPO_ROOT/PACKAGE_ISSUES.md"
echo "  bug-hunt tests: packages/*/test/bug_hunt/"

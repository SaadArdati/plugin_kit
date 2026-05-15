#!/usr/bin/env bash
# Catch-up: assess every bug_hunt test currently in the working tree.
#
# The bug-hunt orchestrator had a `pipefail`-induced bug where its diff
# check returned "no diff" even when codex's fixer DID edit lib files. The
# orchestrator routed those iters down the empty-diff path, which did NOT
# roll back. So leaked codex edits accumulated in lib/, and every downstream
# iter snapshotted from a polluted base.
#
# Each test is treated as a CLAIM ("the leaked fix for this bug works")
# and verified by running it against current lib. Output categorizes:
#
#   PASS  - test passes today; the fix in lib actually works. Keep both.
#   FAIL  - test fails today; the leaked fix is broken or absent. Test stays
#           as evidence; user decides between @Skip or git checkout HEAD on
#           the affected lib file.
#   ERROR - test could not be loaded (compile error / stale API import).
#           Usually a leftover from a prior aborted run. Recommend delete.
#
# Usage:
#   bash scripts/bug-hunt-loop/catch-up.sh           # run + report
#   bash scripts/bug-hunt-loop/catch-up.sh --verbose # also dump first 25
#                                                     lines of failing output

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERBOSE=0
[[ "${1:-}" == "--verbose" ]] && VERBOSE=1

if command -v timeout >/dev/null 2>&1; then
  TO=(timeout)
elif command -v gtimeout >/dev/null 2>&1; then
  TO=(gtimeout)
else
  TO=(perl -e 'use POSIX; alarm shift; exec @ARGV')
fi

# bash 3.2 friendly: use a tempdir and per-test files instead of associative
# arrays. summary.tsv holds one line per test: STATUS<TAB>PKG<TAB>REL
TMPDIR_RUN=$(mktemp -d)
SUMMARY="$TMPDIR_RUN/summary.tsv"
FAIL_OUT_DIR="$TMPDIR_RUN/fail-out"
mkdir -p "$FAIL_OUT_DIR"
: >"$SUMMARY"

cleanup() { rm -rf "$TMPDIR_RUN"; }
trap cleanup EXIT

run_test() {
  local pkg="$1" rel="$2"
  local out_path="$FAIL_OUT_DIR/${pkg}__${rel//\//_}.out"
  local rel_to_pkg="${rel#packages/$pkg/}"
  if ! ( cd "$REPO_ROOT/packages/$pkg" && "${TO[@]}" 240 flutter test --reporter=expanded "$rel_to_pkg" ) >"$out_path" 2>&1; then
    if grep -qE 'loading .* \[E\]|Failed to load|Compilation failed|No such file' "$out_path"; then
      printf 'ERROR\t%s\t%s\n' "$pkg" "$rel" >>"$SUMMARY"
      echo "ERROR"
      return
    fi
    printf 'FAIL\t%s\t%s\n' "$pkg" "$rel" >>"$SUMMARY"
    echo "FAIL"
    return
  fi
  # `flutter test` exits 0 for both PASS and SKIP. Distinguish them: a real
  # pass has at least one "+N:" line with N>=1; a skip has "+0 ~M -0".
  if grep -qE 'All tests skipped|^00:[0-9]+ \+0 ~[0-9]+:|^00:[0-9]+ \+0 ~[0-9]+ -0:' "$out_path"; then
    printf 'SKIP\t%s\t%s\n' "$pkg" "$rel" >>"$SUMMARY"
    rm -f "$out_path"
    echo "SKIP"
    return
  fi
  printf 'PASS\t%s\t%s\n' "$pkg" "$rel" >>"$SUMMARY"
  rm -f "$out_path"  # only keep failing/error outputs for verbose mode
  echo "PASS"
}

echo "scanning bug_hunt tests under packages/*/test/bug_hunt/..."
echo

found_any=0
for pkg in plugin_kit plugin_kit_dialog flutter_plugin_kit; do
  dir="$REPO_ROOT/packages/$pkg/test/bug_hunt"
  [[ -d "$dir" ]] || continue
  for f in "$dir"/*_test.dart; do
    [[ -f "$f" ]] || continue
    found_any=1
    rel="${f#$REPO_ROOT/}"
    printf '  %s ... ' "$rel"
    run_test "$pkg" "$rel"
  done
done

if (( ! found_any )); then
  echo "(no bug_hunt tests found; nothing to assess)"
  exit 0
fi

echo
echo "===================== SUMMARY ====================="
n_pass=$(awk -F'\t' '$1=="PASS"' "$SUMMARY" | wc -l | tr -d ' ')
n_fail=$(awk -F'\t' '$1=="FAIL"' "$SUMMARY" | wc -l | tr -d ' ')
n_err=$(awk -F'\t'  '$1=="ERROR"' "$SUMMARY" | wc -l | tr -d ' ')
n_skip=$(awk -F'\t' '$1=="SKIP"' "$SUMMARY" | wc -l | tr -d ' ')
printf 'PASS  : %s (leaked fix works; keep test + lib state)\n' "$n_pass"
printf 'FAIL  : %s (real bug, leaked fix did not solve it)\n' "$n_fail"
printf 'SKIP  : %s (test is @Skip annotated; un-skip and re-run to verify)\n' "$n_skip"
printf 'ERROR : %s (test wont load; stale leftover; recommend delete)\n' "$n_err"
echo

if (( n_pass > 0 )); then
  echo "--- PASS (keepers) ---"
  awk -F'\t' '$1=="PASS"{printf "  %s :: %s\n", $2, $3}' "$SUMMARY"
  echo
fi
if (( n_fail > 0 )); then
  echo "--- FAIL (real bugs, leaked fix did not solve them) ---"
  awk -F'\t' '$1=="FAIL"{printf "  %s :: %s\n", $2, $3}' "$SUMMARY"
  echo
fi
if (( n_skip > 0 )); then
  echo "--- SKIP (un-skip and re-run for honest result) ---"
  awk -F'\t' '$1=="SKIP"{printf "  %s :: %s\n", $2, $3}' "$SUMMARY"
  echo
fi
if (( n_err > 0 )); then
  echo "--- ERROR (stale; safe to delete) ---"
  awk -F'\t' '$1=="ERROR"{printf "  %s :: %s\n", $2, $3}' "$SUMMARY"
  echo
fi

if (( VERBOSE )); then
  echo "===================== VERBOSE OUTPUT ====================="
  for f in "$FAIL_OUT_DIR"/*.out; do
    [[ -f "$f" ]] || continue
    echo
    echo "--- $(basename "$f") ---"
    tail -25 "$f"
  done
fi

echo
echo "Suggested next moves:"
echo "  1. ERROR rows: rm packages/<pkg>/test/bug_hunt/<test>.dart"
echo "  2. FAIL rows: read each test, decide between"
echo "     (a) wrap with @Skip('PACKAGE_ISSUES.md ref') so suite stays green"
echo "     (b) git checkout HEAD -- the relevant lib file to revert a broken leak"
echo "  3. PASS rows: nothing to do; keep both test and current lib state."
echo
echo "After cleanup, run 'flutter test' on each affected package to confirm"
echo "the suite is green before the next bug-hunt restart."

#!/usr/bin/env bash
# coverage-loop orchestrator
#
# Builds regression armor by finding untested public-API behaviors and
# generating characterization tests that lock them in. The pipeline is:
#
#   hunter (read-only)
#     -> proposes one untested behavior with file:line evidence
#   test-writer (workspace-write)
#     -> writes a passing test under packages/{pkg}/test/coverage/
#   GREEN gate (orchestrator)
#     -> runs the test once; it must exit 0
#   validator (read-only)
#     -> sanity-checks test shape (no SUT mocks, real observable assertion)
#   MUTATION gate (orchestrator)
#     -> backs up source, replaces cited lines with `throw UnimplementedError()`,
#        re-runs test; test must NOT pass. Restores source either way.
#   reviewer (read-only)
#     -> final judgment: durable regression armor or brittle noise
#
# Codex agents NEVER commit. The orchestrator never commits either.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$REPO_ROOT/scripts/coverage-loop"
PROMPTS_DIR="$SCRIPT_DIR/prompts"

MAX_ITERS=15
DRY_RUN=0
RESUME_DIR=""

HUNTER_MODEL="gpt-5.4"
TEST_WRITER_MODEL="gpt-5.3-codex"
VALIDATOR_MODEL="gpt-5.4"
REVIEWER_MODEL="gpt-5.3-codex"

STAGE_TIMEOUT_S=1500
TEST_TIMEOUT_S=600

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max)     MAX_ITERS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --resume)  RESUME_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

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
ITER_FILE="$STATE_DIR/iteration.txt"
LATEST_LINK="$SCRIPT_DIR/runs/latest"

PERSISTENT_STATE_DIR="$SCRIPT_DIR/state"
mkdir -p "$PERSISTENT_STATE_DIR"
STOPLIST_FILE="$PERSISTENT_STATE_DIR/permanent-stoplist.md"
if [[ ! -f "$STOPLIST_FILE" ]]; then
  cat >"$STOPLIST_FILE" <<'EOF'
# Permanent stoplist (coverage-loop)
#
# Append-only ledger across runs. Hunter must not re-raise any slug listed
# below.
EOF
fi

RUN_STOPLIST="$STATE_DIR/stoplist.md"
[[ -f "$RUN_STOPLIST" ]] || echo "# This run's stoplist additions (full log: $STOPLIST_FILE)" >"$RUN_STOPLIST"
[[ -f "$ITER_FILE" ]] || echo 0 >"$ITER_FILE"

if (( IS_RESUME == 0 )); then
  ln -sfn "$WORKDIR" "$LATEST_LINK"
fi

# Portable timeout.
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

parse_block_after() {
  local file="$1" header="$2"
  awk -v h="$header" '
    $0 == h {found=1; next}
    found && /^## / {exit}
    found && NF {print; exit}
  ' "$file"
}

parse_dash_field() {
  local file="$1" field="$2"
  grep -m1 "^- ${field}:" "$file" 2>/dev/null \
    | sed -E "s/^- ${field}:[[:space:]]*//" \
    | sed -E 's/^"(.*)"$/\1/'
}

run_test_single_file() {
  local pkg="$1" test_file="$2" prefix="$3"
  local pkg_dir="$REPO_ROOT/packages/$pkg"
  local rel_test="${test_file#packages/$pkg/}"
  if (( DRY_RUN )); then
    echo "[DRY RUN] (cd packages/$pkg && flutter test $rel_test)" >"${prefix}.out"
    echo "0" >"${prefix}.exit"
    return 0
  fi
  (
    cd "$pkg_dir" || exit 99
    with_timeout "$TEST_TIMEOUT_S" flutter test --reporter=expanded "$rel_test"
  ) >"${prefix}.out" 2>&1
  local rc=$?
  echo "$rc" >"${prefix}.exit"
  return $rc
}

# Mutation gate: replace lines [start..end] of source_file with a throw,
# run the test once, restore the source. Returns 0 if test failed against
# mutation (good - test is load-bearing); 1 if it passed (test is not
# actually testing the cited source); 2 on infrastructure error.
mutation_check() {
  local pkg="$1" test_file="$2" src_file="$3" line_spec="$4" prefix="$5"
  local start_line end_line
  if [[ "$line_spec" == *-* ]]; then
    start_line="${line_spec%-*}"
    end_line="${line_spec#*-}"
  else
    start_line="$line_spec"
    end_line="$line_spec"
  fi
  if [[ ! -f "$REPO_ROOT/$src_file" ]]; then
    log "mutation: source file not found: $src_file"
    return 2
  fi
  local backup
  backup=$(mktemp)
  cp -a "$REPO_ROOT/$src_file" "$backup"

  python3 - "$REPO_ROOT/$src_file" "$start_line" "$end_line" <<'PY'
import sys, pathlib
path, s, e = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
p = pathlib.Path(path)
lines = p.read_text().splitlines()
s = max(1, s)
e = min(e, len(lines))
for i in range(s - 1, e):
    raw = lines[i]
    indent = len(raw) - len(raw.lstrip())
    if not raw.strip():
        continue
    lines[i] = ' ' * indent + 'throw UnimplementedError("mutated by coverage-loop");'
p.write_text('\n'.join(lines) + '\n')
PY

  run_test_single_file "$pkg" "$test_file" "$prefix"
  local rc=$?

  cp -a "$backup" "$REPO_ROOT/$src_file"
  rm -f "$backup"

  if (( rc == 0 )); then
    return 1
  fi
  return 0
}

START_TS=$(date +%s)
log "coverage-loop start; workdir=$WORKDIR; max_iters=$MAX_ITERS; dry_run=$DRY_RUN"

last_iteration=$(cat "$ITER_FILE")
clean_streak=0

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
  render_prompt "$PROMPTS_DIR/hunter.md" "$HUNT_PROMPT" \
    ITERATION "$i" \
    STOPLIST "$(cat "$STOPLIST_FILE")"
  if ! run_codex "$HUNT_PROMPT" "$HUNT_OUT" "$HUNTER_MODEL" "read-only"; then
    log "iter $i: hunter failed; ending loop"
    break
  fi

  status=$(grep -m1 -E '^(PROPOSAL_FOUND|CLEAN|DRY_RUN)$' "$HUNT_OUT" || echo "UNKNOWN")
  if [[ "$status" == "CLEAN" ]]; then
    clean_streak=$((clean_streak + 1))
    log "iter $i: hunter reports clean (streak=$clean_streak)"
    if (( clean_streak >= 2 )); then
      echo "CONVERGED: hunter clean for 2 consecutive iters at iter $i" >"$WORKDIR/CONVERGED"
      break
    fi
    continue
  fi
  if [[ "$status" != "PROPOSAL_FOUND" && "$status" != "DRY_RUN" ]]; then
    log "iter $i: hunter status=$status; skipping iter"
    continue
  fi
  clean_streak=0

  PACKAGE=$(parse_dash_field "$HUNT_OUT" "package")
  SLUG=$(parse_dash_field "$HUNT_OUT" "slug")
  SOURCE_FILE=$(parse_dash_field "$HUNT_OUT" "source_file")
  SOURCE_LINES=$(parse_dash_field "$HUNT_OUT" "source_lines")

  if [[ "$status" == "DRY_RUN" ]]; then
    PACKAGE="${PACKAGE:-plugin_kit}"
    SLUG="${SLUG:-dry-run-stub}"
    SOURCE_FILE="${SOURCE_FILE:-packages/plugin_kit/lib/src/dummy.dart}"
    SOURCE_LINES="${SOURCE_LINES:-1}"
  fi

  if [[ -z "$PACKAGE" || -z "$SLUG" || -z "$SOURCE_FILE" || -z "$SOURCE_LINES" ]]; then
    log "iter $i: hunter output missing fields (package=$PACKAGE slug=$SLUG file=$SOURCE_FILE lines=$SOURCE_LINES); skipping"
    continue
  fi
  log "iter $i: proposal pkg=$PACKAGE slug=$SLUG src=$SOURCE_FILE:$SOURCE_LINES"

  # ---- Stage 2: Test-writer ---------------------------------------------
  log "iter $i: test-writer"
  TW_PROMPT="$ITER_DIR/test-writer.prompt.md"
  TW_OUT="$ITER_DIR/test-writer.md"
  render_prompt "$PROMPTS_DIR/test-writer.md" "$TW_PROMPT" \
    ITERATION "$i" \
    ITERATION_PADDED "$ITER_PADDED" \
    PROPOSAL "$(cat "$HUNT_OUT")"
  if ! run_codex "$TW_PROMPT" "$TW_OUT" "$TEST_WRITER_MODEL" "workspace-write"; then
    log "iter $i: test-writer failed; ending loop"
    break
  fi

  tw_status=$(grep -m1 -E '^(TEST_WRITTEN|INFEASIBLE|DRY_RUN)$' "$TW_OUT" || echo "UNKNOWN")
  if [[ "$tw_status" == "INFEASIBLE" ]]; then
    log "iter $i: test-writer INFEASIBLE; stoplisting"
    stoplist_add "- iter $i infeasible: $SLUG"
    continue
  fi
  if [[ "$tw_status" == "DRY_RUN" ]]; then
    log "iter $i: dry-run; skipping rest of stages"
    continue
  fi

  TEST_FILE=$(parse_block_after "$TW_OUT" "## TEST_FILE")
  if [[ -z "$TEST_FILE" || ! -f "$REPO_ROOT/$TEST_FILE" ]]; then
    log "iter $i: test-writer did not produce a readable test file ($TEST_FILE); skipping"
    continue
  fi

  # ---- GREEN gate -------------------------------------------------------
  log "iter $i: GREEN check"
  GREEN_PREFIX="$ITER_DIR/green"
  run_test_single_file "$PACKAGE" "$TEST_FILE" "$GREEN_PREFIX"
  green_rc=$(cat "${GREEN_PREFIX}.exit")
  log "iter $i: GREEN exit=$green_rc"
  if (( green_rc != 0 )); then
    log "iter $i: test does not pass against current code; deleting and stoplisting"
    rm -f "$REPO_ROOT/$TEST_FILE"
    stoplist_add "- iter $i no-green: $SLUG"
    continue
  fi

  # ---- Stage 3: Validator -----------------------------------------------
  log "iter $i: validator"
  VAL_PROMPT="$ITER_DIR/validate.prompt.md"
  VAL_OUT="$ITER_DIR/validated.md"
  render_prompt "$PROMPTS_DIR/validator.md" "$VAL_PROMPT" \
    ITERATION "$i" \
    TEST_FILE_PATH "$TEST_FILE" \
    TEST_FILE_CONTENTS "$(cat "$REPO_ROOT/$TEST_FILE")" \
    GREEN_OUTPUT "$(tail -100 "${GREEN_PREFIX}.out")"
  if ! run_codex "$VAL_PROMPT" "$VAL_OUT" "$VALIDATOR_MODEL" "read-only"; then
    log "iter $i: validator failed; deleting test"
    rm -f "$REPO_ROOT/$TEST_FILE"
    continue
  fi
  val_decision=$(parse_block_after "$VAL_OUT" "## DECISION")
  log "iter $i: validator decision=$val_decision"
  if [[ "$val_decision" != "CONFIRMED" ]]; then
    rm -f "$REPO_ROOT/$TEST_FILE"
    stoplist_add "- iter $i validator-dropped: $SLUG"
    continue
  fi

  # ---- MUTATION gate ----------------------------------------------------
  log "iter $i: mutation gate (mutating $SOURCE_FILE:$SOURCE_LINES)"
  MUT_PREFIX="$ITER_DIR/mutation"
  mutation_check "$PACKAGE" "$TEST_FILE" "$SOURCE_FILE" "$SOURCE_LINES" "$MUT_PREFIX"
  mut_rc=$?
  if (( mut_rc == 2 )); then
    log "iter $i: mutation gate infrastructure error; deleting test"
    rm -f "$REPO_ROOT/$TEST_FILE"
    stoplist_add "- iter $i mutation-infra: $SLUG"
    continue
  fi
  if (( mut_rc == 1 )); then
    log "iter $i: test passes against mutated source; not load-bearing. Deleting."
    rm -f "$REPO_ROOT/$TEST_FILE"
    stoplist_add "- iter $i mutation-passed: $SLUG"
    continue
  fi
  log "iter $i: mutation gate passed (test fails against mutated source)"

  # ---- Stage 4: Reviewer ------------------------------------------------
  log "iter $i: reviewer"
  REV_PROMPT="$ITER_DIR/review.prompt.md"
  REV_OUT="$ITER_DIR/review.md"
  render_prompt "$PROMPTS_DIR/reviewer.md" "$REV_PROMPT" \
    ITERATION "$i" \
    TEST_FILE_PATH "$TEST_FILE" \
    TEST_FILE_CONTENTS "$(cat "$REPO_ROOT/$TEST_FILE")" \
    PROPOSAL "$(cat "$HUNT_OUT")"
  if ! run_codex "$REV_PROMPT" "$REV_OUT" "$REVIEWER_MODEL" "read-only"; then
    log "iter $i: reviewer failed; deleting test"
    rm -f "$REPO_ROOT/$TEST_FILE"
    continue
  fi
  rev_decision=$(parse_block_after "$REV_OUT" "## DECISION")
  log "iter $i: reviewer decision=$rev_decision"
  if [[ "$rev_decision" != "PASS" ]]; then
    log "iter $i: reviewer FAILED; deleting test"
    rm -f "$REPO_ROOT/$TEST_FILE"
    stoplist_add "- iter $i reviewer-failed: $SLUG"
    continue
  fi

  log "iter $i: SUCCESS - coverage test kept at $TEST_FILE"
  stoplist_add "- iter $i landed: $SLUG"
done

END_TS=$(date +%s)
elapsed=$((END_TS - START_TS))
log "coverage-loop end; elapsed=${elapsed}s; workdir=$WORKDIR"

if [[ -f "$WORKDIR/CONVERGED" ]]; then
  cat "$WORKDIR/CONVERGED"
else
  echo "loop ended without explicit convergence; iteration cap or stage failure" \
    | tee -a "$WORKDIR/orchestrator.log"
fi

echo
echo "artifacts:"
echo "  log:               $WORKDIR/orchestrator.log"
echo "  iters:             $WORKDIR/iters/"
echo "  state:             $WORKDIR/state/"
echo "  persistent state:  $PERSISTENT_STATE_DIR/"
echo "  coverage tests:    packages/*/test/coverage/"

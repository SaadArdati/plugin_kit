#!/usr/bin/env bash
# doc-audit-loop orchestrator
#
# Runs the auditor → validator → fixer → reviewer pipeline against the plugin_kit
# documentation surface, with an external `make` verifier as the convergence
# gate, snapshot-based rollback when the verifier fails, a stoplist mechanism
# to suppress recurring false positives, and a hard iteration cap.
#
# Codex agents NEVER commit. The orchestrator never commits either. Working
# state lives under WORKDIR (default: scripts/doc-audit-loop/runs/<timestamp>).
#
# Usage:
#   scripts/doc-audit-loop/orchestrator.sh              # full run
#   scripts/doc-audit-loop/orchestrator.sh --dry-run    # build prompts, no codex
#   scripts/doc-audit-loop/orchestrator.sh --max 5      # cap iterations
#   scripts/doc-audit-loop/orchestrator.sh --resume <run-dir>
#
# Read the README in this directory for the full workflow rationale.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$REPO_ROOT/scripts/doc-audit-loop"
PROMPTS_DIR="$SCRIPT_DIR/prompts"

MAX_ITERS=15
DRY_RUN=0
RESUME_DIR=""

# Models. Codex coding model for fixer/reviewer (better at edits), general for
# auditor/validator (better at reasoning over prose). Verify with
# `codex debug models` if dispatches fail.
AUDITOR_MODEL="gpt-5.4"
VALIDATOR_MODEL="gpt-5.4"
FIXER_MODEL="gpt-5.3-codex"
REVIEWER_MODEL="gpt-5.3-codex"

# Per-stage timeouts in seconds. Codex runs over a large doc surface can take a
# while; give them headroom.
STAGE_TIMEOUT_S=1500   # 25 min per stage
VERIFIER_TIMEOUT_S=900 # 15 min for the make + flutter test gate

# Files/dirs the fixer is allowed to touch. The snapshot/restore mechanism
# copies these before each fixer run and restores them on verifier failure.
#
# IMPORTANT: keep this list tight. Earlier versions snapshotted `website/` and
# `example/` wholesale, which dragged in `node_modules/`, `build/`,
# `.dart_tool/`, and `dist/` — about 1 GB per iteration. With 15 iterations
# that is 15 GB of dead-weight copies. Only list paths the fixer is actually
# allowed to edit per the fixer prompt.
declare -a DOC_SCOPE=(
  "website/src/content/docs"
  "website/snippets/lib"
  "example/villain_lair/bin"
  "example/villain_lair/lib"
  "example/state_garden/bin"
  "example/state_garden/lib"
  "example/state_garden/README.md"
  "example/code_editor/bin"
  "example/code_editor/lib"
  "example/model_embassy/bin"
  "example/model_embassy/lib"
  "example/plugin_kit_dialog_demo/bin"
  "example/plugin_kit_dialog_demo/lib"
  "packages/plugin_kit/lib"
  "packages/plugin_kit_dialog/lib"
  "packages/flutter_plugin_kit/lib"
  "README.md"
  "PACKAGE_ISSUES.md"
  "Makefile"
)
# READMEs under packages/ are also doc surface. We snapshot them individually.
declare -a PACKAGE_README_GLOBS=(
  "packages/plugin_kit/README.md"
  "packages/plugin_kit_dialog/README.md"
  "packages/plugin_kit_dialog/example/README.md"
  "packages/flutter_plugin_kit/README.md"
  "packages/flutter_plugin_kit/example/README.md"
)

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max)
      MAX_ITERS="$2"; shift 2 ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    --resume)
      RESUME_DIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)
      echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# Working directory layout
# ---------------------------------------------------------------------------

if [[ -n "$RESUME_DIR" ]]; then
  # Resolve to absolute path BEFORE any symlink mutation downstream. If a
  # caller hands in a path that happens to be the `latest` symlink, the
  # `ln -sfn` step below would otherwise overwrite that symlink with the
  # relative argument and break resume.
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
STOPLIST_FILE="$STATE_DIR/stoplist.md"
DROPPED_LEDGER="$STATE_DIR/dropped-ledger.md"
ITER_FILE="$STATE_DIR/iteration.txt"
LATEST_LINK="$SCRIPT_DIR/runs/latest"

# Stoplist seed (first run only)
if [[ ! -f "$STOPLIST_FILE" ]]; then
  cat >"$STOPLIST_FILE" <<'EOF'
# Stoplist (resolved or out-of-scope findings; auditor must not re-raise)
EOF
fi
[[ -f "$DROPPED_LEDGER" ]] || : >"$DROPPED_LEDGER"
[[ -f "$ITER_FILE" ]] || echo 0 >"$ITER_FILE"

# Only rewrite the `latest` symlink on a fresh run. On --resume we may have
# been handed the symlink itself; updating it from inside would corrupt it.
if (( IS_RESUME == 0 )); then
  ln -sfn "$WORKDIR" "$LATEST_LINK"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Portable timeout. macOS lacks `timeout`; Homebrew coreutils ships `gtimeout`.
# Fall back to a Perl shim when neither is available.
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
    echo "## STATUS\nCLEAN" >"$outpath"
    return 0
  fi
  # Use a temp file for stderr so we don't drown the orchestrator log.
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

snapshot_docs() {
  local target="$1"
  mkdir -p "$target"
  cd "$REPO_ROOT"
  for entry in "${DOC_SCOPE[@]}"; do
    [[ -e "$entry" ]] || continue
    cp -a "$entry" "$target/" || true
  done
  for r in "${PACKAGE_README_GLOBS[@]}"; do
    [[ -e "$r" ]] || continue
    mkdir -p "$target/$(dirname "$r")"
    cp -a "$r" "$target/$r"
  done
}

restore_docs() {
  local source="$1"
  cd "$REPO_ROOT"
  for entry in "${DOC_SCOPE[@]}"; do
    [[ -e "$source/$entry" ]] || continue
    rm -rf "$entry"
    # Recreate parent dir for entries one level deep (e.g. example/foo/lib).
    mkdir -p "$(dirname "$entry")"
    cp -a "$source/$entry" "$entry"
  done
  for r in "${PACKAGE_README_GLOBS[@]}"; do
    [[ -e "$source/$r" ]] || continue
    cp -a "$source/$r" "$r"
  done
}

# Keep only the most recent N snapshots. Snapshots exist for rollback safety
# during their iteration; older ones are pure disk weight.
#
# Implemented without bash 4-only features (`mapfile`/`readarray`) because
# macOS ships bash 3.2 by default.
prune_snapshots() {
  local keep="${1:-1}"
  local snaps_dir="$SNAP_DIR"
  [[ -d "$snaps_dir" ]] || return 0
  local all=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && all+=("$line")
  done < <(ls -1 "$snaps_dir" 2>/dev/null | sort)
  local total=${#all[@]}
  if (( total <= keep )); then return 0; fi
  local cut=$(( total - keep ))
  local idx
  for (( idx = 0; idx < cut; idx++ )); do
    rm -rf "$snaps_dir/${all[idx]}"
  done
}

paths_diff_against_snapshot() {
  # Print files that differ between the working tree and the given snapshot.
  local snap="$1"
  cd "$REPO_ROOT"
  for entry in "${DOC_SCOPE[@]}" "${PACKAGE_README_GLOBS[@]}"; do
    [[ -e "$entry" ]] || continue
    if [[ -d "$entry" ]]; then
      diff -rq "$snap/$entry" "$entry" 2>/dev/null \
        | awk '/differ$/ {gsub(/^Files /, ""); sub(/ and .* differ$/, ""); print}'
      diff -rq "$snap/$entry" "$entry" 2>/dev/null \
        | awk '/^Only in/ {dir=$3; sub(/:/, "", dir); print dir "/" $4}'
    else
      if ! cmp -s "$snap/$entry" "$entry" 2>/dev/null; then
        echo "$entry"
      fi
    fi
  done
}

write_diff_against_snapshot() {
  # Build a textual diff of changed files (vs snapshot) into the given file.
  local snap="$1" out="$2"
  : >"$out"
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    {
      echo "===== $p ====="
      diff -u "$snap/$p" "$REPO_ROOT/$p" 2>/dev/null || true
      echo ""
    } >>"$out"
  done < <(paths_diff_against_snapshot "$snap")
}

run_verifier() {
  local log="$1"
  if (( DRY_RUN )); then
    echo "[DRY RUN] skipped verifier" >"$log"
    return 0
  fi
  cd "$REPO_ROOT"
  {
    echo "## flutter analyze website/snippets"
    with_timeout "$VERIFIER_TIMEOUT_S" flutter analyze website/snippets || return $?
    echo
    echo "## flutter test website/snippets"
    with_timeout "$VERIFIER_TIMEOUT_S" flutter test website/snippets || return $?
    echo
    echo "## make doc-check (excerpts + versions)"
    with_timeout "$VERIFIER_TIMEOUT_S" make doc-check || return $?
  } >"$log" 2>&1
}

count_findings() {
  # Count occurrences of `## FINDING ` (auditor) or `## CONFIRMED ` (validator)
  # in the given file. grep -c emits "0\nexit-1" on zero matches; capture the
  # number cleanly and ignore the exit code.
  local file="$1" prefix="$2"
  if [[ ! -f "$file" ]]; then echo 0; return; fi
  local n
  n=$(grep -c "^## $prefix " "$file" 2>/dev/null || true)
  echo "${n:-0}"
}

extract_dropped_claims() {
  # Pull out one-liner identifiers for every DROPPED finding in a validator
  # report. Used to feed the stoplist when the same kind of claim is dropped
  # across iterations.
  local file="$1"
  awk '
    /^## DROPPED / {flag=1; next}
    /^## DROPPED / {flag=0}
    flag && /^- reason:/ {print $0}
  ' "$file"
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

START_TS=$(date +%s)
log "doc-audit-loop start; workdir=$WORKDIR; max_iters=$MAX_ITERS; dry_run=$DRY_RUN"

empty_streak=0
last_iteration=$(cat "$ITER_FILE")

for ((i = last_iteration + 1; i <= MAX_ITERS; i++)); do
  ITER_DIR="$ITERS_DIR/iter-$(printf %02d "$i")"
  mkdir -p "$ITER_DIR"
  log "==== iteration $i ===="
  echo "$i" >"$ITER_FILE"

  # ---- Stage 1: Auditor -------------------------------------------------
  log "iter $i: auditor"
  AUDIT_PROMPT="$ITER_DIR/audit.prompt.md"
  AUDIT_OUT="$ITER_DIR/audit.md"
  render_prompt "$PROMPTS_DIR/auditor.md" "$AUDIT_PROMPT" \
    ITERATION "$i" \
    STOPLIST "$(cat "$STOPLIST_FILE")"
  if ! run_codex "$AUDIT_PROMPT" "$AUDIT_OUT" "$AUDITOR_MODEL" "read-only"; then
    log "iter $i: auditor failed; ending loop"
    break
  fi

  status=$(grep -m1 -E '^(ISSUES_FOUND|CLEAN)$' "$AUDIT_OUT" || echo "UNKNOWN")
  finding_count=$(count_findings "$AUDIT_OUT" "FINDING")
  log "iter $i: auditor status=$status findings=$finding_count"

  if [[ "$status" == "CLEAN" ]] || (( finding_count == 0 )); then
    log "iter $i: auditor reports clean; convergence"
    echo "CONVERGED: auditor clean at iter $i" >"$WORKDIR/CONVERGED"
    break
  fi

  # ---- Stage 2: Validator -----------------------------------------------
  log "iter $i: validator"
  VAL_PROMPT="$ITER_DIR/validate.prompt.md"
  VAL_OUT="$ITER_DIR/validated.md"
  render_prompt "$PROMPTS_DIR/validator.md" "$VAL_PROMPT" \
    ITERATION "$i" \
    FINDINGS "$(cat "$AUDIT_OUT")"
  if ! run_codex "$VAL_PROMPT" "$VAL_OUT" "$VALIDATOR_MODEL" "read-only"; then
    log "iter $i: validator failed; ending loop"
    break
  fi

  confirmed_count=$(count_findings "$VAL_OUT" "CONFIRMED")
  dropped_count=$(count_findings "$VAL_OUT" "DROPPED")
  log "iter $i: validator confirmed=$confirmed_count dropped=$dropped_count"

  # Append this iter's drops to the ledger for the stoplist feedback.
  {
    echo "## iter $i drops"
    extract_dropped_claims "$VAL_OUT"
    echo
  } >>"$DROPPED_LEDGER"

  if (( confirmed_count == 0 )); then
    empty_streak=$((empty_streak + 1))
    log "iter $i: zero confirmed findings; empty_streak=$empty_streak"
    if (( empty_streak >= 2 )); then
      log "iter $i: two consecutive empty validator results; convergence"
      echo "CONVERGED: two consecutive empty validator passes at iter $i" >"$WORKDIR/CONVERGED"
      break
    fi
    # Promote this iter's dropped claims to the stoplist so the auditor stops
    # re-raising them. Keep entries short; format as compact bullets.
    {
      echo "## iter $i (validator rejected; do not re-raise)"
      extract_dropped_claims "$VAL_OUT" | sed 's/^- reason:/- /'
      echo
    } >>"$STOPLIST_FILE"
    continue
  fi

  # If the dropped:confirmed ratio is >4 for two iters running, the auditor is
  # mostly hallucinating; still iterate but log a warning.
  if (( dropped_count > 0 && dropped_count > 4 * confirmed_count )); then
    log "iter $i: WARNING dropped/confirmed ratio is $dropped_count / $confirmed_count"
  fi

  # ---- Pre-fix snapshot -------------------------------------------------
  SNAP_PATH="$SNAP_DIR/iter-$(printf %02d "$i")"
  log "iter $i: snapshot docs -> $SNAP_PATH"
  snapshot_docs "$SNAP_PATH"

  # ---- Stage 3: Fixer ---------------------------------------------------
  log "iter $i: fixer"
  FIX_PROMPT="$ITER_DIR/fix.prompt.md"
  FIX_OUT="$ITER_DIR/fix-report.md"
  render_prompt "$PROMPTS_DIR/fixer.md" "$FIX_PROMPT" \
    ITERATION "$i" \
    CONFIRMED "$(cat "$VAL_OUT")"
  if ! run_codex "$FIX_PROMPT" "$FIX_OUT" "$FIXER_MODEL" "workspace-write"; then
    log "iter $i: fixer failed; rolling back snapshot and ending loop"
    restore_docs "$SNAP_PATH"
    break
  fi

  # Build a diff against the snapshot for the reviewer to consume.
  DIFF_FILE="$ITER_DIR/changes.diff"
  write_diff_against_snapshot "$SNAP_PATH" "$DIFF_FILE"

  # ---- Stage 4: Reviewer ------------------------------------------------
  log "iter $i: reviewer"
  REV_PROMPT="$ITER_DIR/review.prompt.md"
  REV_OUT="$ITER_DIR/review.md"
  render_prompt "$PROMPTS_DIR/reviewer.md" "$REV_PROMPT" \
    ITERATION "$i" \
    FIX_REPORT "$(cat "$FIX_OUT")" \
    DIFF_PATH "$DIFF_FILE"
  if ! run_codex "$REV_PROMPT" "$REV_OUT" "$REVIEWER_MODEL" "workspace-write"; then
    log "iter $i: reviewer failed; rolling back snapshot"
    restore_docs "$SNAP_PATH"
    break
  fi

  # ---- Verifier (the external gate) -------------------------------------
  log "iter $i: verifier (make + flutter test)"
  VER_LOG="$ITER_DIR/verifier.log"
  if run_verifier "$VER_LOG"; then
    log "iter $i: verifier GREEN"
  else
    log "iter $i: verifier RED; restoring snapshot and recording breakage"
    restore_docs "$SNAP_PATH"
    {
      echo "## iter $i verifier failure"
      echo "snapshot restored. tail of verifier log:"
      tail -40 "$VER_LOG"
      echo
    } >>"$WORKDIR/VERIFIER_FAILURES.md"
    # Stoplist the findings from this iter since fixing them is currently
    # impossible without breaking the build. The next auditor needs to find
    # a different angle.
    {
      echo "## iter $i (verifier rejected fixes; revisit later)"
      grep '^- claim:' "$VAL_OUT" | head -20
      echo
    } >>"$STOPLIST_FILE"
  fi

  # Reset empty streak on a productive iteration.
  empty_streak=0

  # Reclaim disk: a snapshot is only needed for rollback during its own
  # iteration. Keep one as a debugging artifact, prune everything else.
  prune_snapshots 1
done

END_TS=$(date +%s)
elapsed=$((END_TS - START_TS))
log "doc-audit-loop end; elapsed=${elapsed}s; workdir=$WORKDIR"

if [[ -f "$WORKDIR/CONVERGED" ]]; then
  cat "$WORKDIR/CONVERGED"
else
  echo "loop ended without explicit convergence; iteration cap or stage failure" \
    | tee -a "$WORKDIR/orchestrator.log"
fi

echo
echo "artifacts:"
echo "  log:        $WORKDIR/orchestrator.log"
echo "  iters:      $WORKDIR/iters/"
echo "  state:      $WORKDIR/state/"
echo "  package issues: $REPO_ROOT/PACKAGE_ISSUES.md"

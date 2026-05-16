#!/usr/bin/env bash
# Decomp-loop orchestrator. Executes the runtime decomposition spec
# (docs/superpowers/plans/2026-05-16-runtime-decomposition.md) one step at a
# time. Sandboxed codex executor + multi-gate verification + codex reviewer.
# Stops at the commit boundary; never auto-commits.
#
# Usage:
#   bash scripts/decomp-loop/orchestrator.sh                  (run next step)
#   bash scripts/decomp-loop/orchestrator.sh --resume <dir>   (resume run dir)
#   bash scripts/decomp-loop/orchestrator.sh --dry-run        (no codex; gates only)
#   bash scripts/decomp-loop/orchestrator.sh --step <id>      (force a specific step id)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SPEC_PATH="$REPO_ROOT/docs/superpowers/plans/2026-05-16-runtime-decomposition.md"
PROMPTS_DIR="$SCRIPT_DIR/prompts"
PERSISTENT_STATE_DIR="$SCRIPT_DIR/state"
RUNS_DIR="$SCRIPT_DIR/runs"

EXECUTOR_MODEL="${DECOMP_EXECUTOR_MODEL:-gpt-5.3-codex}"
REVIEWER_MODEL="${DECOMP_REVIEWER_MODEL:-gpt-5.4}"
STAGE_TIMEOUT_S="${DECOMP_STAGE_TIMEOUT_S:-1500}"

# GNU `timeout` is missing on macOS by default. Prefer `gtimeout` (coreutils),
# then `timeout`, else fall back to perl-based timeout. The previous `env`
# fallback was a no-op and let codex hang indefinitely (Step 7 stuck 38min
# before manual kill).
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD=(gtimeout "$STAGE_TIMEOUT_S")
elif command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD=(timeout "$STAGE_TIMEOUT_S")
else
  # Perl-based timeout. SIGALRM kills the wrapper after N seconds; the
  # wrapper SIGTERMs its child first, then SIGKILL if still alive.
  TIMEOUT_CMD=(perl -e '
    my $t = shift;
    my $pid = fork // die "fork: $!";
    if ($pid == 0) { exec @ARGV or die "exec: $!"; }
    eval {
      local $SIG{ALRM} = sub { die "timeout\n"; };
      alarm $t;
      waitpid($pid, 0);
      alarm 0;
      exit($? >> 8);
    };
    if ($@ =~ /timeout/) {
      kill "TERM", $pid;
      sleep 2;
      kill "KILL", $pid;
      exit 124;
    }
  ' "$STAGE_TIMEOUT_S")
fi

# Sanity: codex must be on PATH.
if ! command -v codex >/dev/null 2>&1; then
  echo "FATAL: codex CLI not found in PATH. Install or activate it first." >&2
  exit 127
fi

DRY_RUN=0
RESUME_DIR=""
FORCED_STEP_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --resume) RESUME_DIR="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --step) FORCED_STEP_ID="${2:-}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Step list. Order matters; Step 4 is REMOVED per spec.
# Bash 3.2 (macOS default) has no associative arrays; use case statements.
STEP_IDS=( "0" "0a" "1" "2" "3" "5" "6" "7" )
TOTAL_STEPS=${#STEP_IDS[@]}

step_title_for_id() {
  case "$1" in
    "0")  echo "dispose pilot" ;;
    "0a") echo "public API contract test + test scaffolding" ;;
    "1")  echo "SettingsNormalizer extraction" ;;
    "2")  echo "EnablementResolver extraction" ;;
    "3")  echo "dispose pilot generalization (forwarders only)" ;;
    "5")  echo "init + plugin-add extension" ;;
    "6")  echo "session ownership plumbing (rename + move)" ;;
    "7")  echo "reconcile + transactional cluster" ;;
    *)    echo "unknown step" ;;
  esac
}

step_cluster_for_id() {
  case "$1" in
    "0")  echo "dispose pilot" ;;
    "0a") echo "public-api contract test" ;;
    "1")  echo "settings normalizer" ;;
    "2")  echo "enablement resolver" ;;
    "3")  echo "dispose pilot" ;;
    "5")  echo "init" ;;
    "6")  echo "session ownership" ;;
    "7")  echo "reconcile" ;;
    *)    echo "unknown" ;;
  esac
}

# ---- run-dir setup --------------------------------------------------------

if [[ -n "$RESUME_DIR" ]]; then
  if [[ ! -d "$RESUME_DIR" ]]; then
    echo "resume dir not found: $RESUME_DIR" >&2; exit 2
  fi
  WORKDIR="$RESUME_DIR"
else
  TS="$(date -u +'%Y%m%d-%H%M%SZ')"
  WORKDIR="$RUNS_DIR/$TS"
  mkdir -p "$WORKDIR/steps"
  mkdir -p "$PERSISTENT_STATE_DIR"
  ln -snf "$WORKDIR" "$RUNS_DIR/latest"
fi

LOG_FILE="$WORKDIR/orchestrator.log"
touch "$LOG_FILE"

log() { printf '[%s] %s\n' "$(date -u +'%H:%M:%S')" "$*" | tee -a "$LOG_FILE"; }

trap 'log "FATAL line $LINENO"; exit 1' ERR

log "decomp-loop start; workdir=$WORKDIR; spec=$SPEC_PATH"

# ---- step section extraction ---------------------------------------------

extract_step_section() {
  local step_id="$1" out_path="$2"
  local marker="^### Step ${step_id}: "
  local next_re="^### Step "
  awk -v m="$marker" -v n="$next_re" '
    BEGIN { inside=0 }
    inside==1 && $0 ~ n { exit }
    $0 ~ m { inside=1 }
    inside==1 { print }
  ' "$SPEC_PATH" > "$out_path"
  if [[ ! -s "$out_path" ]]; then
    log "FATAL could not extract step $step_id section from spec"
    return 1
  fi
  return 0
}

# Returns 0 if step appears already committed (matched in git log), 1 otherwise.
step_already_committed() {
  local step_id="$1"
  local i
  for i in "${!STEP_IDS[@]}"; do
    if [[ "${STEP_IDS[$i]}" == "$step_id" ]]; then
      local human_num=$((i + 1))
      local pattern="\\[step ${human_num} of ${TOTAL_STEPS}\\]"
      cd "$REPO_ROOT"
      if git log --grep="$pattern" --oneline -1 2>/dev/null | grep -q "refactor(plugin_kit)"; then
        return 0
      fi
      break
    fi
  done
  return 1
}

determine_next_step_id() {
  if [[ -n "$FORCED_STEP_ID" ]]; then
    printf '%s' "$FORCED_STEP_ID"; return 0
  fi
  local id
  for id in "${STEP_IDS[@]}"; do
    if ! step_already_committed "$id"; then
      printf '%s' "$id"; return 0
    fi
  done
  printf 'ALL_DONE'
}

step_index_for_id() {
  local target="$1" i
  for i in "${!STEP_IDS[@]}"; do
    if [[ "${STEP_IDS[$i]}" == "$target" ]]; then echo "$i"; return 0; fi
  done
  return 1
}

# ---- per-step gate library ------------------------------------------------

# Each gate writes to <prefix>.out, exit code to <prefix>.exit. Returns 0 on
# pass, non-zero on fail. Gates are intentionally noisy so the dashboard can
# show what failed.

gate_analyze() {
  local out="$1"
  cd "$REPO_ROOT"
  flutter analyze packages/plugin_kit > "${out}.out" 2>&1
  local rc=$?
  # flutter analyze exits 1 even for info-only diagnostics; the spec gate
  # bans warnings and errors only. Treat exit 0 OR (exit 1 with zero `error
  # •` and `warning •` lines) as PASS. grep -c always prints a number; use
  # tr to drop the trailing newline so the arithmetic test is safe.
  local err_count warn_count
  err_count=$(grep -cE "^[[:space:]]*error " "${out}.out" 2>/dev/null | tr -d '\n')
  warn_count=$(grep -cE "^[[:space:]]*warning " "${out}.out" 2>/dev/null | tr -d '\n')
  err_count=${err_count:-0}
  warn_count=${warn_count:-0}
  if [[ "$rc" -eq 0 ]] || { [[ "$rc" -eq 1 ]] && [[ "$err_count" -eq 0 ]] && [[ "$warn_count" -eq 0 ]]; }; then
    echo "0" > "${out}.exit"
    return 0
  fi
  echo "$rc" > "${out}.exit"
  return $rc
}

gate_test() {
  local out="$1"
  cd "$REPO_ROOT"
  flutter test packages/plugin_kit > "${out}.out" 2>&1
  local rc=$?
  echo "$rc" > "${out}.exit"
  return $rc
}

# Sections-7 grep gates. The spec enumerates them as "binding per step".
# Step-specific gates accumulate as later steps add files.
gate_grep() {
  local step_id="$1" out="$2"
  cd "$REPO_ROOT"
  : > "${out}.out"
  local pass=1

  # Part-of URI: every file under runtime/ must declare part of '../plugin.dart';
  if [[ -d packages/plugin_kit/lib/src/plugin/runtime ]]; then
    while IFS= read -r f; do
      local first_part_line
      first_part_line=$(grep -nE "^part of " "$f" | head -1 || true)
      if [[ -n "$first_part_line" ]] && ! grep -qE "^part of '\.\./plugin\.dart';" "$f"; then
        echo "FAIL part-of-uri: $f: $first_part_line" >> "${out}.out"
        pass=0
      fi
    done < <(find packages/plugin_kit/lib/src/plugin/runtime -name '*.dart' 2>/dev/null)
  fi

  # SettingsNormalizer gate (only applies once the file exists, i.e. from Step 1 on)
  local sn="packages/plugin_kit/lib/src/plugin/runtime/settings_normalizer.dart"
  if [[ -f "$sn" ]]; then
    # Plugin token forbidden (except PluginId, PluginConfig, LocalPluginOverride substrings)
    local plugin_hits
    plugin_hits=$(grep -nE '\bPlugin\b' "$sn" | grep -vE 'PluginId|PluginConfig|LocalPluginOverride' || true)
    if [[ -n "$plugin_hits" ]]; then
      echo "FAIL settings_normalizer.dart names Plugin type:" >> "${out}.out"
      echo "$plugin_hits" >> "${out}.out"
      pass=0
    fi
    # No import of plugin.dart at any depth, single/double quoted, with leading whitespace
    if grep -nE "^[[:space:]]*import[[:space:]]+['\"](\.\./)*plugin\.dart['\"]" "$sn" >> "${out}.out"; then
      echo "FAIL settings_normalizer.dart imports plugin.dart (any depth, any quote style)" >> "${out}.out"
      pass=0
    fi
  fi

  # EnablementResolver gate (only applies from Step 2 on)
  local er="packages/plugin_kit/lib/src/plugin/runtime/enablement.dart"
  if [[ -f "$er" ]]; then
    # Allowlist: only _runtimeLog or _log are permitted underscore-prefixed names
    local bad_under
    bad_under=$(grep -nE '\b_[a-zA-Z]' "$er" | grep -vE '_runtimeLog\b|_log\b' || true)
    if [[ -n "$bad_under" ]]; then
      echo "FAIL enablement.dart references forbidden underscore-prefixed identifier:" >> "${out}.out"
      echo "$bad_under" >> "${out}.out"
      pass=0
    fi
  fi

  if [[ $pass -eq 1 ]]; then
    echo "PASS all grep gates" >> "${out}.out"
    echo 0 > "${out}.exit"; return 0
  else
    echo 1 > "${out}.exit"; return 1
  fi
}

# Confirms every public method on PluginRuntime still has a declaration in
# runtime.dart. (Not a structural check that it's the SAME declaration -- the
# extension-impl pattern means the body can be one-line; what we verify is
# that the public name still appears at the class level.)
gate_signatures() {
  local out="$1"
  local f="$REPO_ROOT/packages/plugin_kit/lib/src/plugin/runtime.dart"
  : > "${out}.out"
  local pass=1
  # Use -F (fixed string) for each signature; the `(` chars would otherwise
  # trip ERE parsing. Each entry is a unique fixed substring known to appear
  # in the public-method declaration line; the orchestrator does not care
  # whether the body is on the same line (forwarder) or follows on the next.
  local sigs=(
    'class PluginRuntime<'
    'PluginRuntime init({'
    'Future<void> dispose('
    'Future<void> updateSettings('
    'Future<void> updateGlobalSettings('
    'Future<void> updateSessionSettings('
    'Future<PluginSession<S>> createSession('
    'void updateSettingsSnapshot('
    'void resetSettings('
    'void addPlugin(Plugin '
    'void addPlugins(List<Plugin>'
    'bool isPluginEnabled('
    'bool isPluginAttached('
  )
  local sig
  for sig in "${sigs[@]}"; do
    if ! grep -qF "$sig" "$f"; then
      echo "FAIL missing signature: $sig" >> "${out}.out"
      pass=0
    fi
  done
  if [[ $pass -eq 1 ]]; then
    echo "PASS all public signatures present in runtime.dart" >> "${out}.out"
    echo 0 > "${out}.exit"; return 0
  else
    echo 1 > "${out}.exit"; return 1
  fi
}

gate_line_count() {
  local out="$1"
  local f="$REPO_ROOT/packages/plugin_kit/lib/src/plugin/runtime.dart"
  local current_lines
  current_lines=$(wc -l < "$f" | tr -d ' ')
  echo "runtime.dart: ${current_lines} lines" > "${out}.out"
  # Soft gate -- always passes, exists for dashboard visibility. Spec section
  # 11 explicitly says line-delta is a sanity gate, not a correctness gate.
  echo 0 > "${out}.exit"
  return 0
}

# ---- main step pipeline ---------------------------------------------------

run_step() {
  local step_id="$1"
  local step_index
  step_index=$(step_index_for_id "$step_id") || {
    log "FATAL unknown step id: $step_id"; return 2
  }
  local human_num=$((step_index + 1))
  local step_title cluster
  step_title="$(step_title_for_id "$step_id")"
  cluster="$(step_cluster_for_id "$step_id")"
  # Use 2-digit zero-padded numeric index for dashboard compatibility.
  # Map: step-00=0, step-01=0a, step-02=1, step-03=2, step-04=3, step-05=5,
  # step-06=6, step-07=7. The spec-side step id ("0a", "5") is preserved in
  # step.txt and in the dashboard column.
  local dir_num
  printf -v dir_num '%02d' "$step_index"
  local step_dir="$WORKDIR/steps/step-${dir_num}"
  mkdir -p "$step_dir"
  printf '%s' "$step_id" > "$step_dir/step.txt"
  printf '%s' "$step_title" > "$step_dir/title.txt"
  printf '%s' "$cluster" > "$step_dir/cluster.txt"
  : > "$step_dir/status.txt"
  echo "starting" > "$step_dir/phase.txt"

  log "==== step ${step_id} (${human_num} of ${TOTAL_STEPS}): ${step_title} ===="

  # Working tree must be free of changes that would either contaminate the
  # step's commit or hide a real conflict. We block on:
  #   - any modified tracked file (would land in `git diff` and get staged)
  #   - any untracked file inside packages/plugin_kit/{lib,test} (the auto-
  #     stage scope picks these up)
  # Pre-existing untracked dirs OUTSIDE that scope (e.g. docs/articles/,
  # .claude/, .dart-tool/) do not get staged, so they are tolerated.
  cd "$REPO_ROOT"
  local modified untracked_pkg
  modified=$(git diff --name-only)
  untracked_pkg=$(git ls-files --others --exclude-standard \
                  packages/plugin_kit/lib packages/plugin_kit/test 2>/dev/null || true)
  if [[ -n "$modified" || -n "$untracked_pkg" ]]; then
    log "BLOCK in-scope tree dirty; resolve before running a step:"
    if [[ -n "$modified" ]]; then
      log "  modified tracked files:"
      printf '    %s\n' $modified | tee -a "$LOG_FILE"
    fi
    if [[ -n "$untracked_pkg" ]]; then
      log "  untracked files inside packages/plugin_kit/{lib,test}:"
      printf '    %s\n' $untracked_pkg | tee -a "$LOG_FILE"
    fi
    echo "BLOCKED in-scope tree dirty at step start" > "$step_dir/status.txt"
    return 3
  fi

  # Extract spec section for this step.
  local spec_section="$step_dir/spec-section.md"
  extract_step_section "$step_id" "$spec_section" || return 3

  local section_start section_end
  section_start=$(grep -n "^### Step ${step_id}: " "$SPEC_PATH" | head -1 | cut -d: -f1)
  # Stop at the next "### Step " (next step in same section) OR the next
  # "## " (next top-level section, e.g. "## 6. End state"). For Step 7
  # (the last step), this prevents bleeding into the End State / Test gap
  # / Review log sections that follow.
  section_end=$(awk -v start="$section_start" '
    NR > start && (/^### Step / || /^## [0-9]/) { print NR - 1; found=1; exit }
    END { if (found != 1) print NR }
  ' "$SPEC_PATH")

  # Render executor prompt.
  local exec_prompt="$step_dir/executor.prompt.md"
  sed \
    -e "s|{{STEP_ID}}|${step_id}|g" \
    -e "s|{{STEP_TITLE}}|${step_title}|g" \
    -e "s|{{STEP_START_LINE}}|${section_start}|g" \
    -e "s|{{STEP_END_LINE}}|${section_end}|g" \
    "$PROMPTS_DIR/step-executor.md" > "$exec_prompt"

  # ---- EXECUTE ----------------------------------------------------------
  echo "executor" > "$step_dir/phase.txt"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "step ${step_id}: DRY_RUN; skipping codex executor"
    echo "DRY_RUN" > "$step_dir/codex.out"
    echo 0 > "$step_dir/codex.exit"
  else
    log "step ${step_id}: executor (codex workspace-write, ${EXECUTOR_MODEL})"
    "${TIMEOUT_CMD[@]}" codex exec \
      -C "$REPO_ROOT" \
      -m "$EXECUTOR_MODEL" \
      -s workspace-write \
      -c 'shell_environment_policy.inherit="all"' \
      --color never \
      -o "$step_dir/codex.out" \
      "$(cat "$exec_prompt")" >"$step_dir/codex.stderr" 2>&1
    echo $? > "$step_dir/codex.exit"
  fi

  if [[ "$(cat "$step_dir/codex.exit")" != "0" ]]; then
    log "BLOCK codex executor non-zero exit"
    echo "BLOCKED codex executor failed" > "$step_dir/status.txt"
    return 3
  fi

  # Heuristic: executor reported BLOCKED itself.
  if grep -qE '^## STATUS\s*$' "$step_dir/codex.out" 2>/dev/null \
      && grep -A1 '^## STATUS\s*$' "$step_dir/codex.out" | grep -qE '^BLOCKED\s*$'; then
    log "BLOCK executor self-reported BLOCKED; see codex.out"
    echo "BLOCKED executor self-reported" > "$step_dir/status.txt"
    return 3
  fi

  # ---- GATES ------------------------------------------------------------
  echo "analyze" > "$step_dir/phase.txt"
  log "step ${step_id}: gate analyze"
  if ! gate_analyze "$step_dir/analyze"; then
    log "BLOCK analyze failed"
    echo "BLOCKED analyze" > "$step_dir/status.txt"
    return 3
  fi

  echo "test" > "$step_dir/phase.txt"
  log "step ${step_id}: gate test (full plugin_kit suite)"
  if ! gate_test "$step_dir/test"; then
    log "BLOCK test failed"
    echo "BLOCKED test" > "$step_dir/status.txt"
    return 3
  fi

  echo "grep" > "$step_dir/phase.txt"
  log "step ${step_id}: gate grep"
  if ! gate_grep "$step_id" "$step_dir/grep-gates"; then
    log "BLOCK grep gate failed"
    echo "BLOCKED grep" > "$step_dir/status.txt"
    return 3
  fi

  echo "signatures" > "$step_dir/phase.txt"
  log "step ${step_id}: gate signatures"
  if ! gate_signatures "$step_dir/signatures"; then
    log "BLOCK signature gate failed"
    echo "BLOCKED signatures" > "$step_dir/status.txt"
    return 3
  fi

  gate_line_count "$step_dir/line-count"  # soft

  # Snapshot diff for reviewer. `git diff` alone misses untracked-new files,
  # which the reviewer interprets as "the file wasn't created" -> false FAIL.
  # `git add -N` (intent-to-add) on untracked files in scope brings them into
  # `git diff` as new-file diffs WITHOUT actually staging their content.
  echo "diff-snapshot" > "$step_dir/phase.txt"
  cd "$REPO_ROOT"
  local new_files
  new_files=$(git ls-files --others --exclude-standard \
              packages/plugin_kit/lib packages/plugin_kit/test 2>/dev/null)
  if [[ -n "$new_files" ]]; then
    # shellcheck disable=SC2086
    git add -N $new_files
  fi
  git diff --no-color > "$step_dir/diff.patch" 2>/dev/null
  local diff_size
  diff_size=$(wc -l < "$step_dir/diff.patch" | tr -d ' ')
  log "step ${step_id}: diff is ${diff_size} lines (incl. untracked-as-intent-to-add)"

  # ---- REVIEWER ---------------------------------------------------------
  local review_prompt="$step_dir/review.prompt.md"
  sed \
    -e "s|{{STEP_ID}}|${step_id}|g" \
    -e "s|{{STEP_TITLE}}|${step_title}|g" \
    -e "s|{{CLUSTER_LABEL}}|${cluster}|g" \
    -e "s|{{STEP_START_LINE}}|${section_start}|g" \
    -e "s|{{STEP_END_LINE}}|${section_end}|g" \
    -e "s|{{EXECUTOR_REPORT_PATH}}|${step_dir}/codex.out|g" \
    -e "s|{{DIFF_PATH}}|${step_dir}/diff.patch|g" \
    "$PROMPTS_DIR/reviewer.md" > "$review_prompt"

  echo "reviewer" > "$step_dir/phase.txt"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "step ${step_id}: DRY_RUN; skipping codex reviewer"
    cat > "$step_dir/review.md" <<EOF
## DECISION
PASS
EOF
  else
    log "step ${step_id}: reviewer (codex read-only, ${REVIEWER_MODEL})"
    "${TIMEOUT_CMD[@]}" codex exec \
      -C "$REPO_ROOT" \
      -m "$REVIEWER_MODEL" \
      -s read-only \
      -c 'shell_environment_policy.inherit="all"' \
      --color never \
      -o "$step_dir/review.md" \
      "$(cat "$review_prompt")" >"$step_dir/review.stderr" 2>&1 || true
  fi

  local review_decision
  review_decision=$(grep -A1 '^## DECISION\s*$' "$step_dir/review.md" | tail -1 | awk '{print $1}')
  log "step ${step_id}: reviewer decision=${review_decision:-UNKNOWN}"
  if [[ "$review_decision" != "PASS" ]]; then
    log "BLOCK reviewer did not PASS"
    echo "BLOCKED reviewer ${review_decision:-UNKNOWN}" > "$step_dir/status.txt"
    return 3
  fi

  # ---- STAGE (no commit) ------------------------------------------------
  echo "staging" > "$step_dir/phase.txt"
  cd "$REPO_ROOT"
  # `git diff --name-only` lists modifications and deletions but not new
  # untracked files. `git ls-files --others` lists untracked. Union gives
  # us every path the executor touched (modified/added/deleted), which we
  # then stage by name (never `-A`).
  local changed_files
  changed_files=$(git diff --name-only)
  local untracked
  untracked=$(git ls-files --others --exclude-standard \
              packages/plugin_kit/lib packages/plugin_kit/test 2>/dev/null || true)
  local all_files
  all_files=$(printf '%s\n%s\n' "$changed_files" "$untracked" | sort -u | sed '/^$/d')

  if [[ -z "$all_files" ]]; then
    log "BLOCK no files changed; executor produced no diff"
    echo "BLOCKED no-diff" > "$step_dir/status.txt"
    return 3
  fi

  # Stage every touched path. Note: `git add <deleted-file>` does NOT
  # stage the deletion in modern git (the path no longer exists). For
  # deletions we need `git add -u <path>` which restages tracked file
  # changes including removals. Run both: per-file `add` for new/modified
  # files, then `add -u` scoped to in-scope dirs to catch deletions the
  # per-file pass missed.
  while IFS= read -r f; do
    git add "$f" 2>/dev/null || true
  done <<< "$all_files"
  git add -u packages/plugin_kit/lib packages/plugin_kit/test 2>/dev/null || true

  # Write a commit message file the user can hand to git -F.
  local commit_msg_path="$step_dir/commit-message.txt"
  {
    echo "refactor(plugin_kit): extract ${cluster} [step ${human_num} of ${TOTAL_STEPS}]"
    echo ""
    echo "Spec: docs/superpowers/plans/2026-05-16-runtime-decomposition.md"
    echo "Step id: ${step_id} (${step_title})"
    echo ""
    echo "Files in this commit:"
    while IFS= read -r f; do echo "- $f"; done <<< "$all_files"
    echo ""
    echo "Verified gates: analyze (clean), test (all pass), grep gates,"
    echo "public-signature preservation, reviewer PASS."
    echo ""
    echo "Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
  } > "$commit_msg_path"

  echo "ready" > "$step_dir/phase.txt"
  echo "READY_FOR_COMMIT" > "$step_dir/status.txt"
  log "step ${step_id}: READY_FOR_COMMIT"
  log "  diff staged: ${all_files//$'\n'/, }"
  log "  commit message: ${commit_msg_path}"
  log "  to commit:  git commit -F '${commit_msg_path}'"
  log "  to resume:  bash scripts/decomp-loop/orchestrator.sh --resume '$WORKDIR'"

  # Append to persistent progress log.
  printf '[%s] step %s READY_FOR_COMMIT\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$step_id" \
    >> "$PERSISTENT_STATE_DIR/progress.log"

  return 0
}

# ---- top level ------------------------------------------------------------

NEXT_STEP="$(determine_next_step_id)"
if [[ "$NEXT_STEP" == "ALL_DONE" ]]; then
  log "ALL STEPS COMMITTED. Decomposition complete."
  echo "all steps committed" > "$WORKDIR/COMPLETE"
  exit 0
fi

log "next step: $NEXT_STEP"
run_step "$NEXT_STEP"
RC=$?

if [[ $RC -eq 0 ]]; then
  log "step ${NEXT_STEP} READY. Review the staged diff, commit, then run --resume."
  exit 0
elif [[ $RC -eq 3 ]]; then
  log "step ${NEXT_STEP} BLOCKED. See $WORKDIR/steps/step-${NEXT_STEP}/ for details."
  exit 3
else
  log "step ${NEXT_STEP} FATAL (rc=$RC)"
  exit $RC
fi

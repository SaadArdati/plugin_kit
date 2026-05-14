#!/usr/bin/env bash
# Tail the most recent doc-audit-loop run.
#
# Usage:
#   scripts/doc-audit-loop/monitor.sh           # follow the latest run's log
#   scripts/doc-audit-loop/monitor.sh status    # snapshot of current state
#   scripts/doc-audit-loop/monitor.sh diff      # diff for the most recent iter
#   scripts/doc-audit-loop/monitor.sh runs      # list runs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNS_DIR="$SCRIPT_DIR/runs"
LATEST="$RUNS_DIR/latest"

cmd="${1:-tail}"

case "$cmd" in
  tail|"")
    [[ -L "$LATEST" ]] || { echo "no runs yet"; exit 0; }
    tail -F "$LATEST/orchestrator.log"
    ;;
  status)
    [[ -L "$LATEST" ]] || { echo "no runs yet"; exit 0; }
    target=$(readlink "$LATEST")
    echo "latest run: $target"
    echo "iteration:  $(cat "$LATEST/state/iteration.txt" 2>/dev/null || echo 0)"
    if [[ -f "$LATEST/CONVERGED" ]]; then
      cat "$LATEST/CONVERGED"
    fi
    echo
    echo "tail of orchestrator log:"
    tail -20 "$LATEST/orchestrator.log" 2>/dev/null || echo "(no log)"
    echo
    if [[ -f "$LATEST/VERIFIER_FAILURES.md" ]]; then
      echo "verifier failures:"
      cat "$LATEST/VERIFIER_FAILURES.md"
    fi
    ;;
  diff)
    [[ -L "$LATEST" ]] || { echo "no runs yet"; exit 0; }
    last_iter=$(ls -1 "$LATEST/iters" 2>/dev/null | tail -1)
    [[ -n "$last_iter" ]] || { echo "no iterations yet"; exit 0; }
    diff_file="$LATEST/iters/$last_iter/changes.diff"
    if [[ -s "$diff_file" ]]; then
      "${PAGER:-less}" "$diff_file"
    else
      echo "no changes in $last_iter"
    fi
    ;;
  runs)
    ls -1 "$RUNS_DIR" 2>/dev/null | grep -v '^latest$' || echo "no runs yet"
    ;;
  *)
    echo "usage: $0 {tail|status|diff|runs}" >&2
    exit 2
    ;;
esac

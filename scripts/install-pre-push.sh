#!/usr/bin/env bash
# install-pre-push.sh — install the protected-branch pre-push hook into git checkouts.
#
#   scripts/install-pre-push.sh <repo-dir> [<repo-dir> ...]
#
# Idempotent. If a pre-push hook already exists (e.g. gitleaks) it is preserved as
# `pre-push.local`; our guard runs first and then replays stdin to it. Hooks are per-clone and
# NOT versioned, so re-run this after cloning a repo fresh — that is the one weakness of the
# client-side layer, and why guard-main.yml exists as the server-side detector.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/pre-push"
[ -f "$SRC" ] || { echo "missing $SRC"; exit 1; }

installed=0; chained=0; already=0; skipped=0
for dir in "$@"; do
  gitdir=$(git -C "$dir" rev-parse --git-dir 2>/dev/null) || { skipped=$((skipped+1)); continue; }
  case "$gitdir" in /*) ;; *) gitdir="$(cd "$dir" && pwd)/${gitdir#./}" ;; esac
  hooks="$gitdir/hooks"; mkdir -p "$hooks"
  hook="$hooks/pre-push"

  if [ -f "$hook" ] && grep -q 'REFUSING non-fast-forward' "$hook" 2>/dev/null; then
    already=$((already+1)); continue
  fi
  if [ -f "$hook" ]; then                    # preserve an existing hook (gitleaks, …)
    mv "$hook" "$hooks/pre-push.local"; chmod +x "$hooks/pre-push.local"
    chained=$((chained+1))
  fi

  cp "$SRC" "$hook"; chmod +x "$hook"
  echo "  installed: $dir"
  installed=$((installed+1))
done
echo "pre-push guard: $installed installed, $chained chained over an existing hook, $already already-present, $skipped not-a-git-repo"

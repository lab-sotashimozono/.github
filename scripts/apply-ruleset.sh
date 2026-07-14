#!/usr/bin/env bash
# Create or update the per-repo branch-protection ruleset (idempotent).
# Repository rulesets work on Free (incl. private); org rulesets would need Team.
# Usage: apply-ruleset.sh <repo>
set -euo pipefail
ORG=lab-sotashimozono
REPO="${1:?usage: apply-ruleset.sh <repo>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILE="$HERE/../rulesets/protect-default.json"
NAME=protect-default-branch

ID=$(gh api "/repos/$ORG/$REPO/rulesets" --jq \
  ".[] | select(.name==\"$NAME\") | .id" 2>/dev/null || true)

if [ -n "${ID:-}" ]; then
  gh api -X PUT "/repos/$ORG/$REPO/rulesets/$ID" --input "$FILE" >/dev/null
  echo "   ruleset updated (id=$ID)"
else
  gh api -X POST "/repos/$ORG/$REPO/rulesets" --input "$FILE" >/dev/null
  echo "   ruleset created"
fi

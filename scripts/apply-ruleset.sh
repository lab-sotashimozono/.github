#!/usr/bin/env bash
# Create or update one repo's branch-protection ruleset (idempotent).
#
# PLAN GATE (verified empirically 2026-07-14): on GitHub **Free**, rulesets work on PUBLIC
# repos only. A PRIVATE repo returns 403 "Upgrade to GitHub Pro or make this repository
# public to enable this feature." — no admin token can bypass a plan gate. We detect that
# and report it instead of failing the whole run. Upgrading the org to Team makes every
# private repo start getting the ruleset with NO change to this script.
#
# Usage: apply-ruleset.sh <repo>
set -uo pipefail
ORG=lab-sotashimozono
REPO="${1:?usage: apply-ruleset.sh <repo>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILE="$HERE/../rulesets/protect-default.json"
NAME=protect-default-branch

if ! gh api "/repos/$ORG/$REPO/rulesets" >/dev/null 2>&1; then
  echo "   ruleset UNAVAILABLE on this plan (private repo on Free → needs GitHub Pro/Team)"
  exit 0
fi

ID=$(gh api "/repos/$ORG/$REPO/rulesets" --jq ".[] | select(.name==\"$NAME\") | .id" 2>/dev/null || true)

if [ -n "${ID:-}" ]; then
  gh api -X PUT "/repos/$ORG/$REPO/rulesets/$ID" --input "$FILE" >/dev/null && echo "   ruleset updated (id=$ID)"
else
  gh api -X POST "/repos/$ORG/$REPO/rulesets" --input "$FILE" >/dev/null && echo "   ruleset created"
fi

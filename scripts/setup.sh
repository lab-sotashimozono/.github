#!/usr/bin/env bash
# One-shot, idempotent org initialization. Run as an org admin (gh auth logged in).
#
#   BOT_PAT=<token> scripts/setup.sh        # also syncs the BOT_PAT repo secret
#   scripts/setup.sh                        # settings only (skips secret sync)
#
# Per repo listed in repos.tsv it reconciles:
#   - branch-protection ruleset (repo-level -> works on Free, incl. private)
#   - BOT_PAT secret (only when BOT_PAT is in the environment)
#   - presence of CI workflows (adopt missing ones via init-repo.sh)
set -euo pipefail
ORG=lab-sotashimozono
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$HERE/../repos.tsv"

# --- sanity: authenticated admin on the org ---------------------------------
gh auth status >/dev/null || { echo "gh not authenticated"; exit 1; }
gh api "/orgs/$ORG" -q .login >/dev/null || { echo "no access to org $ORG"; exit 1; }
PLAN=$(gh api "/orgs/$ORG" -q .plan.name 2>/dev/null || echo unknown)
echo "== org=$ORG  plan=$PLAN =="

# --- per-repo reconciliation ------------------------------------------------
while IFS=$'\t' read -r repo vis _; do
  [[ -z "$repo" || "$repo" == \#* ]] && continue
  echo "-- $repo ($vis)"

  # branch-protection ruleset (tolerant: a plan/permission failure is reported,
  # not fatal, so the rest of the manifest still reconciles)
  "$HERE/apply-ruleset.sh" "$repo" || echo "   ruleset FAILED (plan/permission?)"

  # BOT_PAT secret (only if a value is provided in the environment)
  if [ -n "${BOT_PAT:-}" ]; then
    gh secret set BOT_PAT --repo "$ORG/$repo" --body "$BOT_PAT" \
      && echo "   BOT_PAT secret synced"
  else
    echo "   BOT_PAT not in env -> skipping secret sync"
  fi

  # CI presence check (does not auto-open PRs)
  if gh api "/repos/$ORG/$repo/contents/.github/workflows/ci.yml" >/dev/null 2>&1; then
    echo "   CI present"
  else
    echo "   CI MISSING -> run: scripts/init-repo.sh $repo $vis"
  fi
done < "$MANIFEST"

echo "== done =="

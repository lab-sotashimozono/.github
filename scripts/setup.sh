#!/usr/bin/env bash
# One-shot, idempotent org initialization. Run as an org admin (gh auth logged in).
#
#   scripts/setup.sh                 # reconcile every repo in repos.tsv
#   scripts/setup.sh ITensorAD.jl    # just one
#
# Per repo it reconciles / reports:
#   - branch-protection ruleset (REPO-level → works on Free, incl. private)
#   - adoption of the org reusable workflows (FormatCheck / AutoRegister)
# BOT_PAT lives as an ORG secret (visibility=all), so every repo — private included —
# gets it via `secrets: inherit`. Nothing per-repo to sync.
set -uo pipefail
ORG=lab-sotashimozono
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$HERE/../repos.tsv"
ONLY="${1:-}"

gh auth status >/dev/null 2>&1 || { echo "gh not authenticated"; exit 1; }
gh api "/orgs/$ORG" -q .login >/dev/null || { echo "no access to org $ORG"; exit 1; }
PLAN=$(gh api "/orgs/$ORG" -q .plan.name 2>/dev/null || echo unknown)
echo "== org=$ORG  plan=$PLAN =="

if gh api "/orgs/$ORG/actions/secrets/BOT_PAT" --jq '.name' >/dev/null 2>&1; then
  echo "== BOT_PAT: org secret present (visibility=$(gh api "/orgs/$ORG/actions/secrets/BOT_PAT" --jq '.visibility')) =="
else
  echo "== BOT_PAT: MISSING at org level — CompatHelper PRs won't trigger CI and private"
  echo "   AutoRegister tags won't fire PublishRelease. Add it as an org Actions secret. =="
fi

has() { gh api "/repos/$ORG/$1/contents/.github/workflows/$2" >/dev/null 2>&1; }

while IFS=$'\t' read -r repo vis _; do
  [[ -z "$repo" || "$repo" == \#* ]] && continue
  [[ -n "$ONLY" && "$ONLY" != "$repo" ]] && continue
  echo "-- $repo ($vis)"
  "$HERE/apply-ruleset.sh" "$repo" || echo "   ruleset FAILED (plan/permission?)"

  # Actions access: let this repo's actions / reusable workflows be called from anywhere in
  # the org ("Accessible from repositories in the lab-sotashimozono organization"). Only
  # meaningful for PRIVATE repos — a public repo's workflows are already callable by anyone.
  if [ "$vis" = private ]; then
    if gh api -X PUT "/repos/$ORG/$repo/actions/permissions/access" -f access_level=organization >/dev/null 2>&1; then
      echo "   actions access = organization"
    else
      echo "   actions access FAILED"
    fi
  fi
  has "$repo" FormatCheck.yml  && echo "   FormatCheck  present" || echo "   FormatCheck  MISSING -> init-repo.sh $repo $vis"
  has "$repo" AutoRegister.yml && echo "   AutoRegister present" || echo "   AutoRegister absent (ok for apps/experiments — not registrable)"
done < "$MANIFEST"

echo "== done =="

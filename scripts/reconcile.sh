#!/usr/bin/env bash
# Idempotent per-repo reconcile for lab-sotashimozono. THE single implementation —
# `setup.sh` and the `Reconcile repos` workflow both delegate here so a fix lands in one place.
#
#   scripts/reconcile.sh                    # every repo in the org (except .github)
#   scripts/reconcile.sh ITensorAD.jl       # just these
#   DRY_RUN=1 scripts/reconcile.sh          # report only, change nothing
#
# Repos are DISCOVERED from the org API, not read from repos.tsv: a repository created five
# minutes ago is then reconciled with no manifest edit, which is the whole point. repos.tsv
# stays as documentation of intent.
#
# ── The Free-plan fact this exists to work around (measured 2026-07-26, not guessed) ────────
# Organization Actions secrets are delivered to PUBLIC repositories ONLY. Probes:
#   public  lab-sotashimozono/.github     → BOT_PAT length 40
#   private lab-sotashimozono/skeleton.jl → BOT_PAT length  0, CODECOV_TOKEN length 0
# So `secrets: inherit` silently hands a PRIVATE repo an EMPTY string, and anything authored
# with it quietly falls back to github.token — which is exactly why BOT_PAT-authored PRs and
# tags were not triggering downstream workflows. The token was never "empty"; it was never
# delivered.
#
# The only place org secrets can be read on this plan is the PUBLIC `.github` repo. That makes
# this script's other job SECRET DISTRIBUTION: copy each org secret into every private repo as
# a repository secret, where it IS visible. Values arrive through the environment (the workflow
# passes them in); this script never reads, logs, or stores a secret value.
#
# ── What needs a token this script cannot have ──────────────────────────────────────────────
# BOT_PAT carries scope `repo` only — enough for repository settings and secrets, NOT enough to
# push files under `.github/workflows/` (that needs `workflow`). Stamping the org's caller
# workflows into a repo therefore stays a LOCAL step: `scripts/init-repo.sh <repo> <vis>`,
# run with your own gh login. This script reports which repos still need it.
set -uo pipefail

ORG=lab-sotashimozono
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN="${DRY_RUN:-}"

# Org secrets to push down into private repos. Each name must also be present in the
# environment (the workflow maps `secrets.<NAME>` to `<NAME>`); a name whose environment value
# is absent or implausibly short is SKIPPED loudly rather than distributing a placeholder.
DISTRIBUTE="${DISTRIBUTE:-BOT_PAT CODECOV_TOKEN}"
MIN_SECRET_LEN="${MIN_SECRET_LEN:-16}"

gh auth status >/dev/null 2>&1 || { echo "gh not authenticated"; exit 1; }

say() { printf '%s\n' "$*"; }

# Every field is read through `gh api --jq` — gh embeds jq, so this runs identically on a
# GitHub-hosted runner and on a box with no jq installed. (It did not, once: a bare `jq` left
# `private` EMPTY, every repo was treated as public, and the private-only steps were skipped
# without a word. Silence is the failure mode to design against here.)

# ── Which repos ──────────────────────────────────────────────────────────────────────────
if [ "$#" -gt 0 ]; then
  REPOS=("$@")
else
  mapfile -t REPOS < <(gh api "/orgs/$ORG/repos?per_page=100" --paginate \
    --jq '.[] | select(.name != ".github") | .name' | sort)
fi
say "== org=$ORG  plan=$(gh api "/orgs/$ORG" -q .plan.name 2>/dev/null || echo unknown)  repos=${#REPOS[@]} ${DRY_RUN:+(DRY RUN)} =="

# ── Which secrets are actually distributable ─────────────────────────────────────────────
DISTRIBUTABLE=()
for name in $DISTRIBUTE; do
  value="${!name:-}"
  if [ -z "$value" ]; then
    say "!! $name: not in the environment — skipping distribution (run this from the workflow, or export it)"
  elif [ "${#value}" -lt "$MIN_SECRET_LEN" ]; then
    say "!! $name: value is ${#value} chars, below MIN_SECRET_LEN=$MIN_SECRET_LEN — refusing to distribute a placeholder"
  else
    DISTRIBUTABLE+=("$name")
  fi
done
say "== distributing: ${DISTRIBUTABLE[*]:-(none)} =="

needs_stamping=()
still_template=()

for repo in "${REPOS[@]}"; do
  meta=$(gh api "/repos/$ORG/$repo" --jq '[.private, .allow_auto_merge, .archived] | @tsv' 2>/dev/null) || {
    say "-- $repo: UNREADABLE (permissions?)"; continue; }
  IFS=$'\t' read -r private automerge archived <<<"$meta"
  if [ "$private" != true ] && [ "$private" != false ]; then
    say "-- $repo: could not read visibility (got '${private}') — SKIPPING rather than guessing"
    continue
  fi
  [ "$archived" = true ] && { say "-- $repo: archived, skipping"; continue; }
  say "-- $repo ($([ "$private" = true ] && echo private || echo public))"

  # 1. Auto-merge — AutoMerge.yml is inert without it.
  if [ "$automerge" = true ]; then
    say "   auto-merge already on"
  elif [ -n "$DRY_RUN" ]; then
    say "   auto-merge WOULD be enabled"
  elif gh api -X PATCH "/repos/$ORG/$repo" -F allow_auto_merge=true >/dev/null 2>&1; then
    say "   auto-merge enabled"
  else
    say "   auto-merge FAILED"
  fi

  # 2. Let this repo's own workflows be called from elsewhere in the org. Public repos are
  #    callable by definition, so this is a private-only setting.
  if [ "$private" = true ]; then
    current=$(gh api "/repos/$ORG/$repo/actions/permissions/access" --jq .access_level 2>/dev/null)
    if [ "$current" = organization ]; then
      say "   actions access already organization"
    elif [ -n "$DRY_RUN" ]; then
      say "   actions access WOULD become organization (is ${current:-unknown})"
    elif gh api -X PUT "/repos/$ORG/$repo/actions/permissions/access" -f access_level=organization >/dev/null 2>&1; then
      say "   actions access = organization (was ${current:-unknown})"
    else
      say "   actions access FAILED"
    fi
  fi

  # 3. Secret distribution — the Free-plan workaround. Private repos only: a public repo
  #    already receives the org secret directly, and writing a copy would only add drift.
  if [ "$private" = true ] && [ "${#DISTRIBUTABLE[@]}" -gt 0 ]; then
    for name in "${DISTRIBUTABLE[@]}"; do
      # Value goes in on STDIN, never as an argument: `--body "$value"` would put the secret
      # in the process's argv, readable from /proc by anything else on the runner. gh reads
      # the value from stdin when --body is omitted. Nothing here ever prints the value —
      # only its name and the outcome — and a secret is write-only once stored, so it stays a
      # black box end to end.
      if [ -n "$DRY_RUN" ]; then
        say "   secret $name WOULD be set"
      elif printf '%s' "${!name}" | gh secret set "$name" --repo "$ORG/$repo" >/dev/null 2>&1; then
        say "   secret $name set"
      else
        say "   secret $name FAILED"
      fi
    done
  fi

  # 4. Branch protection. Plan-gated on Free for private repos; apply-ruleset.sh reports that
  #    rather than failing, so a Team upgrade needs no change here.
  "$HERE/apply-ruleset.sh" "$repo" 2>/dev/null || say "   ruleset FAILED"

  # 5. Health: has the repo adopted the org workflows, and did the template bootstrap run?
  gh api "/repos/$ORG/$repo/contents/.github/workflows/FormatCheck.yml" >/dev/null 2>&1 \
    || needs_stamping+=("$repo")
  gh api "/repos/$ORG/$repo/contents/src/MyModule.jl" >/dev/null 2>&1 \
    && still_template+=("$repo")
done

say ""
say "== summary =="
if [ "${#still_template[@]}" -gt 0 ]; then
  say "!! STILL UNINITIALIZED (placeholder module + THIS TEMPLATE'S UUID — they collide with each other):"
  for r in "${still_template[@]}"; do say "     $r  → Actions ▸ Template bootstrap ▸ Run workflow"; done
fi
if [ "${#needs_stamping[@]}" -gt 0 ]; then
  say "!! missing the org caller workflows (needs \`workflow\` scope ⇒ run LOCALLY):"
  for r in "${needs_stamping[@]}"; do say "     scripts/init-repo.sh $r <public|private>"; done
fi
[ "${#still_template[@]}" -eq 0 ] && [ "${#needs_stamping[@]}" -eq 0 ] && say "   all repos initialized and stamped"
say "== done =="

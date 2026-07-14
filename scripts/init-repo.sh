#!/usr/bin/env bash
# Stamp the lab org-default workflows into a member repo via a PR.
#   Usage: init-repo.sh <repo> <private|public>
#
# Stamps only what the org actually owns as reusables:
#   FormatCheck.yml   → reusable format-check (JuliaFormatter v2; rosina for private)
#   CompatHelper.yml  → reusable compathelper (BOT_PAT-authored PRs, so CI triggers)
#   AutoRegister.yml  → reusable autoregister (public → @JuliaRegistrator / private → tag)
#   dependabot.yml    → weekly GitHub-Actions bumps
#
# NOT stamped: the test CI. It is genuinely per-repo (rosina juliaup + throwaway test env
# vs hosted matrix), so each repo keeps its own CI.yml — do not try to unify it.
# Apps/experiments that are not registrable packages: delete AutoRegister.yml afterwards.
set -euo pipefail
ORG=lab-sotashimozono
REPO="${1:?usage: init-repo.sh <repo> <private|public>}"
VIS="${2:?usage: init-repo.sh <repo> <private|public>}"
case "$VIS" in private|public) ;; *) echo "vis must be private|public"; exit 2;; esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$HERE/../templates"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

gh repo clone "$ORG/$REPO" "$WORK/$REPO" -- --depth 1
cd "$WORK/$REPO"
git checkout -b chore/adopt-org-workflows

mkdir -p .github/workflows
cp "$TPL/FormatCheck.$VIS.yml" .github/workflows/FormatCheck.yml
cp "$TPL/CompatHelper.yml"     .github/workflows/CompatHelper.yml
cp "$TPL/AutoRegister.yml"     .github/workflows/AutoRegister.yml
cp "$TPL/dependabot.yml"       .github/dependabot.yml

git add .github
git commit -m "ci: adopt lab org reusable workflows (format-check, compathelper, autoregister)"
git push -u origin chore/adopt-org-workflows
gh pr create --base main --fill
echo "Opened org-workflow adoption PR for $ORG/$REPO ($VIS)"

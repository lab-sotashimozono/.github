#!/usr/bin/env bash
# Stamp lab CI + CompatHelper + Dependabot into a member repo via a PR.
# Usage: init-repo.sh <repo> <private|public>
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
git checkout -b chore/ci-bootstrap

mkdir -p .github/workflows
cp "$TPL/ci.$VIS.yml"      .github/workflows/ci.yml
cp "$TPL/compathelper.yml" .github/workflows/compathelper.yml
cp "$TPL/dependabot.yml"   .github/dependabot.yml

git add .github
git commit -m "ci: adopt lab reusable workflows + CompatHelper + Dependabot"
git push -u origin chore/ci-bootstrap
gh pr create --base main --fill
echo "Opened CI bootstrap PR for $ORG/$REPO ($VIS)"

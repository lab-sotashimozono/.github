#!/usr/bin/env bash
# KEPT as the manifests recovery tool: `manifests` branches on PRIVATE repos cannot be
# branch-protected on GitHub Free, so if one is ever deleted/rewritten, regenerate it with this
# (deps are pinned to each release-time commit; going-forward snapshots are automatic via
# manifest-snapshot.yml). Usage: bash backfill_manifests.sh <owner/repo>
# backfill_manifests.sh <owner/repo>
# Reconstruct PAST releases' Manifest.toml (internal git [sources] deps pinned to the commit that was
# their main-HEAD at each release's time) and push to the `manifests` orphan branch. Registry deps
# resolve to current (bounded by [compat]); transitive-internal deps are pinned only at the top level.
set -uo pipefail
REPO="$1"; ORG="${REPO%%/*}"
export JULIA_PKG_PRECOMPILE_AUTO=0
CLONE=$(mktemp -d); git clone -q "https://github.com/$REPO.git" "$CLONE"; cd "$CLONE"
# existing manifests-branch versions (skip those)
existing=""
if git ls-remote --exit-code --heads origin manifests >/dev/null 2>&1; then
  git fetch -q --depth=1 origin manifests
  existing=$(git ls-tree -r --name-only FETCH_HEAD | grep -oE '^v[^/]+' | sort -u)
fi
tags=$(gh release list --repo "$REPO" --json tagName -q '.[].tagName' 2>/dev/null | grep -E '^v[0-9]' | sort -V)
[ -z "$tags" ] && { echo "no release tags"; exit 0; }
declare -a NEWVERS=()
for tag in $tags; do
  VER="${tag#v}"
  if printf '%s\n' "$existing" | grep -qx "v$VER"; then echo "== $tag already snapshotted — skip"; continue; fi
  TS=$(gh api "repos/$REPO/commits/$tag" --jq '.commit.committer.date' 2>/dev/null)
  echo "== $tag (v$VER) @ $TS =="
  proj=$(mktemp -d)
  git show "$tag:Project.toml" > "$proj/Project.toml" 2>/dev/null || { echo "  no Project.toml at $tag"; continue; }
  # pin each internal (ORG) git [sources] dep to its main commit at TS
  for url in $(grep -oE "https://github.com/$ORG/[A-Za-z0-9_.-]+\.jl" "$proj/Project.toml" | sort -u); do
    dep="${url##*/}"
    sha=$(gh api "repos/$ORG/$dep/commits?sha=main&until=$TS&per_page=1" --jq '.[0].sha' 2>/dev/null)
    [ -z "$sha" ] && { echo "  WARN no $dep commit <= $TS"; continue; }
    echo "  pin $dep -> ${sha:0:8}"
    sed -i "s|\($dep\"[^}]*rev = \"\)main\"|\1$sha\"|" "$proj/Project.toml"
  done
  ( cd "$proj" && rm -f Manifest.toml && timeout 400 julia --startup-file=no -e 'using Pkg; Pkg.activate("."); Pkg.instantiate()' >/dev/null 2>&1 )
  [ -f "$proj/Manifest.toml" ] || { echo "  FAILED to produce Manifest"; continue; }
  mkdir -p "$CLONE/.mfsnap/v$VER"; cp "$proj/Manifest.toml" "$CLONE/.mfsnap/v$VER/Manifest.toml"
  NEWVERS+=("v$VER")
  echo "  captured v$VER/Manifest.toml"
done
[ ${#NEWVERS[@]} -eq 0 ] && { echo "nothing new to snapshot"; exit 0; }
# push all captured to the manifests branch
work=$(mktemp -d); cd "$work"; git init -q
git config user.name "github-actions[bot]"; git config user.email "github-actions[bot]@users.noreply.github.com"
if git ls-remote --exit-code --heads "https://github.com/$REPO.git" manifests >/dev/null 2>&1; then
  git fetch -q --depth=1 "https://github.com/$REPO.git" manifests && git checkout -q FETCH_HEAD
fi
for v in "${NEWVERS[@]}"; do mkdir -p "$v"; cp "$CLONE/.mfsnap/$v/Manifest.toml" "$v/Manifest.toml"; git add "$v/Manifest.toml"; done
git commit -q -m "manifest: backfill snapshots for ${NEWVERS[*]} (deps pinned to release-time commits)"
git push -q "https://github.com/$REPO.git" HEAD:manifests
echo "pushed backfilled snapshots: ${NEWVERS[*]}"

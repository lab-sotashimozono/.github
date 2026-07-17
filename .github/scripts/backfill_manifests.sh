#!/usr/bin/env bash
# backfill_manifests.sh <owner/repo>  — reconstruct PAST releases' Manifest.toml with internal
# git [sources] deps pinned to the commit that was their main-HEAD at each release's time, and push to
# the `manifests` orphan branch. Robust: handles inline AND [sources.X] table format, and any github
# owner (lab-sotashimozono OR personal), via a TOML-aware pinning pass. rev=<tag> sources are left as-is
# (already pinned). Registry deps resolve to current (bounded by [compat]).
set -uo pipefail
REPO="$1"; ORG="${REPO%%/*}"
export JULIA_PKG_PRECOMPILE_AUTO=0
CLONE=$(mktemp -d); git clone -q "https://github.com/$REPO.git" "$CLONE"; cd "$CLONE"
existing=""
if git ls-remote --exit-code --heads origin manifests >/dev/null 2>&1; then
  git fetch -q --depth=1 origin manifests
  existing=$(git ls-tree -r --name-only FETCH_HEAD | grep -oE '^v[^/]+' | sort -u)
fi
tags=$(gh release list --repo "$REPO" --json tagName,isDraft -q '.[]|select(.isDraft==false)|.tagName' 2>/dev/null | grep -E '^v[0-9]' | sort -V)
[ -z "$tags" ] && { echo "no release tags"; exit 0; }
declare -a NEWVERS=()
for tag in $tags; do
  VER="${tag#v}"
  printf '%s\n' "$existing" | grep -qx "v$VER" && { echo "== $tag already snapshotted — skip"; continue; }
  TS=$(gh api "repos/$REPO/commits/$tag" --jq '.commit.committer.date' 2>/dev/null)
  echo "== $tag (v$VER) @ $TS =="
  proj=$(mktemp -d)
  git show "$tag:Project.toml" > "$proj/Project.toml" 2>/dev/null || { echo "  no Project.toml"; continue; }
  # TOML-aware pin: every [sources] entry with rev="main" -> its repo's commit at TS (any owner/format)
  ( cd "$proj" && TS="$TS" julia --startup-file=no -e '
      using TOML
      ts = ENV["TS"]; p = TOML.parsefile("Project.toml")
      srcs = get(p, "sources", nothing); srcs === nothing && exit(0)
      for (name, s) in srcs
        (s isa AbstractDict && get(s,"rev","")=="main" && haskey(s,"url")) || continue
        m = match(r"github\.com[/:]([^/]+)/(.+?)(?:\.git)?$", strip(String(s["url"])))
        m === nothing && continue
        owner, repo = m.captures[1], m.captures[2]
        u = "repos/$owner/$repo/commits?sha=main&until=$ts&per_page=1"
        sha = strip(read(Cmd(["gh","api",u,"--jq",".[0].sha"]), String))
        isempty(sha) && continue
        s["rev"] = sha
        println(stderr, "  pin $name ($owner/$repo) -> ", first(sha,8))
      end
      open(io->TOML.print(io,p), "Project.toml","w")
    ' )
  ( cd "$proj" && rm -f Manifest.toml && timeout 400 julia --startup-file=no -e 'using Pkg; Pkg.activate("."); Pkg.instantiate()' >/dev/null 2>&1 )
  [ -f "$proj/Manifest.toml" ] || { echo "  FAILED to produce Manifest"; continue; }
  mkdir -p "$CLONE/.mfsnap/v$VER"; cp "$proj/Manifest.toml" "$CLONE/.mfsnap/v$VER/Manifest.toml"; NEWVERS+=("v$VER")
  echo "  captured v$VER/Manifest.toml"
done
[ ${#NEWVERS[@]} -eq 0 ] && { echo "nothing new"; exit 0; }
work=$(mktemp -d); cd "$work"; git init -q
git config user.name "github-actions[bot]"; git config user.email "github-actions[bot]@users.noreply.github.com"
git ls-remote --exit-code --heads "https://github.com/$REPO.git" manifests >/dev/null 2>&1 && \
  { git fetch -q --depth=1 "https://github.com/$REPO.git" manifests && git checkout -q FETCH_HEAD; }
for v in "${NEWVERS[@]}"; do mkdir -p "$v"; cp "$CLONE/.mfsnap/$v/Manifest.toml" "$v/Manifest.toml"; git add "$v/Manifest.toml"; done
git commit -q -m "manifest: backfill ${NEWVERS[*]} (deps pinned to release-time commits, TOML-aware)"
git push -q "https://github.com/$REPO.git" HEAD:manifests
echo "pushed: ${NEWVERS[*]}"

# lab-sotashimozono/.github

Org-level defaults for **lab-sotashimozono** (private research + public spin-offs).

This repo is GitHub's special `.github` repository: it hosts the org profile,
**reusable workflows**, **starter workflows**, and the scripts that apply
org-wide **branch-protection rulesets** and bootstrap CI into member repos.

## Initialize / reconcile

Run as an **org admin** (nothing here beats the plan gate — see below):

```bash
BOT_PAT=<token> scripts/setup.sh     # apply ruleset + sync BOT_PAT secret + report
scripts/setup.sh                     # settings only (skip secret sync)
```

`setup.sh` is **idempotent** and **declarative**: it reads `repos.tsv`, applies a
**repo-level ruleset** to each, syncs the `BOT_PAT` secret, and reports which repos
still need CI. To onboard a repo: add a line to `repos.tsv`, rerun `setup.sh`, then
for its workflows run once:

```bash
scripts/init-repo.sh <repo> <public|private>   # opens a chore/ci-bootstrap PR
```

### Branch protection on Free

Branch protection uses **repository rulesets** (`/repos/{o}/{r}/rulesets`), which
work on Free — including private repos. The **org-level** ruleset endpoint would
need Team, so we deliberately apply per-repo (the `setup.sh` loop does this, still
one command). If a specific ruleset apply is refused, `setup.sh` reports it and
keeps going instead of aborting.

## Layout

```
repos.tsv                             declarative repo manifest (name + visibility)
profile/README.md                     org profile (public landing)
.github/workflows/julia-ci.yml        reusable: test + JuliaFormatter v2
.github/workflows/compathelper.yml    reusable: CompatHelper (compat bump PRs)
.github/workflow-templates/           "New workflow" UI starters
rulesets/protect-default.json         org branch-protection ruleset (structural)
scripts/setup.sh                      idempotent org init (run this)
scripts/apply-ruleset.sh              create/update the ruleset (called by setup.sh)
scripts/init-repo.sh <repo> <vis>     stamp CI+CompatHelper+Dependabot into a repo
templates/                            per-repo caller files init-repo.sh copies
```

## CI runner policy (security)

- **private repos → self-hosted (rosina)** via `runs-on: [self-hosted, rosina]`.
- **public repos → GitHub-hosted** (`ubuntu-latest`). Never self-hosted:
  fork PRs would run arbitrary code on rosina.
- Hard-enforced by the `Rosina` runner group ("Allow public repositories" = OFF).
  Even a mistaken `runs-on: self-hosted` in a public repo cannot reach rosina.

## One-command adoption per repo

```
scripts/init-repo.sh QAtlas.jl public     # hosted CI
scripts/init-repo.sh SomeResearch.jl private  # rosina CI
```

Opens a `chore/ci-bootstrap` PR; the org ruleset lets the org admin merge it.

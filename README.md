# lab-sotashimozono/.github

Org-level defaults for **lab-sotashimozono** (private research + public spin-offs).

GitHub's special `.github` repository: org profile, the **reusable workflows** every member repo
calls, and the scripts that apply the org's **branch-protection rulesets** and stamp the defaults
into a repo.

## Reusable workflows (what the org actually owns)

| reusable | what it does | callers pass |
|---|---|---|
| `format-check.yml` | JuliaFormatter **v2** check — the formatter version is pinned here, once, fleet-wide | `runner` (private → `["self-hosted","rosina"]`, public → `"ubuntu-latest"`) |
| `compathelper.yml` | `[compat]` bump PRs, authored by **BOT_PAT** so the PR triggers CI | `secrets: inherit` |
| `autoregister.yml` | on a `Project.toml` version bump: **public → `@JuliaRegistrator`** (General); **private → push `vX.Y.Z` tag** (fires PublishRelease) | `secrets: inherit` |
| `documentation.yml` | Documenter build + deploy + PR preview, with the **deploy target as an input** — `gh-pages` (Documenter pushes the branch) or `path` (copy the site to a directory on a self-hosted runner, i.e. host the docs on the box) | `runner`, `target`, `path-dest`, `preview-base-url` |
| `docs-cleanup-preview.yml` | delete `previews/PR<n>` when the PR closes, from the gh-pages branch or from the runner directory | `runner`, `target`, `path-dest` |

> **Docs hosting, honestly:** on the org's **Free** plan a **private** repo's GitHub Pages site is
> *built but not served* — `https://lab-sotashimozono.github.io/<PrivateRepo>/` returns **404**. So for
> the private repos `target: 'gh-pages'` only archives the site in the branch; nothing is readable.
> `target: 'path'` is the way out: the rosina runner copies the built site to `path-dest` and the box
> hosts it, with no public exposure and no credentials — the docs never leave the machine. The
> workflows take the target as an input precisely so that switch is two lines in the caller.

**The test CI is deliberately NOT here.** It is genuinely per-repo (private repos run rosina +
juliaup + a throwaway test env because `Pkg.test()` trips a Julia-1.12 depot quirk; public repos
run a hosted OS/version matrix). Each repo keeps its own `CI.yml`. Don't try to unify it.

## CI runner policy (security)

- **private → self-hosted rosina** — a single shared **org pool** (runner group `Rosina`,
  label `rosina`), provisioned by `infra/self-hosted-runners/runner-setup-org.sh`.
- **public → GitHub-hosted** (`ubuntu-latest`). Never self-hosted: a fork PR would run
  arbitrary code on rosina. Hard-enforced — the `Rosina` group has *Allow public repositories*
  **off**, so a public repo cannot reach the pool even if a workflow asks for it.

## Secrets — the Free-plan trap (measured, not guessed)

**Organization Actions secrets are delivered to PUBLIC repositories only.** Probed 2026-07-26 by
printing secret *lengths* in both kinds of repo:

| repo | visibility | `BOT_PAT` | `CODECOV_TOKEN` |
|---|---|---|---|
| `.github` | public | **40** | 1 |
| `skeleton.jl` | private | **0** | **0** |

So `secrets: inherit` hands a **private** repo an **empty string**, and every step that meant to
author something "as BOT_PAT" silently fell back to `github.token` — which is precisely why
BOT_PAT-authored PRs and private release tags were not triggering downstream workflows. The token
was never empty (it is a real 40-char PAT, scope `repo`); it was never *delivered*.

Two consequences the rest of this repo is built around:

1. **`.github` is the org's only public repo, so it is the only place a workflow can read an org
   secret.** That is what makes `Reconcile repos` (below) possible at all.
2. **Every private repo needs its own copy** of each secret. `reconcile.sh` writes them, so this
   is maintained rather than remembered.

> `CODECOV_TOKEN` at the org level is currently a **1-character placeholder**, so it is refused
> for distribution (`MIN_SECRET_LEN`) rather than copied across the fleet. Set it to the real
> Codecov org upload token and the next reconcile propagates it. Until then each private repo
> needs its own `CODECOV_TOKEN`, which is why they already have one.

## Initialize / reconcile

Automatic: **`Reconcile repos`** (`.github/workflows/reconcile.yml`) runs daily, and on demand via
**Actions ▸ Reconcile repos ▸ Run workflow** — use that right after creating a repository, with
`dry-run` first if you want to see the diff. Repos are **discovered from the org API**, so a
repository created five minutes ago is picked up with no manifest edit.

Same thing locally, as an **org admin**:

```bash
scripts/setup.sh                              # every repo in the org
scripts/setup.sh ITensorAD.jl                 # just one
DRY_RUN=1 scripts/setup.sh                    # report only
BOT_PAT=… CODECOV_TOKEN=… scripts/setup.sh    # also distribute secrets (see above)
```

`setup.sh` is a thin wrapper over `scripts/reconcile.sh`, which the workflow runs verbatim — one
implementation, so the automated pass and your local pass cannot drift.

Per repo it reconciles: **auto-merge on**, **Actions access = organization** (private), **org
secrets distributed** (private), **branch-protection ruleset** (plan-gated, see below), and
reports two health facts — repos still carrying the template placeholder, and repos that have not
adopted the org caller workflows.

**Stamping the caller workflows stays local.** It pushes files under `.github/workflows/`, which
needs a token with the `workflow` scope; BOT_PAT has `repo` only, so the workflow cannot do it and
says so instead of failing silently:

```bash
scripts/init-repo.sh <repo> <public|private>   # opens a chore/adopt-org-workflows PR
```

### Branch protection — the plan gate (verified, not guessed)

Protection uses **repository rulesets** (`/repos/{o}/{r}/rulesets`); rules: no deletion, no
force-push, linear history, PR required (0 approvals), with **OrganizationAdmin bypass** so you
can still bootstrap/hotfix directly.

| | **Free** (today) | **Team** |
|---|---|---|
| public repo | ✅ applied | ✅ |
| private repo | ❌ `403 Upgrade to GitHub Pro or make this repository public` | ✅ |

An admin token applies *settings*; it cannot bypass a *plan gate*. So today only the 3 public
repos are protected — the 15 private ones have **no server-side branch protection**. Upgrading
the org to Team needs **no change** to `setup.sh`: rerun it and every private repo picks the
ruleset up. Until then, treat main on private repos as convention-protected (the admin bypass
would have made it advisory for you anyway).

## Layout

```
repos.tsv                              repo manifest — documentation of intent; reconcile
                                       discovers repos from the org API instead
profile/README.md                      org profile (public landing)
.github/workflows/reconcile.yml        settings + secret distribution (daily / on demand)
.github/workflows/template-bootstrap.yml  reusable: initialize a repo made from skeleton.jl
.github/workflows/format-check.yml     reusable: JuliaFormatter v2
.github/workflows/compathelper.yml     reusable: [compat] bump PRs
.github/workflows/autoregister.yml     reusable: register (public) / tag (private)
.github/workflows/documentation.yml    reusable: Documenter build/deploy/preview (target: gh-pages | path)
.github/workflows/docs-cleanup-preview.yml  reusable: tear a PR preview down
rulesets/protect-default.json          branch-protection ruleset
scripts/reconcile.sh                   THE implementation (workflow + setup.sh both run it)
scripts/setup.sh                       thin local wrapper over reconcile.sh (run this)
scripts/apply-ruleset.sh <repo>        create/update one repo's ruleset
scripts/init-repo.sh <repo> <vis>      stamp the org workflows into a repo (needs `workflow` scope)
templates/                             the per-repo caller files init-repo.sh copies
```

## Creating a new package repository

1. **Use this template** on `skeleton.jl`.
2. Nothing else — `Template bootstrap` renames the placeholder module after the repository,
   assigns a **fresh UUID** (without which every generated package shares the template's UUID and
   they collide), and sets the version to 0.1.0 on the first push to `main`.
3. **Actions ▸ Reconcile repos ▸ Run workflow** for the settings and secrets immediately,
   or leave it to the daily pass.
4. Once, locally: `scripts/init-repo.sh <repo> <public|private>` for the caller workflows.

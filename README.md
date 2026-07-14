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

## Secrets

`BOT_PAT` is an **org** Actions secret with `visibility=all`, so every repo — private included —
gets it through `secrets: inherit`. It is what makes CompatHelper PRs and private release tags
trigger downstream workflows (a `GITHUB_TOKEN`-authored PR/tag does not).

## Initialize / reconcile

Run as an **org admin**:

```bash
scripts/setup.sh                 # every repo in repos.tsv
scripts/setup.sh ITensorAD.jl    # just one
```

Idempotent and declarative: reads `repos.tsv`, applies each repo's branch-protection ruleset, and
reports which repos still need the org workflows. To onboard a repo: add a line to `repos.tsv`,
rerun `setup.sh`, then stamp its workflows once:

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
repos.tsv                              declarative repo manifest (name + visibility)
profile/README.md                      org profile (public landing)
.github/workflows/format-check.yml     reusable: JuliaFormatter v2
.github/workflows/compathelper.yml     reusable: [compat] bump PRs
.github/workflows/autoregister.yml     reusable: register (public) / tag (private)
.github/workflows/documentation.yml    reusable: Documenter build/deploy/preview (target: gh-pages | path)
.github/workflows/docs-cleanup-preview.yml  reusable: tear a PR preview down
rulesets/protect-default.json          branch-protection ruleset
scripts/setup.sh                       idempotent org init (run this)
scripts/apply-ruleset.sh <repo>        create/update one repo's ruleset
scripts/init-repo.sh <repo> <vis>      stamp the org workflows into a repo
templates/                             the per-repo caller files init-repo.sh copies
```

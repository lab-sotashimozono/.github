# Release reproducibility — restoring a release's exact dependencies

Internal lab dependencies are pinned by `rev="main"` in each package's `Project.toml` `[sources]`.
That does **not** freeze a commit: resolving later fetches *current* `main`, not the state a release was
built against. To make releases reproducible without per-dependency `rev` pinning (a maintenance
burden), the **`ManifestSnapshot`** workflow — reusable
[`.github/workflows/manifest-snapshot.yml`](.github/workflows/manifest-snapshot.yml), called by each
package's `.github/workflows/ManifestSnapshot.yml` — resolves the project on every **version bump** and
commits the fully-pinned `Manifest.toml` (each dependency pinned by its exact `git-tree-sha1`) to the
package's **`manifests` orphan branch** at `v<version>/Manifest.toml`.

## Restore the exact dependency state of release `v<version>`

```bash
git checkout v<version>                                              # the release tag
git fetch origin manifests
git show origin/manifests:v<version>/Manifest.toml > Manifest.toml   # the pinned snapshot
julia --project=. -e 'using Pkg; Pkg.instantiate()'                  # fetch the pinned upstream commits
```

`Pkg.instantiate()` reads the Manifest's `git-tree-sha1` for every git dependency, so it checks out the
**exact upstream commit recorded at release time** — regardless of where `main` points now. (The commit
must still exist; since `main` only moves forward, it always does.)

## Notes

- Runs on the **rosina** self-hosted runner (only it can fetch the private `[sources]` deps).
- Needs no secret beyond `GITHUB_TOKEN` (own-repo push to the orphan branch).
- `Manifest.toml` stays gitignored on `main`; only the `manifests` branch holds the release snapshots.
- Browse a package's snapshots at `https://github.com/lab-sotashimozono/<pkg>/tree/manifests`.

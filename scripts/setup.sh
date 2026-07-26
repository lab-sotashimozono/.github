#!/usr/bin/env bash
# One-shot, idempotent org initialization. Run as an org admin (gh auth logged in).
#
#   scripts/setup.sh                 # every repo in the org
#   scripts/setup.sh ITensorAD.jl    # just one
#
# This is a THIN WRAPPER. The implementation is scripts/reconcile.sh, shared verbatim with the
# `Reconcile repos` workflow, so the automated pass and your local pass can never drift apart.
# Run this when you want an answer now; the workflow runs it daily as the safety net, and
# manually via Actions ▸ Reconcile repos ▸ Run workflow right after creating a repository.
#
# Two differences when running locally rather than from the workflow:
#
#   * SECRET DISTRIBUTION IS SKIPPED unless you export the values. On the Free plan an
#     organization secret is delivered to PUBLIC repositories only, so every private repo needs
#     its own copy — which is what reconcile.sh writes. It reads the values from the
#     environment and never logs them:
#
#         BOT_PAT=… CODECOV_TOKEN=… scripts/setup.sh
#
#     Without them it says so per secret and reconciles everything else.
#
#   * STAMPING the org caller workflows into a repo is still a separate, local step —
#     `scripts/init-repo.sh <repo> <public|private>` — because it pushes files under
#     .github/workflows/, which needs a token with the `workflow` scope (BOT_PAT has `repo`
#     only). reconcile.sh lists the repos that still need it.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/reconcile.sh" "$@"

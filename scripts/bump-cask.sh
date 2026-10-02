#!/bin/bash
# The ai-pet-usage cask bump, run by .github/workflows/bump-cask.yml. A script (not inline workflow YAML) so its whole
# behavior is testable: scripts/test-bump.sh runs it end-to-end against a stubbed gh / curl and a throwaway git repo.
#
#   bump-cask.sh        env: REPO (default F-e-u-e-r/ai-pet-usage), CASK (default Casks/ai-pet-usage.rb),
#                            RUNNER_TEMP (scratch; falls back to TMPDIR, then /tmp); run from the tap's checkout
#
# Selection (select-release.jq; contract = docs/release/VERSIONING.md in the app repo): the highest canonical
# beta / rc / stable release by semantic order, never alpha or legacy alpha-v*, no fallback (none eligible => exit 0,
# cask unchanged). Candidates: every non-draft release, listed with a bound of 1000 (one more is requested: a listing
# over the bound is known to be incomplete, so the run fails instead of selecting from it). Then: exactly one matching
# asset with a well-formed API digest (release-asset.sh), validated before
# the "already current" shortcut (update-cask.sh --check: 0 = current, 1 = rewrite needed, anything else fails); the
# download must match the digest (verify-asset.sh); version / sha256 / url are rewritten together (update-cask.sh);
# commit + push only when the cask actually changed.
set -euo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-F-e-u-e-r/ai-pet-usage}"
CASK="${CASK:-Casks/ai-pet-usage.rb}"
WORK="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/bump.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Bounded listing: one more than the 1000-release bound is requested, so a listing over the bound is KNOWN to be
# incomplete. Selecting from it could pick a lower version or report "no eligible release", so the run fails instead.
gh release list --repo "$REPO" --limit 1001 --exclude-drafts \
    --json tagName,isDraft,isPrerelease,publishedAt > "$WORK/releases.json"
if ! jq -e 'type == "array" and length <= 1000' "$WORK/releases.json" >/dev/null; then
    echo "more than 1000 releases (or not a release list): refusing to select from a partial listing — cask unchanged"
    exit 1
fi
TAG="$(jq -r --arg mode select -f "$HERE/select-release.jq" "$WORK/releases.json")"
if [ -z "$TAG" ]; then
    echo "no eligible canonical release (beta/rc/stable) — cask unchanged; legacy alpha-v* is never selected"
    exit 0
fi
VERSION="${TAG#v}"
ASSET="AI-Pet-Usage-${TAG}-arm64.zip"
URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"

gh api "repos/${REPO}/releases/tags/${TAG}" > "$WORK/release.json"
# exactly one matching asset with a well-formed digest, or the run fails (before any shortcut)
API_SHA="$(bash "$HERE/release-asset.sh" "$WORK/release.json" "$ASSET")"
# --check: 0 = current (nothing to do), 1 = rewrite needed, anything else = invalid cask / input
set +e
bash "$HERE/update-cask.sh" --check "$CASK" "$VERSION" "$API_SHA"
rc=$?
set -e
case $rc in
    0) echo "cask already at ${VERSION}"; exit 0 ;;
    1) ;;
    *) echo "update-cask.sh --check failed (exit $rc)"; exit "$rc" ;;
esac

curl -fsSL "$URL" -o "$WORK/asset.zip"
SHA="$(bash "$HERE/verify-asset.sh" "$WORK/asset.zip" "sha256:${API_SHA}")"
bash "$HERE/update-cask.sh" "$CASK" "$VERSION" "$SHA"
if git diff --quiet -- "$CASK"; then
    echo "cask already at ${VERSION}"
    exit 0
fi
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git commit -m "ai-pet-usage ${VERSION}" -- "$CASK"
git push

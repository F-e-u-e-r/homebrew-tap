#!/bin/bash
# Extracts the GitHub API digest of the release asset the cask points at — the bump's only trust anchor for
# the download. Runs before any shortcut, so a malformed digest can never reach "already current".
#
#   release-asset.sh <release.json> <asset-name>
#       <release.json>: the object returned by `gh api repos/<repo>/releases/tags/<tag>`.
#       Prints the digest's 64 lowercase hex characters and exits 0 when exactly one asset is named
#       <asset-name> and its digest is "sha256:<64 lowercase hex>". Exits 1 otherwise: zero or several
#       matching assets, a missing / null / malformed digest, or JSON that is not a release object.
set -euo pipefail
export LC_ALL=C

die() {
    printf 'release-asset: %s\n' "$1" >&2
    exit 1
}

[ $# -eq 2 ] || { echo "usage: release-asset.sh <release.json> <asset-name>" >&2; exit 2; }
json="$1"
name="$2"
matches="$(jq -c --arg a "$name" '
    if type == "object" and (.assets | type) == "array"
    then [ .assets[] | select(type == "object" and .name == $a) ]
    else error("not a release object") end' "$json" 2>/dev/null)" || die "malformed release JSON"
count="$(jq -r 'length' <<< "$matches")"
[ "$count" = 1 ] || die "expected exactly one asset named $name (found $count)"
# The format check runs inside jq with \A...\z: a shell $(...) would strip a trailing newline and let
# "sha256:<hex>\n" pass.
hex="$(jq -r '.[0].digest | if type == "string" and test("\\Asha256:[0-9a-f]{64}\\z") then .[7:] else "" end' <<< "$matches")"
[[ $hex =~ ^[0-9a-f]{64}$ ]] || die "malformed or missing API digest for $name"
printf '%s\n' "$hex"

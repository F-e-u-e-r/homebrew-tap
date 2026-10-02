#!/bin/bash
# Verifies a downloaded release asset against the GitHub API's asset digest.
#
#   verify-asset.sh <file> <digest>      <digest> exactly as the API returns it: "sha256:<64 lowercase hex>"
#
# Prints the asset's lowercase hex sha256 and exits 0 on a match; exits 1 on a mismatch, a malformed or
# missing digest, or an empty or missing download.
set -euo pipefail
export LC_ALL=C

[ $# -eq 2 ] || { echo "usage: verify-asset.sh <file> <digest>" >&2; exit 2; }
file="$1"
digest="$2"
[[ $digest =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "verify-asset: malformed or missing API digest" >&2; exit 1; }
[ -s "$file" ] || { echo "verify-asset: empty or missing download" >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then
    sum="$(sha256sum "$file" | awk '{print $1}')"
else
    sum="$(shasum -a 256 "$file" | awk '{print $1}')"
fi
[ "sha256:$sum" = "$digest" ] || { echo "verify-asset: downloaded sha256 does not match the GitHub API digest" >&2; exit 1; }
printf '%s\n' "$sum"

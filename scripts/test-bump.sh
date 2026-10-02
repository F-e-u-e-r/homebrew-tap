#!/bin/bash
# Tests for the canonical cask bump: scripts/select-release.jq, scripts/release-asset.sh, scripts/update-cask.sh,
# scripts/verify-asset.sh, scripts/bump-cask.sh (end-to-end against a stubbed gh / curl and a throwaway git repo)
# and the wiring of .github/workflows/bump-cask.yml.
# Vectors: tests/canonical-version-vectors.tsv — a byte-identical copy of
# Sources/usagecore-tests/Fixtures/canonical-version-vectors.tsv in F-e-u-e-r/ai-pet-usage (sha256 pinned below).
# Run: bash scripts/test-bump.sh   (exit 0 = all pass)
set -uo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SEL="$ROOT/scripts/select-release.jq"
UPD="$ROOT/scripts/update-cask.sh"
VER="$ROOT/scripts/verify-asset.sh"
ASSETX="$ROOT/scripts/release-asset.sh"
BUMP="$ROOT/scripts/bump-cask.sh"
CASK="$ROOT/Casks/ai-pet-usage.rb"
WF="$ROOT/.github/workflows/bump-cask.yml"
VECTORS="$ROOT/tests/canonical-version-vectors.tsv"
VECTORS_SHA256="12b6b1d6eeba01ba3d3fd6c41c5f618b59b019bfb7432f9c5fecbd9733539b1b"
for tool in jq ruby git; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'bump tests: FAIL (%s is required)\n' "$tool"; exit 1; }
done
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CASK_SHA_AT_START="$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$CASK"; else shasum -a 256 "$CASK"; fi | awk '{print $1}')"

pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok; else bad "$1: got [$2] want [$3]"; fi; }
sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }

# JSON-encode a raw string (newlines and spaces preserved) so it can be fed to jq as input.
jstr() { jq -Rn --arg s "$1" '$s'; }
parse() { jstr "$1" | jq -c --arg mode parse -f "$SEL"; }
key() { jstr "$1" | jq -c --arg mode key -f "$SEL"; }
select_from() { printf '%s' "$1" | jq -r --arg mode select -f "$SEL"; }
# sel <label> <json> <want>: the selector must exit 0 AND print exactly <want> ("" = no eligible release).
sel() {
    local out rc
    out="$(select_from "$2" 2>/dev/null)"
    rc=$?
    check "$1 (exit)" "$rc" 0
    check "$1" "$out" "$3"
}

split_tsv() {
    local rest="$1"
    F=()
    while [[ $rest == *$'\t'* ]]; do
        F+=("${rest%%$'\t'*}")
        rest="${rest#*$'\t'}"
    done
    F+=("$rest")
}

# ---------------------------------------------------------------- 1. shared vectors (parity with the app)
check "vectors file is the pinned copy" "$(sha256_of "$VECTORS")" "$VECTORS_SHA256"
n_accept=0
n_reject=0
n_order=0
while IFS= read -r line || [ -n "$line" ]; do
    case $line in '' | '#'*) continue ;; esac
    split_tsv "$line"
    input="${F[1]-}"
    input="${input//\\n/$'\n'}"
    case ${F[0]} in
        accept)
            n_accept=$((n_accept + 1))
            iter="${F[4]}"
            [ "$iter" = "-" ] && iter="null"
            IFS=. read -r maj min pat <<< "${F[2]}"
            check "accept [$input]" "$(parse "$input")" \
                "{\"maj\":$maj,\"min\":$min,\"pat\":$pat,\"channel\":\"${F[3]}\",\"iteration\":$iter}"
            ;;
        reject)
            n_reject=$((n_reject + 1))
            check "reject [$input] (${F[2]-})" "$(parse "$input")" "null"
            check "reject key [$input]" "$(key "$input")" "null"
            ;;
        order)
            n_order=$((n_order + 1))
            lo="$(key "$input")"
            hi="$(key "${F[2]}")"
            check "order [$input < ${F[2]}]" "$(jq -n --argjson a "$lo" --argjson b "$hi" '$a < $b and ($b < $a | not)')" "true"
            ;;
        *) bad "unknown vector kind [${F[0]}]" ;;
    esac
done < "$VECTORS"
check "accept vector count" "$n_accept" 15
check "reject vector count" "$n_reject" 47
check "order vector count" "$n_order" 13

# ---------------------------------------------------------------- 2. selection (F6 H1–H9, H14)
R() { printf '{"tagName":"%s","isDraft":%s,"isPrerelease":%s,"publishedAt":"%s"}' "$1" "$2" "$3" "${4:-2026-10-01T00:00:00Z}"; }
sel "H1 canonical beta chosen over legacy" \
    "[$(R alpha-v0.4.0 false true 2026-09-27T17:07:34Z),$(R v0.1.0-beta.1 false true)]" "v0.1.0-beta.1"
sel "H2 only legacy alpha-v* -> nothing (no fallback)" \
    "[$(R alpha-v0.4.0 false true),$(R alpha-v0.3.0 false true),$(R alpha-v9.9.9 false false)]" ""
sel "H2 empty list -> nothing" '[]' ""
sel "H3 numeric iteration order" \
    "[$(R v0.1.0-beta.10 false true),$(R v0.1.0-beta.2 false true),$(R v0.1.0-beta.9 false true)]" "v0.1.0-beta.10"
sel "H4 stable beats its rc" "[$(R v0.1.0-rc.1 false true),$(R v0.1.0 false false)]" "v0.1.0"
sel "H4 rc is eligible on its own" "[$(R v0.1.0-rc.1 false true)]" "v0.1.0-rc.1"
sel "H4 rc beats a beta of the same core" "[$(R v0.1.0-beta.9 false true),$(R v0.1.0-rc.1 false true)]" "v0.1.0-rc.1"
sel "H3 numeric rc iteration order" "[$(R v0.1.0-rc.2 false true),$(R v0.1.0-rc.10 false true)]" "v0.1.0-rc.10"
sel "H5 alpha excluded (stable stays)" "[$(R v0.1.1-alpha.1 false true),$(R v0.1.0 false false)]" "v0.1.0"
sel "H5 alpha-only -> nothing" "[$(R v0.2.0-alpha.1 false true)]" ""
sel "H6 malformed canonical-looking tags ignored" \
    "[$(R v0.1.0-beta.0 false true),$(R v01.0.0 false false),$(R v0.1.0-preview.1 false true),$(R V0.2.0 false false),$(R v0.1.0-beta.1 false true)]" "v0.1.0-beta.1"
sel "H7 drafts ignored" "[$(R v0.2.0 true false),$(R v0.1.0-beta.1 false true)]" "v0.1.0-beta.1"
sel "H7 missing isDraft ignored" '[{"tagName":"v9.9.9","isPrerelease":false},{"tagName":"v0.1.0","isDraft":false,"isPrerelease":false}]' "v0.1.0"
sel "H7 null isDraft ignored" '[{"tagName":"v9.9.9","isDraft":null,"isPrerelease":false}]' ""
sel "H7 string isDraft ignored" '[{"tagName":"v9.9.9","isDraft":"false","isPrerelease":false}]' ""
sel "H7 numeric isDraft ignored" '[{"tagName":"v9.9.9","isDraft":0,"isPrerelease":false}]' ""
sel "H8 stable tag marked prerelease ignored" "[$(R v0.2.0 false true),$(R v0.1.0-beta.1 false true)]" "v0.1.0-beta.1"
sel "H8 beta tag not marked prerelease ignored" "[$(R v0.2.0-beta.1 false false),$(R v0.1.0-beta.1 false true)]" "v0.1.0-beta.1"
sel "H8 rc tag not marked prerelease ignored" "[$(R v0.2.0-rc.1 false false),$(R v0.1.0-rc.1 false true)]" "v0.1.0-rc.1"
sel "H8 missing prerelease flag ignored" '[{"tagName":"v0.3.0","isDraft":false},{"tagName":"v0.1.0-beta.1","isDraft":false,"isPrerelease":true}]' "v0.1.0-beta.1"
sel "H8 string prerelease flag ignored" '[{"tagName":"v0.3.0","isDraft":false,"isPrerelease":"false"}]' ""
sel "H9 version order, not publish time or list order" \
    "[$(R v0.1.1 false false 2026-12-01T00:00:00Z),$(R v0.2.0-beta.1 false true 2026-11-01T00:00:00Z),$(R v0.1.0 false false 2026-10-01T00:00:00Z)]" "v0.2.0-beta.1"
sel "H9 string order is not version order" "[$(R v0.10.0 false false),$(R v0.9.0 false false)]" "v0.10.0"
sel "H14 future stable" "[$(R v0.1.0-rc.2 false true),$(R v0.1.0 false false),$(R v0.1.0-beta.3 false true)]" "v0.1.0"
sel "malformed records ignored (null / number / object / array tagName, non-object entries)" \
    '[null,"v9.9.9",3,{"tagName":null,"isDraft":false,"isPrerelease":false},{"tagName":5,"isDraft":false,"isPrerelease":false},{"tagName":{"a":1},"isDraft":false,"isPrerelease":false},{"tagName":["v1.0.0"],"isDraft":false,"isPrerelease":false},{"tagName":"v0.1.0-beta.1","isDraft":false,"isPrerelease":true}]' \
    "v0.1.0-beta.1"
out="$(select_from '{"tagName":"v9.9.9","isDraft":false,"isPrerelease":false}' 2>/dev/null)"
rc=$?
if [ "$rc" -ne 0 ] && [ -z "$out" ]; then ok; else bad "a non-array input must be an error, not 'no eligible release' (exit $rc, out [$out])"; fi

# ---------------------------------------------------------------- 3. cask rewrite (H10, H11, H13, H14)
SHA_A="$(printf 'a%.0s' $(seq 1 64))"
SHA_B="$(printf 'b%.0s' $(seq 1 64))"
cp "$CASK" "$TMP/cask.rb"
bash "$UPD" --check "$TMP/cask.rb" 0.1.0-beta.1 "$SHA_A"; check "H13 --check before rewrite needs work" "$?" 1
bash "$UPD" "$TMP/cask.rb" 0.1.0-beta.1 "$SHA_A"; check "H11 rewrite exit" "$?" 0
diff "$CASK" "$TMP/cask.rb" > "$TMP/cask.diff"
check "H11 exactly three lines replaced" "$(grep -c '^< ' "$TMP/cask.diff") $(grep -c '^> ' "$TMP/cask.diff")" "3 3"
check "H11 version line" "$(grep -c '^  version "0.1.0-beta.1"$' "$TMP/cask.rb")" 1
check "H11 sha256 line" "$(grep -c "^  sha256 \"$SHA_A\"$" "$TMP/cask.rb")" 1
check "H11 url line is the canonical template" \
    "$(grep -cF '  url "https://github.com/F-e-u-e-r/ai-pet-usage/releases/download/v#{version}/AI-Pet-Usage-v#{version}-arm64.zip",' "$TMP/cask.rb")" 1
check "H11 no legacy alpha-v left" "$(grep -c 'alpha-v' "$TMP/cask.rb")" 0
check "H11 verified: stanza untouched" "$(grep -cF '      verified: "github.com/F-e-u-e-r/ai-pet-usage/"' "$TMP/cask.rb")" 1
url_line="$(grep -E '^  url "' "$TMP/cask.rb")"
url="${url_line#  url \"}"
url="${url%\",}"
check "H10 interpolated URL is mechanically derived from the tag" "${url//\#\{version\}/0.1.0-beta.1}" \
    "https://github.com/F-e-u-e-r/ai-pet-usage/releases/download/v0.1.0-beta.1/AI-Pet-Usage-v0.1.0-beta.1-arm64.zip"
bash "$UPD" --check "$TMP/cask.rb" 0.1.0-beta.1 "$SHA_A"; check "H13 --check after rewrite is current" "$?" 0
cp "$TMP/cask.rb" "$TMP/cask.again.rb"
bash "$UPD" "$TMP/cask.again.rb" 0.1.0-beta.1 "$SHA_A"
if cmp -s "$TMP/cask.rb" "$TMP/cask.again.rb"; then ok; else bad "H13 rewrite is not idempotent"; fi
bash "$UPD" --check "$TMP/cask.rb" 0.1.0-beta.1 "$SHA_B"; check "H13 --check: same version + url, new sha256 (re-upload) needs work" "$?" 1
bash "$UPD" "$TMP/cask.rb" 0.1.0 "$SHA_B"; check "H14 stable rewrite exit" "$?" 0
check "H14 stable version line" "$(grep -c '^  version "0.1.0"$' "$TMP/cask.rb")" 1
check "H14 stable sha256 line" "$(grep -c "^  sha256 \"$SHA_B\"$" "$TMP/cask.rb")" 1
check "H14 stable url line is the canonical template" \
    "$(grep -cF '  url "https://github.com/F-e-u-e-r/ai-pet-usage/releases/download/v#{version}/AI-Pet-Usage-v#{version}-arm64.zip",' "$TMP/cask.rb")" 1
stable_url_line="$(grep -E '^  url "' "$TMP/cask.rb")"
stable_url="${stable_url_line#  url \"}"
stable_url="${stable_url%\",}"
check "H14 stable interpolated URL (read back from the rewritten file)" "${stable_url//\#\{version\}/0.1.0}" \
    "https://github.com/F-e-u-e-r/ai-pet-usage/releases/download/v0.1.0/AI-Pet-Usage-v0.1.0-arm64.zip"
bash "$UPD" --check "$TMP/cask.rb" 0.1.0 "$SHA_B"; check "H13 --check after the stable rewrite is current" "$?" 0
cp "$CASK" "$TMP/guard.rb"
for badargs in "v0.1.0-beta.1|$SHA_A" "0.1.0-beta.0|$SHA_A" "alpha-v0.4.0|$SHA_A" "0.1.0-beta.1|ABC" "0.1.0-beta.1|"; do
    IFS='|' read -r v s <<< "$badargs"
    bash "$UPD" "$TMP/guard.rb" "$v" "$s" 2>/dev/null; check "update-cask rejects [$badargs]" "$?" 2
done
if cmp -s "$CASK" "$TMP/guard.rb"; then ok; else bad "rejected update-cask runs must leave the cask untouched"; fi
printf 'cask "x" do\n  version "1"\n  version "2"\n  sha256 "%s"\n  url "https://github.com/F-e-u-e-r/ai-pet-usage/releases/download/x",\nend\n' "$SHA_A" > "$TMP/dup.rb"
cp "$TMP/dup.rb" "$TMP/dup.orig"
bash "$UPD" "$TMP/dup.rb" 0.1.0 "$SHA_A" 2>/dev/null; check "update-cask refuses duplicate target lines" "$?" 2
if cmp -s "$TMP/dup.rb" "$TMP/dup.orig"; then ok; else bad "duplicate-line refusal modified the file"; fi
# Malformed casks: an extra stanza in any form, or invalid Ruby, is refused in both modes; the file is untouched.
cp "$TMP/cask.again.rb" "$TMP/current.rb"   # a valid, current 0.1.0-beta.1 / SHA_A cask
bash "$UPD" --check "$TMP/current.rb" 0.1.0-beta.1 "$SHA_A"; check "fixture: current cask --check" "$?" 0
for extra in '  url "https://example.invalid/other.zip"' '    version "9"' '  sha256 :no_check' \
             '  url("https://example.invalid/other.zip")' '  version("9")' "  sha256(\"$SHA_B\")" \
             '  url"https://example.invalid/x.zip"' '  name "x"; url "https://example.invalid/y.zip"' \
             "  \"#{url('https://example.invalid/other.zip')}#{sha256(:no_check)}\"" '  "#{version("9")}"' \
             '  "#{ sha256 :no_check }"' '  "#{version.major}"'; do
    awk -v x="$extra" '{ print } /^      verified:/ { print x }' "$TMP/current.rb" > "$TMP/extra.rb"
    cp "$TMP/extra.rb" "$TMP/extra.orig"
    bash "$UPD" --check "$TMP/extra.rb" 0.1.0-beta.1 "$SHA_A" 2>/dev/null; check "--check refuses extra stanza [$extra]" "$?" 2
    bash "$UPD" "$TMP/extra.rb" 0.1.0-beta.1 "$SHA_B" 2>/dev/null; check "rewrite refuses extra stanza [$extra]" "$?" 2
    if cmp -s "$TMP/extra.rb" "$TMP/extra.orig"; then ok; else bad "extra-stanza refusal modified the file [$extra]"; fi
done
# The url template's bare #{version} (even spaced) is not a stanza: a spaced template only needs a rewrite.
sed 's/#{version}/#{ version }/g' "$TMP/current.rb" > "$TMP/spaced.rb"
bash "$UPD" --check "$TMP/spaced.rb" 0.1.0-beta.1 "$SHA_A" 2>/dev/null
check "--check: a spaced bare #{ version } is not a stanza (rewrite needed, not refused)" "$?" 1
# A bare #{version} elsewhere only reads the version (Homebrew's getter), so it is not a stanza either.
awk '{ print } /^  name "AI Pet Usage"$/ { print "  name \"#{version}\"" }' "$TMP/current.rb" > "$TMP/named.rb"
check "fixture: a name \"#{version}\" line was added" "$(grep -c '^  name "#{version}"$' "$TMP/named.rb")" 1
bash "$UPD" --check "$TMP/named.rb" 0.1.0-beta.1 "$SHA_A" 2>/dev/null
check "--check: a bare #{version} outside the url only reads the version (current, not refused)" "$?" 0
grep -v '^end$' "$TMP/current.rb" > "$TMP/noend.rb"
cp "$TMP/noend.rb" "$TMP/noend.orig"
bash "$UPD" --check "$TMP/noend.rb" 0.1.0-beta.1 "$SHA_A" 2>/dev/null; check "--check refuses a cask that is not valid Ruby" "$?" 2
bash "$UPD" "$TMP/noend.rb" 0.1.0-beta.1 "$SHA_B" 2>/dev/null; check "rewrite refuses a cask that is not valid Ruby" "$?" 2
if cmp -s "$TMP/noend.rb" "$TMP/noend.orig"; then ok; else bad "invalid-Ruby refusal modified the file"; fi

# ---------------------------------------------------------------- 4. asset digest (H12)
printf 'asset-bytes' > "$TMP/asset.zip"
real="$(sha256_of "$TMP/asset.zip")"
out="$(bash "$VER" "$TMP/asset.zip" "sha256:$real")"; check "H12 matching digest exit" "$?" 0
check "H12 matching digest prints sha" "$out" "$real"
out="$(bash "$VER" "$TMP/asset.zip" "sha256:$SHA_A" 2>"$TMP/v.err")"; check "H12 mismatching digest exit" "$?" 1
check "H12 mismatch prints nothing" "$out" ""
if grep -q 'does not match the GitHub API digest' "$TMP/v.err"; then ok; else bad "H12 mismatch message"; fi
bash "$VER" "$TMP/asset.zip" "" 2>/dev/null; check "H12 missing digest exit" "$?" 1
bash "$VER" "$TMP/asset.zip" "md5:$real" 2>/dev/null; check "H12 non-sha256 digest exit" "$?" 1
: > "$TMP/empty.zip"
bash "$VER" "$TMP/empty.zip" "sha256:$real" 2>/dev/null; check "H12 empty download exit" "$?" 1

# release-asset.sh: exactly one matching asset with a well-formed "sha256:<hex>" API digest, else exit 1
A="AI-Pet-Usage-v0.1.0-beta.1-arm64.zip"
ax() { # ax <label> <release-json> <want-stdout> <want-exit>
    printf '%s' "$2" > "$TMP/release.json"
    local out rc
    out="$(bash "$ASSETX" "$TMP/release.json" "$A" 2>/dev/null)"
    rc=$?
    check "$1 (exit)" "$rc" "$4"
    check "$1 (stdout)" "$out" "$3"
}
ax "release-asset: one matching asset" "{\"assets\":[{\"name\":\"$A\",\"digest\":\"sha256:$SHA_A\"},{\"name\":\"other.zip\",\"digest\":null}]}" "$SHA_A" 0
ax "release-asset: non-object asset entries ignored" "{\"assets\":[null,3,\"x\",{\"name\":\"$A\",\"digest\":\"sha256:$SHA_A\"}]}" "$SHA_A" 0
ax "release-asset: zero matching assets" '{"assets":[{"name":"other.zip","digest":"sha256:x"}]}' "" 1
ax "release-asset: two matching assets" "{\"assets\":[{\"name\":\"$A\",\"digest\":\"sha256:$SHA_A\"},{\"name\":\"$A\",\"digest\":\"sha256:$SHA_B\"}]}" "" 1
ax "release-asset: null digest" "{\"assets\":[{\"name\":\"$A\",\"digest\":null}]}" "" 1
ax "release-asset: missing digest" "{\"assets\":[{\"name\":\"$A\"}]}" "" 1
ax "release-asset: digest without sha256: prefix" "{\"assets\":[{\"name\":\"$A\",\"digest\":\"$SHA_A\"}]}" "" 1
ax "release-asset: uppercase hex" "{\"assets\":[{\"name\":\"$A\",\"digest\":\"sha256:$(printf 'A%.0s' $(seq 1 64))\"}]}" "" 1
ax "release-asset: 63 hex" "{\"assets\":[{\"name\":\"$A\",\"digest\":\"sha256:${SHA_A:1}\"}]}" "" 1
ax "release-asset: trailing newline inside the digest" "{\"assets\":[{\"name\":\"$A\",\"digest\":\"sha256:$SHA_A\\n\"}]}" "" 1
ax "release-asset: malformed JSON" '{"assets":[' "" 1
ax "release-asset: not a release object" '[]' "" 1
ax "release-asset: assets is not an array" '{"assets":{}}' "" 1

# ---------------------------------------------------------------- 5. wiring guards (bump-cask.yml -> scripts/bump-cask.sh)
check "workflow runs scripts/bump-cask.sh" "$(grep -cF 'run: bash scripts/bump-cask.sh' "$WF")" 1
check "workflow carries no inline bump logic (non-comment lines)" "$(grep -v '^[[:space:]]*#' "$WF" | grep -cE 'gh release|update-cask|curl |git commit')" 0
check "bump selects via select-release.jq" "$(grep -cF 'jq -r --arg mode select -f "$HERE/select-release.jq"' "$BUMP")" 1
check "bump has no alpha-v selection or prefix stripping" "$(grep -cE 'startswith\("alpha-v"\)|#alpha-v' "$BUMP")" 0
check "bump does not order by publishedAt" "$(grep -c 'sort_by(.publishedAt)' "$BUMP")" 0
check "bump lists with one more than the 1000-release bound" "$(grep -cF 'gh release list --repo "$REPO" --limit 1001 --exclude-drafts' "$BUMP")" 1
check "bump derives the asset name from the tag" "$(grep -cF 'ASSET="AI-Pet-Usage-${TAG}-arm64.zip"' "$BUMP")" 1
check "bump derives the download URL from the tag" "$(grep -cF 'URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"' "$BUMP")" 1
check "bump never strips an unvalidated digest" "$(grep -cF 'DIGEST' "$BUMP")" 0
check "bump fails on any other --check exit status" "$(grep -cF '*) echo "update-cask.sh --check failed (exit $rc)"; exit "$rc" ;;' "$BUMP")" 1

# ---------------------------------------------------------------- 7. bump-cask.sh end-to-end (stubbed gh / curl, real git)
# A throwaway tap clone ($E2E/tap, pushing to a local bare repo) runs the real scripts/bump-cask.sh; only gh and curl
# are stubs. The real Casks/ai-pet-usage.rb is only ever copied.
E2E="$TMP/e2e"
mkdir -p "$E2E/bin" "$E2E/state" "$E2E/tmp" "$E2E/tap/Casks"
cat > "$E2E/bin/gh" <<'STUB'
#!/bin/bash
printf 'gh %s\n' "$*" >> "$E2E_STATE/calls.log"
case "$1 $2" in
    "release list")   # honors --limit N like gh: the first N (newest created first; default 30)
        limit=30
        prev=""
        for a in "$@"; do
            [ "$prev" = "--limit" ] && limit="$a"
            prev="$a"
        done
        jq -c ".[:$limit]" "$E2E_STATE/releases.json" ;;
    "api repos/F-e-u-e-r/ai-pet-usage/releases/tags/"*) cat "$E2E_STATE/release.json" ;;
    *) exit 3 ;;
esac
STUB
cat > "$E2E/bin/curl" <<'STUB'
#!/bin/bash
out=""
url=""
while [ $# -gt 0 ]; do
    case $1 in
        -o) out="$2"; shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
printf 'curl %s\n' "$url" >> "$E2E_STATE/calls.log"
cp "$E2E_STATE/asset.bin" "$out"
STUB
chmod +x "$E2E/bin/gh" "$E2E/bin/curl"
cp "$CASK" "$E2E/tap/Casks/ai-pet-usage.rb"
git init -q "$E2E/tap"
git -C "$E2E/tap" symbolic-ref HEAD refs/heads/main
git -C "$E2E/tap" add Casks/ai-pet-usage.rb
git -C "$E2E/tap" -c user.name=test -c user.email=test@example.invalid commit -q -m "legacy cask"
git init -q --bare "$E2E/remote.git"
git -C "$E2E/tap" remote add origin "$E2E/remote.git"
git -C "$E2E/tap" push -q -u origin main 2>/dev/null
e2e() { # e2e <label>: run bump-cask.sh against the current stub state; sets rc, curls, apis, commits, synced
    : > "$E2E/state/calls.log"
    (cd "$E2E/tap" && PATH="$E2E/bin:$PATH" E2E_STATE="$E2E/state" RUNNER_TEMP="$E2E/tmp" bash "$BUMP" > "$E2E/out.txt" 2>&1)
    rc=$?
    curls="$(grep -c '^curl ' "$E2E/state/calls.log")"
    apis="$(grep -c '^gh api ' "$E2E/state/calls.log")"
    commits="$(git -C "$E2E/tap" rev-list --count HEAD)"
    if [ "$(git -C "$E2E/tap" rev-parse HEAD)" = "$(git -C "$E2E/remote.git" rev-parse main)" ]; then synced=yes; else synced=no; fi
}
asset_json() { # asset_json <tag> <digest> [<digest of a duplicate asset>]
    local a="AI-Pet-Usage-$1-arm64.zip"
    if [ -n "${3-}" ]; then
        printf '{"assets":[{"name":"%s","digest":"%s"},{"name":"%s","digest":"%s"}]}' "$a" "$2" "$a" "$3"
    else
        printf '{"assets":[{"name":"other.zip","digest":null},{"name":"%s","digest":"%s"}]}' "$a" "$2"
    fi
}
cask_line() { grep -E "^  $1 " "$E2E/tap/Casks/ai-pet-usage.rb"; }

printf '[%s]' "$(R alpha-v0.4.0 false true)" > "$E2E/state/releases.json"
e2e
check "E2E no eligible release: exit 0, no API/download, no commit" "$rc|$apis|$curls|$commits" "0|0|0|1"

printf 'beta-1 bytes' > "$E2E/state/asset.bin"
B1="$(sha256_of "$E2E/state/asset.bin")"
printf '[%s,%s]' "$(R alpha-v0.4.0 false true)" "$(R v0.1.0-beta.1 false true)" > "$E2E/state/releases.json"
asset_json v0.1.0-beta.1 "sha256:$B1" > "$E2E/state/release.json"
e2e
check "E2E first canonical bump: exit, one download, one commit, pushed" "$rc|$curls|$commits|$synced" "0|1|2|yes"
check "E2E first canonical bump: download URL derived from the tag" "$(grep '^curl ' "$E2E/state/calls.log")" \
    "curl https://github.com/F-e-u-e-r/ai-pet-usage/releases/download/v0.1.0-beta.1/AI-Pet-Usage-v0.1.0-beta.1-arm64.zip"
check "E2E first canonical bump: cask version" "$(cask_line version)" '  version "0.1.0-beta.1"'
check "E2E first canonical bump: cask sha256 = verified download" "$(cask_line sha256)" "  sha256 \"$B1\""
check "E2E first canonical bump: cask url template" "$(cask_line url)" \
    '  url "https://github.com/F-e-u-e-r/ai-pet-usage/releases/download/v#{version}/AI-Pet-Usage-v#{version}-arm64.zip",'
check "E2E first canonical bump: commit message" "$(git -C "$E2E/tap" log -1 --format=%s)" "ai-pet-usage 0.1.0-beta.1"

e2e
check "E2E already current: exit 0, no download, no new commit" "$rc|$curls|$commits" "0|0|2"

printf 'beta-1 re-uploaded bytes' > "$E2E/state/asset.bin"
B1R="$(sha256_of "$E2E/state/asset.bin")"
asset_json v0.1.0-beta.1 "sha256:$B1R" > "$E2E/state/release.json"
e2e
check "E2E same-version re-upload: new sha256 committed" "$rc|$curls|$commits|$(cask_line sha256)" "0|1|3|  sha256 \"$B1R\""

before="$(sha256_of "$E2E/tap/Casks/ai-pet-usage.rb")"
printf 'tampered bytes' > "$E2E/state/asset.bin"
asset_json v0.1.0-beta.1 "sha256:$SHA_A" > "$E2E/state/release.json"
e2e
check "E2E download not matching the API digest: fails, cask untouched, no commit" \
    "$([ "$rc" -ne 0 ] && echo fail)|$(sha256_of "$E2E/tap/Casks/ai-pet-usage.rb")|$commits" "fail|$before|3"
asset_json v0.1.0-beta.1 "$SHA_A" > "$E2E/state/release.json"
e2e
check "E2E malformed API digest: fails before any download" "$([ "$rc" -ne 0 ] && echo fail)|$curls|$commits" "fail|0|3"
asset_json v0.1.0-beta.1 "sha256:$SHA_A" "sha256:$SHA_B" > "$E2E/state/release.json"
e2e
check "E2E two matching assets: fails before any download" "$([ "$rc" -ne 0 ] && echo fail)|$curls|$commits" "fail|0|3"

printf 'rc-1 bytes' > "$E2E/state/asset.bin"
C1="$(sha256_of "$E2E/state/asset.bin")"
printf '[%s,%s,%s]' "$(R v0.2.0-alpha.1 false true)" "$(R v0.1.0-beta.1 false true)" "$(R v0.1.0-rc.1 false true)" > "$E2E/state/releases.json"
asset_json v0.1.0-rc.1 "sha256:$C1" > "$E2E/state/release.json"
e2e
check "E2E rc supersedes the beta (newer alpha ignored)" "$rc|$commits|$(cask_line version)|$synced" '0|4|  version "0.1.0-rc.1"|yes'

# Bounded listing (1000 releases; one more is requested): a listing over the bound is KNOWN to be incomplete, so the
# bump fails before selecting — never a lower version, never "no eligible release".
alpha_list() { local i out=""; for i in $(seq "$1" -1 1); do out="$out,$(R "v0.9.0-alpha.$i" false true)"; done; printf '%s' "${out#,}"; }
printf 'v1.0.0 bytes' > "$E2E/state/asset.bin"
asset_json v1.0.0 "sha256:$(sha256_of "$E2E/state/asset.bin")" > "$E2E/state/release.json"
printf '[%s,%s,%s]' "$(R v1.0.0 false false)" "$(alpha_list 999)" "$(R v2.0.0 false false)" > "$E2E/state/releases.json"
e2e
check "E2E over the bound (v1.0.0 + 999 newer alphas hide v2.0.0): fails, no API / download / commit" \
    "$([ "$rc" -ne 0 ] && echo fail)|$apis|$curls|$commits|$(cask_line version)|$(grep -c 'more than 1000 releases' "$E2E/out.txt")" \
    'fail|0|0|4|  version "0.1.0-rc.1"|1'
printf '[%s,%s]' "$(alpha_list 1000)" "$(R v9.9.9 false false)" > "$E2E/state/releases.json"
e2e
check "E2E over the bound (1000 newer alphas hide v9.9.9): fails, not 'no eligible release'" \
    "$([ "$rc" -ne 0 ] && echo fail)|$apis|$commits|$(grep -c 'no eligible' "$E2E/out.txt")" 'fail|0|4|0'
printf 'rc-2 bytes' > "$E2E/state/asset.bin"
C2="$(sha256_of "$E2E/state/asset.bin")"
asset_json v0.1.0-rc.2 "sha256:$C2" > "$E2E/state/release.json"
printf '[%s,%s]' "$(alpha_list 999)" "$(R v0.1.0-rc.2 false true)" > "$E2E/state/releases.json"
e2e
check "E2E exactly 1000 releases is a complete listing: rc.2 selected and committed" \
    "$rc|$curls|$commits|$(cask_line version)|$synced" '0|1|5|  version "0.1.0-rc.2"|yes'
check "the real Casks/ai-pet-usage.rb is untouched by the tests" "$(sha256_of "$CASK")" "$CASK_SHA_AT_START"

# ---------------------------------------------------------------- 6. Homebrew Ruby semantics (H15, local only)
if command -v brew >/dev/null 2>&1; then
    if HOMEBREW_NO_AUTO_UPDATE=1 brew ruby -e '
        require "cask/dsl/version"
        v = Cask::DSL::Version.new("0.1.0-beta.1")
        url = "https://github.com/F-e-u-e-r/ai-pet-usage/releases/download/v#{v}/AI-Pet-Usage-v#{v}-arm64.zip"
        ok = !v.latest? && "v#{v}" == "v0.1.0-beta.1" &&
             url == "https://github.com/F-e-u-e-r/ai-pet-usage/releases/download/v0.1.0-beta.1/AI-Pet-Usage-v0.1.0-beta.1-arm64.zip" &&
             ("0.4.0" == v) == false
        exit(ok ? 0 : 1)' >/dev/null 2>&1; then ok; else bad "H15 Cask::DSL::Version semantics for 0.1.0-beta.1"; fi
else
    printf 'SKIP: brew not on PATH — H15 Cask::DSL::Version check not run\n'
fi

# ---------------------------------------------------------------- summary
total=$((pass + fail))
if [ "$fail" -eq 0 ] && [ "$total" -gt 0 ]; then
    printf 'bump tests: PASS (%d checks; vectors %d accept / %d reject / %d order)\n' "$total" "$n_accept" "$n_reject" "$n_order"
    exit 0
fi
printf 'bump tests: FAIL (%d of %d checks failed)\n' "$fail" "$total"
exit 1

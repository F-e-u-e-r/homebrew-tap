#!/bin/bash
# Rewrites (or checks) the three release-specific lines of Casks/ai-pet-usage.rb: version, sha256, url.
#
#   update-cask.sh <cask-file> <version> <sha256>           rewrite those three lines; exit 0
#   update-cask.sh --check <cask-file> <version> <sha256>   exit 0 if the cask already has exactly these
#                                                           three lines, 1 if a rewrite is needed
#
# <version> is the canonical display version (the tag without "v", e.g. 0.1.0-beta.1 — see
# docs/release/VERSIONING.md in F-e-u-e-r/ai-pet-usage); <sha256> is 64 lowercase hex characters.
# The url line always becomes the canonical template, so the first canonical bump migrates the legacy
# alpha-v#{version} URL in the same commit as the version and sha256. The template uses the raw
# #{version} only: Cask::DSL::Version#patch would split 0.1.0-beta.1 into "0-beta".
# The cask must be valid Ruby (`ruby -c`, before and after the rewrite), and every version / sha256 / url
# stanza — whatever its value or indentation — must occur exactly once in the exact form rewritten here.
# On any violation the cask is left untouched and the exit status is 2 (so `--check` exits 0 only for a
# valid, current cask).
set -euo pipefail
export LC_ALL=C

URL_LINE='  url "https://github.com/F-e-u-e-r/ai-pet-usage/releases/download/v#{version}/AI-Pet-Usage-v#{version}-arm64.zip",'
VERSION_RE='^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})(-(alpha|beta|rc)\.([1-9][0-9]{0,8}))?$'

die() {
    printf 'update-cask: %s\n' "$1" >&2
    exit 2
}

check=false
if [ "${1-}" = "--check" ]; then
    check=true
    shift
fi
[ $# -eq 3 ] || die "usage: update-cask.sh [--check] <cask-file> <version> <sha256>"
cask="$1"
version="$2"
sha="$3"
[[ $version =~ $VERSION_RE ]] || die "version must be a canonical display version (got '$version')"
[[ $sha =~ ^[0-9a-f]{64}$ ]] || die "sha256 must be 64 lowercase hex characters"
[ -f "$cask" ] || die "cask file not found: $cask"

command -v ruby >/dev/null 2>&1 || die "ruby is required to validate the cask syntax"
ruby -c "$cask" >/dev/null 2>&1 || die "cask is not valid Ruby: $cask"

# Every release-defining call and the rewritable form of each must both occur exactly once: a second url (e.g. a
# mirror) or a `sha256 :no_check` must not survive unnoticed. The calls are counted with Ruby's own lexer, so every
# syntax counts — `url "x"`, `url("x")`, `url"x"`, a call after `;`, and a call inside a string interpolation
# (`"#{url(…)}"` still calls url). A bare `#{version}` (spaces allowed) only reads the version — Homebrew's `version`
# without an argument is the getter — so it is allowed in any string, as in the url template; any other interpolation
# that names version / sha256 / url (even a reference such as `#{version.major}`) is counted, so the cask is refused —
# fail closed. A lexical check cannot see dynamic dispatch (`send("url", …)`); Homebrew itself rejects a second
# stanza ("may only appear once").
counts="$(ruby -rripper -e '
    names = %w[version sha256 url]
    depth = 0
    inner = []   # significant tokens of the outermost interpolation being read
    counts = Hash.new(0)
    Ripper.lex(File.read(ARGV[0])).each do |(_, type, text)|
      case type
      when :on_embexpr_beg
        depth += 1
        inner = [] if depth == 1
      when :on_embexpr_end
        depth -= 1
        if depth.zero? && inner != [[:on_ident, "version"]]
          inner.each { |t, s| counts[s] += 1 if t == :on_ident && names.include?(s) }
        end
      when :on_sp
      else
        if depth.zero?
          counts[text] += 1 if type == :on_ident && names.include?(text)
        else
          inner << [type, text]
        end
      end
    end
    puts [counts["version"], counts["sha256"], counts["url"]].join(" ")' "$cask")" || die "could not lex the cask"
read -r n_version n_sha n_url <<< "$counts"
t_version=$(grep -cE '^  version "[^"]*"$' "$cask" || true)
t_sha=$(grep -cE '^  sha256 "[^"]*"$' "$cask" || true)
t_url=$(grep -cE '^  url "https://github\.com/F-e-u-e-r/ai-pet-usage/releases/download/[^"]*",$' "$cask" || true)
if [ "$n_version $n_sha $n_url $t_version $t_sha $t_url" != "1 1 1 1 1 1" ]; then
    die "expected exactly one version / sha256 / url stanza in the rewritable form (stanzas $n_version / $n_sha / $n_url, rewritable $t_version / $t_sha / $t_url)"
fi

want_version="  version \"$version\""
want_sha="  sha256 \"$sha\""

if $check; then
    if grep -qxF -- "$want_version" "$cask" && grep -qxF -- "$want_sha" "$cask" && grep -qxF -- "$URL_LINE" "$cask"; then
        exit 0
    fi
    exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
awk -v ver="$want_version" -v sha="$want_sha" -v url="$URL_LINE" '
    /^  version "[^"]*"$/ { print ver; next }
    /^  sha256 "[^"]*"$/ { print sha; next }
    /^  url "https:\/\/github\.com\/F-e-u-e-r\/ai-pet-usage\/releases\/download\/[^"]*",$/ { print url; next }
    { print }
' "$cask" > "$tmp"
ruby -c "$tmp" >/dev/null 2>&1 || die "rewritten cask is not valid Ruby; $cask left untouched"
cat "$tmp" > "$cask"

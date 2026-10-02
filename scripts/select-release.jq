# Canonical release selection for the ai-pet-usage cask.
# Normative contract: docs/release/VERSIONING.md in F-e-u-e-r/ai-pet-usage (tag grammar and ordering)
# plus the owner's main-cask channel policy (beta / rc / stable; alpha excluded).
#
#   jq -r --arg mode select -f scripts/select-release.jq releases.json
#       input:  array of {tagName, isDraft, isPrerelease, ...} (`gh release list --json ...`)
#       output: the selected tag, or "" when no eligible canonical release exists
#   jq -c --arg mode parse -f scripts/select-release.jq <<< '"v0.1.0-beta.1"'
#       input:  a JSON string; output: {maj, min, pat, channel, iteration} or null
#   jq -c --arg mode key -f scripts/select-release.jq <<< '"v0.1.0-beta.1"'
#       input:  a JSON string; output: the canonical sort key [maj, min, pat, rank, iteration] or null
#
# Eligible: canonical tag; isDraft is exactly false; isPrerelease is a boolean that agrees with the tag
# (alpha/beta/rc <=> true, stable <=> false); channel is beta, rc or stable. Every legacy alpha-v*,
# malformed or alpha tag, and every record with missing or non-boolean flags, is excluded (fail closed).
# Choice: the highest canonical semantic version — never publication time, list order or string order.
# No eligible release => "" (the workflow then leaves the cask unchanged; there is no fallback to legacy
# alpha-v* tags). An input that is not an array is an error, never "no eligible release".
#
# Regex notes (verified): Oniguruma's ^...$ also accepts a trailing newline, so the anchors are \A...\z;
# \d matches non-ASCII digits, so digits are [0-9]. Numeric fields are at most 9 digits, so tonumber
# (an IEEE double) is exact.

def canonical_re:
  "\\Av(?<maj>0|[1-9][0-9]{0,8})\\.(?<min>0|[1-9][0-9]{0,8})\\.(?<pat>0|[1-9][0-9]{0,8})(-(?<ch>alpha|beta|rc)\\.(?<it>[1-9][0-9]{0,8}))?\\z";

def parse_tag:
  if type == "string" and test(canonical_re) then
    capture(canonical_re)
    | { maj: (.maj | tonumber), min: (.min | tonumber), pat: (.pat | tonumber),
        channel: (.ch // "stable"),
        iteration: (if .it == null then null else (.it | tonumber) end) }
  else null end;

def rank: { "alpha": 0, "beta": 1, "rc": 2, "stable": 3 }[.];

def sort_key: [ .maj, .min, .pat, (.channel | rank), (.iteration // 0) ];

def cask_channels: [ "beta", "rc", "stable" ];

if $mode == "parse" then
  parse_tag
elif $mode == "key" then
  (parse_tag | if . == null then null else sort_key end)
elif $mode == "select" then
  if type != "array" then error("select: expected an array of releases") else . end
  | [ .[]
    | select(type == "object" and .isDraft == false and (.isPrerelease | type) == "boolean")
    | . as $r
    | ($r.tagName | parse_tag) as $v
    | select($v != null)
    | select(($v.channel as $c | cask_channels | index($c)) != null)
    | select($r.isPrerelease == ($v.channel != "stable"))
    | { tag: $r.tagName, key: ($v | sort_key) } ]
  | sort_by(.key)
  | (last // { tag: "" })
  | .tag
else
  error("unknown mode: \($mode)")
end

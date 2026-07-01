#!/usr/bin/env bash
# post-to-pr.sh — render a ledger into a GitHub review; optionally post it.
# Usage:
#   post-to-pr.sh --dry-run <ledger.json> <commit-sha>            # print payload only
#   post-to-pr.sh <ledger.json> <commit-sha> <owner/repo> <pr#>   # post via gh
# Only OPEN findings are posted. Anchored findings (line != null) become inline
# comments; unanchored findings (line == null) are collected into the review
# body (a null line would 422 an inline comment). If nothing is open, no review
# is posted (an empty COMMENT review is rejected by GitHub).
# shellcheck disable=SC2016  # jq program references $commit (passed via --arg)
set -euo pipefail

die() { printf 'post-to-pr: %s\n' "$1" >&2; exit 1; }
command -v jq >/dev/null || die "jq required"

build_payload() { # <ledger> <commit>
  local ledger="$1" commit="$2"
  jq -e 'type == "array"' "$ledger" >/dev/null 2>&1 || die "ledger not a JSON array: $ledger"
  jq --arg commit "$commit" '
    def sev: {high:"🔴 HIGH", medium:"🟠 MEDIUM", low:"🟢 LOW"}[.severity] // .severity;
    ( [ .[] | select((.status // "open") == "open") ] ) as $open |
    ( [ $open[] | select(.line != null) ] ) as $anchored |
    ( [ $open[] | select(.line == null) ] ) as $unanchored |
    {
      commit_id: $commit,
      event: "COMMENT",
      body: (if ($unanchored | length) > 0
             then "### Unanchored findings\n\n" + ( $unanchored
                    | map("- **" + sev + " — " + .title + "** (" + .dimension + " · " + .file + ")\n\n  " + .detail
                          + (if .suggestion then "\n\n  *Suggested:* " + .suggestion else "" end))
                    | join("\n") )
             else "" end),
      comments: [ $anchored[] | {
        path: .file,
        line: .line,
        side: (.side // "RIGHT"),
        body: ("**" + sev + " — " + .title + "**\n\n" + .detail
               + (if .suggestion then "\n\n*Suggested:* " + .suggestion else "" end))
      } ]
    }' "$ledger"
}

mode="${1:-}"
if [ "$mode" = "--dry-run" ]; then
  ledger="${2:-}"; commit="${3:-}"
  { [ -n "$ledger" ] && [ -n "$commit" ]; } || die "usage: post-to-pr.sh --dry-run <ledger> <commit>"
  [ -f "$ledger" ] || die "no such ledger: $ledger"
  build_payload "$ledger" "$commit"
  exit 0
fi

ledger="${1:-}"; commit="${2:-}"; repo="${3:-}"; pr="${4:-}"
{ [ -n "$ledger" ] && [ -n "$commit" ] && [ -n "$repo" ] && [ -n "$pr" ]; } \
  || die "usage: post-to-pr.sh <ledger> <commit> <owner/repo> <pr#>"
[ -f "$ledger" ] || die "no such ledger: $ledger"

payload="$(build_payload "$ledger" "$commit")"
n_comments="$(printf '%s' "$payload" | jq '.comments | length')"
body_len="$(printf '%s' "$payload" | jq -r '.body | length')"
if [ "$n_comments" -eq 0 ] && [ "$body_len" -eq 0 ]; then
  printf 'post-to-pr: no open findings to post\n' >&2
  exit 0
fi

command -v gh >/dev/null || die "gh required to post (use --dry-run to preview)"
printf '%s' "$payload" \
  | gh api "repos/$repo/pulls/$pr/reviews" --method POST --input - >/dev/null \
  || die "gh api call failed"
printf 'posted review to %s#%s (%s inline, body:%s)\n' "$repo" "$pr" "$n_comments" \
  "$([ "$body_len" -gt 0 ] && echo yes || echo no)" >&2

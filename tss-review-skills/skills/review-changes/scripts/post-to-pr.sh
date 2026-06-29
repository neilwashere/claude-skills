#!/usr/bin/env bash
# post-to-pr.sh — render a ledger into a GitHub review; optionally post it.
# Usage:
#   post-to-pr.sh --dry-run <ledger.json> <commit-sha>            # print payload only
#   post-to-pr.sh <ledger.json> <commit-sha> <owner/repo> <pr#>   # post via gh
# shellcheck disable=SC2016  # jq program references $commit (passed via --arg)
set -euo pipefail

die() { printf 'post-to-pr: %s\n' "$1" >&2; exit 1; }
command -v jq >/dev/null || die "jq required"

build_payload() { # <ledger> <commit>
  local ledger="$1" commit="$2"
  jq -e 'type == "array"' "$ledger" >/dev/null 2>&1 || die "ledger not a JSON array: $ledger"
  jq --arg commit "$commit" '
    def sev: {high:"🔴 HIGH", medium:"🟠 MEDIUM", low:"🟢 LOW"}[.severity] // .severity;
    {
      commit_id: $commit,
      event: "COMMENT",
      comments: [ .[] | {
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
command -v gh >/dev/null || die "gh required to post (use --dry-run to preview)"

build_payload "$ledger" "$commit" \
  | gh api "repos/$repo/pulls/$pr/reviews" --method POST --input - >/dev/null \
  || die "gh api call failed"
printf 'posted review to %s#%s\n' "$repo" "$pr" >&2

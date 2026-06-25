#!/usr/bin/env bash
# worktree-config.sh — resolve worktree CONFIG (not enforcement) from the 3-tier
# config marker family. Sourced by wt-new.sh / wt-rm.sh and by tests.
#
# Per field, the first tier that DEFINES it wins; absent/unparseable tiers are
# skipped. Repo-level files are read from <repo_root> = the MAIN checkout root.
#   <repo_root>/.claude/worktree-config.local.json   (gitignored, per-checkout)
#   <repo_root>/.claude/worktree-config.json          (committed, team)
#   $HOME/.claude/worktree-config.json                (user-global)
#   built-in default (handled by the per-field functions below)

# _wtc_field_raw <repo_root> <field>
# Print compact JSON value of <field> from the first defining tier; rc 1 if none.
_wtc_field_raw() {
  local repo_root="$1" field="$2" f
  for f in \
    "$repo_root/.claude/worktree-config.local.json" \
    "$repo_root/.claude/worktree-config.json" \
    "$HOME/.claude/worktree-config.json"
  do
    [ -f "$f" ] || continue
    jq empty "$f" >/dev/null 2>&1 || continue
    if jq -e --arg k "$field" 'has($k)' "$f" >/dev/null 2>&1; then
      jq -c --arg k "$field" '.[$k]' "$f"
      return 0
    fi
  done
  return 1
}

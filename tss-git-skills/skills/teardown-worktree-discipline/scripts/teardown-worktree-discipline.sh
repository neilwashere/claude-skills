#!/usr/bin/env bash
# teardown-worktree-discipline.sh — remove the worktree-discipline enforcement
# installed by setup-worktree-discipline. Idempotent: safe to run repeatedly.
#
# Steps:
#   1. Deregister the hook from ~/.claude/settings.json
#   2. Delete ~/.claude/hooks/worktree-discipline.sh
#   3. Remove the ## Worktree discipline section from ~/.claude/CLAUDE.md
#
# Does NOT touch per-repo markers (.claude/worktree-discipline*.json).
# Run BEFORE /plugin uninstall.
set -euo pipefail

# jq is a hard dependency — fail loud if absent.
command -v jq >/dev/null 2>&1 || { echo "teardown: jq is required" >&2; exit 1; }

SETTINGS="$HOME/.claude/settings.json"
HOOK_FILE="$HOME/.claude/hooks/worktree-discipline.sh"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"

CHANGED=0

# Clean up any orphaned temp files on exit (including aborts).
_teardown_tmp=""
cleanup() { [ -n "$_teardown_tmp" ] && rm -f "$_teardown_tmp"; }
trap cleanup EXIT

# Abort on unparseable settings.json — a malformed file can silently masquerade
# as "not registered," causing the script to delete the hook file while the
# dangling registration stays in settings.json (every tool call then fails).
if [ -f "$SETTINGS" ] && ! jq empty "$SETTINGS" >/dev/null 2>&1; then
  echo "teardown: $SETTINGS is not valid JSON — fix or restore it first, then re-run" >&2
  exit 1
fi

# ---- 1. Deregister the hook from settings.json ----
if [ -f "$SETTINGS" ] && jq -e '[.. | .command? // empty] | any(test("worktree-discipline.sh"))' "$SETTINGS" >/dev/null 2>&1; then
  # Write filtered JSON to a temp file, then atomically replace — avoids
  # truncating the live file before jq runs (set -e would abort mid-write).
  _teardown_tmp="$(mktemp)"
  jq '
    if (.hooks.PreToolUse | type) == "array" then
        .hooks.PreToolUse |= (
            map(.hooks |= map(select((.command // "") | test("worktree-discipline.sh") | not)))
          | map(select((.hooks | length) > 0))
        )
      | (if (.hooks.PreToolUse | length) == 0 then .hooks |= del(.PreToolUse) else . end)
    else . end
  ' "$SETTINGS" > "$_teardown_tmp"
  # Verify the entry was actually removed before committing.
  if jq -e '[.. | .command? // empty] | any(test("worktree-discipline.sh"))' "$_teardown_tmp" >/dev/null 2>&1; then
    echo "teardown: FAILED to remove hook from settings.json" >&2
    exit 1
  fi
  cp "$_teardown_tmp" "$SETTINGS"
  rm -f "$_teardown_tmp"
  echo "teardown: hook deregistered from ~/.claude/settings.json"
  CHANGED=1
else
  echo "teardown: hook not registered in settings.json (already clean)"
fi

# ---- 2. Delete the copied hook script ----
if [ -f "$HOOK_FILE" ]; then
  rm -f "$HOOK_FILE"
  echo "teardown: removed ~/.claude/hooks/worktree-discipline.sh"
  CHANGED=1
else
  echo "teardown: hook script not present (already clean)"
fi

# ---- 3. Remove the CLAUDE.md rule section ----
if [ -f "$CLAUDE_MD" ] && grep -q '^## Worktree discipline' "$CLAUDE_MD"; then
  _teardown_tmp="$(mktemp)"
  awk '
    /^## / { skip = ($0 ~ /^## Worktree discipline[[:space:]]*$/) }
    !skip
  ' "$CLAUDE_MD" > "$_teardown_tmp"
  if grep -q '^## Worktree discipline' "$_teardown_tmp"; then
    echo "teardown: FAILED to remove rule from CLAUDE.md" >&2
    exit 1
  fi
  cp "$_teardown_tmp" "$CLAUDE_MD"
  rm -f "$_teardown_tmp"
  echo "teardown: removed '## Worktree discipline' section from ~/.claude/CLAUDE.md"
  CHANGED=1
else
  echo "teardown: CLAUDE.md rule not present (already clean)"
fi

# ---- Summary ----
if [ "$CHANGED" -eq 1 ]; then
  echo "teardown: done. Reload with /hooks or restart the session."
else
  echo "teardown: nothing to remove — worktree-discipline was not installed."
fi

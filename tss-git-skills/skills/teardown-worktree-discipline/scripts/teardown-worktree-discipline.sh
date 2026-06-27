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

SETTINGS="$HOME/.claude/settings.json"
HOOK_FILE="$HOME/.claude/hooks/worktree-discipline.sh"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"

CHANGED=0

# ---- 1. Deregister the hook from settings.json ----
if [ -f "$SETTINGS" ] && jq -e '[.. | .command? // empty] | any(test("worktree-discipline.sh"))' "$SETTINGS" >/dev/null 2>&1; then
  cp "$SETTINGS" "$SETTINGS.bak"
  jq '
    if (.hooks.PreToolUse | type) == "array" then
        .hooks.PreToolUse |= (
            map(.hooks |= map(select((.command // "") | test("worktree-discipline.sh") | not)))
          | map(select((.hooks | length) > 0))
        )
      | (if (.hooks.PreToolUse | length) == 0 then .hooks |= del(.PreToolUse) else . end)
    else . end
  ' "$SETTINGS.bak" > "$SETTINGS"
  # Verify the entry was actually removed.
  if jq -e '[.. | .command? // empty] | any(test("worktree-discipline.sh"))' "$SETTINGS" >/dev/null 2>&1; then
    echo "teardown: FAILED to remove hook from settings.json — restoring backup" >&2
    cp "$SETTINGS.bak" "$SETTINGS"
    rm -f "$SETTINGS.bak"
    exit 1
  fi
  rm -f "$SETTINGS.bak"
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
  cp "$CLAUDE_MD" "$CLAUDE_MD.bak"
  awk '
    /^## / { skip = ($0 ~ /^## Worktree discipline[[:space:]]*$/) }
    !skip
  ' "$CLAUDE_MD.bak" > "$CLAUDE_MD"
  if grep -q '^## Worktree discipline' "$CLAUDE_MD"; then
    echo "teardown: FAILED to remove rule from CLAUDE.md — restoring backup" >&2
    cp "$CLAUDE_MD.bak" "$CLAUDE_MD"
    rm -f "$CLAUDE_MD.bak"
    exit 1
  fi
  rm -f "$CLAUDE_MD.bak"
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

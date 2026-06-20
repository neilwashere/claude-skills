#!/usr/bin/env bash
# PreToolUse hook on Bash — enforces "main repo dir's HEAD is always main/master".
#
# Reads JSON from stdin. Outputs a deny decision (with reason) on violation,
# or exits 0 silently on allow. Never throws — anything unexpected exits 0
# so the user/agent is never wedged.
#
# What it blocks (only in the main repo dir, i.e. git-dir == git-common-dir):
#   - git checkout -b <branch>
#   - git switch -c <branch>
#   - git checkout <branch>   (where <branch> is not main/master, not a sha, not a file)
#   - git switch <branch>     (same)
#   - git cherry-pick ...     (only valid when already on a feature branch — we aren't here)
#   - git commit/merge/rebase/push  (if HEAD has somehow drifted to a non-default branch)
#
# What it allows:
#   - All operations inside any worktree (git-dir != git-common-dir)
#   - Everything that doesn't start with `git`
#   - git checkout/switch to main or master
#   - git checkout <sha> for inspection (detached HEAD on a sha is fine)
#   - git checkout -- <file> or git checkout HEAD -- <file>
#
# See ~/.claude/CLAUDE.md "Branch discipline" for the rule + rationale.

set -u

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
if [ -z "$COMMAND" ]; then exit 0; fi

# Fast bail: not a git command at all.
if ! echo "$COMMAND" | grep -qE '(^|[[:space:]]|[;|&])git[[:space:]]'; then
  exit 0
fi

# Compute effective cwd at the moment `git` would execute. The agent may chain
# `cd <path> && git ...` in a single Bash invocation, in which case the hook's
# own $PWD is misleading: a `cd` into a worktree before `git checkout -b` should
# be allowed; a `cd` into the main repo dir from a worktree should be denied.
# We walk the command up to the first `git ` token, replaying any `cd <path>`
# segments to derive the dir git would actually run in.
EFFECTIVE_CWD="$PWD"
PRE_GIT="${COMMAND%%git *}"
if [ "$PRE_GIT" != "$COMMAND" ]; then
  REMAINING="$PRE_GIT"
  BASH_REMATCH=()
  while [[ "$REMAINING" =~ (^|[\&\;\|[:space:]])cd[[:space:]]+([^[:space:]\&\;\|()\<\>]+) ]]; do
    TARGET="${BASH_REMATCH[2]}"
    REMAINING="${REMAINING#*${BASH_REMATCH[0]}}"
    case "$TARGET" in
      /*) CAND="$TARGET" ;;
      *)  CAND="$EFFECTIVE_CWD/$TARGET" ;;
    esac
    RESOLVED=$(cd "$CAND" 2>/dev/null && pwd -P) && EFFECTIVE_CWD="$RESOLVED"
  done
fi

# Determine repo state from the effective cwd.
GIT_DIR=$(cd "$EFFECTIVE_CWD" 2>/dev/null && git rev-parse --git-dir 2>/dev/null) || exit 0
GIT_COMMON=$(cd "$EFFECTIVE_CWD" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null) || exit 0
GIT_DIR_ABS=$(cd "$EFFECTIVE_CWD" 2>/dev/null && cd "$GIT_DIR" 2>/dev/null && pwd -P) || GIT_DIR_ABS="$GIT_DIR"
GIT_COMMON_ABS=$(cd "$EFFECTIVE_CWD" 2>/dev/null && cd "$GIT_COMMON" 2>/dev/null && pwd -P) || GIT_COMMON_ABS="$GIT_COMMON"

# Inside a worktree — allow everything. The whole point of worktrees is to be
# where feature work happens.
if [ "$GIT_DIR_ABS" != "$GIT_COMMON_ABS" ]; then
  exit 0
fi

DEFAULT_BRANCHES_RE='^(main|master)$'

emit_deny() {
  local reason="$1"
  jq -n --arg r "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# 1. Creating a branch in the main repo dir.
if echo "$COMMAND" | grep -qE '\bgit[[:space:]]+(checkout[[:space:]]+-b|switch[[:space:]]+-c)\b'; then
  emit_deny "Blocked: creating a branch in the main repo dir. Use 'git worktree add ../<repo>.worktrees/<slug> -b <branch>' (or the user's wt-* helpers), then cd into the worktree before committing. See ~/.claude/CLAUDE.md 'Branch discipline'."
fi

# 2. Switching to an existing branch (not main/master, not a sha, not a file).
SWITCH_CMD=$(echo "$COMMAND" | grep -oE '\bgit[[:space:]]+(checkout|switch)[[:space:]]+[^&;|]*' | head -1 || true)
if [ -n "$SWITCH_CMD" ]; then
  # File-checkout (uses `--`) — allow.
  if echo "$SWITCH_CMD" | grep -q '[[:space:]]--[[:space:]]'; then :
  else
    # First non-flag positional arg.
    TARGET=$(echo "$SWITCH_CMD" \
      | sed -E 's/^[[:space:]]*git[[:space:]]+(checkout|switch)[[:space:]]+//' \
      | awk '{ for (i=1;i<=NF;i++) if ($i !~ /^-/) { print $i; exit } }')
    if [ -n "$TARGET" ]; then
      DENY_SWITCH_MSG="Blocked: switching to branch '$TARGET' in the main repo dir. The main repo dir must stay on main/master. Use a worktree: 'git worktree add ../\$(basename \$PWD).worktrees/$TARGET -b $TARGET' (or cd into an existing worktree at ../\$(basename \$PWD).worktrees/$TARGET). See ~/.claude/CLAUDE.md 'Branch discipline'."
      if echo "$TARGET" | grep -qE "$DEFAULT_BRANCHES_RE"; then :
      elif echo "$TARGET" | grep -qE '^[0-9a-f]{7,40}$'; then :     # sha
      elif (cd "$EFFECTIVE_CWD" 2>/dev/null && git rev-parse --verify --quiet "refs/heads/$TARGET" >/dev/null 2>&1); then
        # Target IS a local branch — deny even if a path of the same name exists.
        # Without this check, `git checkout docs` would be allowed whenever a
        # `docs/` dir exists alongside a `docs` branch (common collision case).
        emit_deny "$DENY_SWITCH_MSG"
      elif [ -e "$EFFECTIVE_CWD/$TARGET" ] || [ -e "$TARGET" ]; then :  # file/dir, not a branch
      else
        emit_deny "$DENY_SWITCH_MSG"
      fi
    fi
  fi
fi

# 3. Cherry-pick — block in main dir unconditionally. Cherry-picks belong on
# feature branches, which live in worktrees.
if echo "$COMMAND" | grep -qE '\bgit[[:space:]]+cherry-pick\b'; then
  emit_deny "Blocked: cherry-pick in the main repo dir. Cherry-picks belong on feature branches — cd into the worktree first. See ~/.claude/CLAUDE.md 'Branch discipline'."
fi

# 4. Bad-state catch: if HEAD has drifted to a non-default branch (e.g. a previous
# bypass), block any write op that would compound the damage.
CURRENT_BRANCH=$(cd "$EFFECTIVE_CWD" 2>/dev/null && git branch --show-current 2>/dev/null || true)
if [ -n "$CURRENT_BRANCH" ] && ! echo "$CURRENT_BRANCH" | grep -qE "$DEFAULT_BRANCHES_RE"; then
  if echo "$COMMAND" | grep -qE '\bgit[[:space:]]+(commit|merge|rebase|push|cherry-pick)\b'; then
    emit_deny "Blocked: '$COMMAND' in the main repo dir while HEAD is on '$CURRENT_BRANCH' (should be main/master). Main repo dir is in a bad state. Switch back: 'git checkout main' here, then continue your work in the worktree. See ~/.claude/CLAUDE.md 'Branch discipline'."
  fi
fi

exit 0

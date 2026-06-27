#!/usr/bin/env bash
# PreToolUse hook — enforce worktree discipline in OPTED-IN repos.
#
# Matched on Write|Edit|NotebookEdit|Bash. Reads the tool call as JSON on stdin.
# Emits a deny decision (with reason) on violation, else exits 0 silently.
# Never throws — anything unexpected exits 0 so the agent is never wedged.
#
# OPT-IN per repo (off by default everywhere):
#   <repo>/.claude/worktree-discipline.json        {"enforce": true, "allowPaths": ["CHANGELOG.md", ".changeset/**"]}
#   <repo>/.claude/worktree-discipline.local.json  (gitignored) overrides the committed marker per-checkout
# No marker, or enforce:false  ->  this hook does nothing.
#
# In an ENFORCED MAIN checkout (git-dir == git-common-dir) it DENIES:
#   - Write / Edit / NotebookEdit to any path in the tree
#       (except the marker files, anything under .git/, and allowPaths globs)
#   - git checkout -b / switch -c / branch switch / cherry-pick
#   - git commit|merge|rebase|push while HEAD has drifted off main/master
#   - best-effort: Bash > / >> / tee / sed -i writes that resolve into the tree
# It ALWAYS ALLOWS: anything inside a worktree (git-dir != git-common-dir),
# anything outside a git repo, and everything in a non-enforced repo.
#
# See ~/.claude/CLAUDE.md "Worktree discipline" for the rule + rationale.

set -u

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ -z "$TOOL" ] && exit 0

emit_deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

ENTER_MSG="Create and enter a worktree first: run /create-and-enter-worktree (it creates a sibling worktree off origin/<default>, then relocates the session with the EnterWorktree tool). Do NOT 'cd' into a worktree — the harness reverts cwd after every Bash call, so writes still land in the main checkout."

# ---------------------------------------------------------------------------
# 1. Resolve the directory the operation actually targets.
# ---------------------------------------------------------------------------
FILE=""
COMMAND=""
case "$TOOL" in
  Write|Edit|NotebookEdit)
    FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null)
    [ -z "$FILE" ] && exit 0
    case "$FILE" in /*) ;; *) FILE="$PWD/$FILE" ;; esac
    TARGET_DIR=$(dirname "$FILE")
    ;;
  Bash)
    COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
    [ -z "$COMMAND" ] && exit 0
    # Effective cwd: replay any `cd <path>` segments before the operation, so a
    # `cd ../wt && git ...` is judged in the worktree, and `cd <main> && ...`
    # from a worktree is judged in main.
    EFFECTIVE_CWD="$PWD"
    REMAINING="$COMMAND"
    BASH_REMATCH=()
    while [[ "$REMAINING" =~ (^|[\&\;\|[:space:]])cd[[:space:]]+([^[:space:]\&\;\|()\<\>]+) ]]; do
      TGT="${BASH_REMATCH[2]}"
      REMAINING="${REMAINING#*${BASH_REMATCH[0]}}"
      case "$TGT" in
        /*) CAND="$TGT" ;;
        *)  CAND="$EFFECTIVE_CWD/$TGT" ;;
      esac
      RES=$(cd "$CAND" 2>/dev/null && pwd -P) && EFFECTIVE_CWD="$RES"
    done
    TARGET_DIR="$EFFECTIVE_CWD"
    ;;
  *) exit 0 ;;
esac

# ---------------------------------------------------------------------------
# 2. Locate the repo and detect worktree vs main checkout.
# ---------------------------------------------------------------------------
# A Write/Edit may target a not-yet-existing directory (e.g. creating a file in
# a brand-new subdir). Walk TARGET_DIR up to the nearest existing ancestor so the
# `cd` below succeeds and enforcement still applies — otherwise a failing `cd`
# would hit `|| exit 0` and silently allow the write (enforcement bypass).
while [ -n "$TARGET_DIR" ] && [ ! -d "$TARGET_DIR" ]; do TARGET_DIR=$(dirname "$TARGET_DIR"); done
TOPLEVEL=$(cd "$TARGET_DIR" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || exit 0
GIT_DIR=$(cd "$TARGET_DIR" 2>/dev/null && git rev-parse --git-dir 2>/dev/null) || exit 0
GIT_COMMON=$(cd "$TARGET_DIR" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null) || exit 0
GIT_DIR_ABS=$(cd "$TARGET_DIR" 2>/dev/null && cd "$GIT_DIR" 2>/dev/null && pwd -P) || GIT_DIR_ABS="$GIT_DIR"
GIT_COMMON_ABS=$(cd "$TARGET_DIR" 2>/dev/null && cd "$GIT_COMMON" 2>/dev/null && pwd -P) || GIT_COMMON_ABS="$GIT_COMMON"

# Inside a worktree — allow everything. Worktrees are where work belongs.
[ "$GIT_DIR_ABS" != "$GIT_COMMON_ABS" ] && exit 0

# ---------------------------------------------------------------------------
# 3. Opt-in marker (local override wins). Bail unless enforce == true.
# ---------------------------------------------------------------------------
MARKER="$TOPLEVEL/.claude/worktree-discipline.json"
LOCAL="$TOPLEVEL/.claude/worktree-discipline.local.json"
ACTIVE=""
if   [ -f "$LOCAL" ];  then ACTIVE="$LOCAL"
elif [ -f "$MARKER" ]; then ACTIVE="$MARKER"
fi
[ -z "$ACTIVE" ] && exit 0
ENFORCE=$(jq -r '.enforce // false' "$ACTIVE" 2>/dev/null)
[ "$ENFORCE" = "true" ] || exit 0
ALLOWPATHS=$(jq -r '(.allowPaths // [])[]' "$ACTIVE" 2>/dev/null)

# True if $1 (path relative to repo root) is exempt: a marker file, under .git/,
# or matching an allowPaths glob.
is_allowed_path() {
  local rel="$1"
  case "$rel" in
    .claude/worktree-discipline.json|.claude/worktree-discipline.local.json|.claude/worktree-config.json|.claude/worktree-config.local.json) return 0 ;;
    .git/*) return 0 ;;
  esac
  local g
  while IFS= read -r g; do
    [ -z "$g" ] && continue
    # shellcheck disable=SC2254
    case "$rel" in $g) return 0 ;; esac
  done <<< "$ALLOWPATHS"
  return 1
}

# ---------------------------------------------------------------------------
# 4a. File-writing tools — deny writes into the enforced main checkout.
# ---------------------------------------------------------------------------
if [ "$TOOL" = "Write" ] || [ "$TOOL" = "Edit" ] || [ "$TOOL" = "NotebookEdit" ]; then
  REL="${FILE#"$TOPLEVEL"/}"
  is_allowed_path "$REL" && exit 0
  emit_deny "Worktree discipline: this repo blocks direct writes to its main checkout ($TOPLEVEL). $ENTER_MSG  To allow this path on main, add it to allowPaths in .claude/worktree-discipline.json, or set {\"enforce\": false} in .claude/worktree-discipline.local.json (gitignored)."
fi

# ---------------------------------------------------------------------------
# 4b. Bash — git branch ops, drifted-HEAD writes, best-effort file writes.
# ---------------------------------------------------------------------------
if [ "$TOOL" = "Bash" ]; then
  DEFAULT_RE='^(main|master)$'

  is_git=0
  printf '%s' "$COMMAND" | grep -qE '(^|[[:space:]]|[;|&])git[[:space:]]' && is_git=1

  if [ "$is_git" = "1" ]; then
    # Creating a branch.
    if printf '%s' "$COMMAND" | grep -qE '\bgit[[:space:]]+(checkout[[:space:]]+-b|switch[[:space:]]+-c)\b'; then
      emit_deny "Worktree discipline: blocked creating a branch in the main checkout. $ENTER_MSG"
    fi
    # Switching to an existing non-default branch (not a sha, not a file).
    SWITCH=$(printf '%s' "$COMMAND" | grep -oE '\bgit[[:space:]]+(checkout|switch)[[:space:]]+[^&;|]*' | head -1 || true)
    if [ -n "$SWITCH" ] && ! printf '%s' "$SWITCH" | grep -q '[[:space:]]--[[:space:]]'; then
      TARGET=$(printf '%s' "$SWITCH" | sed -E 's/^[[:space:]]*git[[:space:]]+(checkout|switch)[[:space:]]+//' \
        | awk '{ for (i=1;i<=NF;i++) if ($i !~ /^-/) { print $i; exit } }')
      if [ -n "$TARGET" ]; then
        if printf '%s' "$TARGET" | grep -qE "$DEFAULT_RE"; then :
        elif printf '%s' "$TARGET" | grep -qE '^[0-9a-f]{7,40}$'; then :
        elif (cd "$EFFECTIVE_CWD" 2>/dev/null && git rev-parse --verify --quiet "refs/heads/$TARGET" >/dev/null 2>&1); then
          emit_deny "Worktree discipline: blocked switching to branch '$TARGET' in the main checkout — it must stay on main/master. Enter a worktree for '$TARGET' instead: EnterWorktree({path}) on its worktree, or /create-and-enter-worktree $TARGET."
        elif [ -e "$EFFECTIVE_CWD/$TARGET" ] || [ -e "$TARGET" ]; then :
        else
          emit_deny "Worktree discipline: blocked switching to branch '$TARGET' in the main checkout — it must stay on main/master. Enter a worktree for '$TARGET' instead: EnterWorktree({path}) on its worktree, or /create-and-enter-worktree $TARGET."
        fi
      fi
    fi
    # Cherry-pick belongs on a feature branch (i.e. in a worktree).
    if printf '%s' "$COMMAND" | grep -qE '\bgit[[:space:]]+cherry-pick\b'; then
      emit_deny "Worktree discipline: blocked cherry-pick in the main checkout — cherry-picks belong on a feature branch. Enter the worktree first (EnterWorktree)."
    fi
    # Bad-state catch: HEAD already drifted off the default branch.
    CUR=$(cd "$EFFECTIVE_CWD" 2>/dev/null && git branch --show-current 2>/dev/null || true)
    if [ -n "$CUR" ] && ! printf '%s' "$CUR" | grep -qE "$DEFAULT_RE"; then
      if printf '%s' "$COMMAND" | grep -qE '\bgit[[:space:]]+(commit|merge|rebase|push|cherry-pick)\b'; then
        emit_deny "Worktree discipline: main checkout is in a bad state — HEAD is on '$CUR' (should be main/master). Run 'git checkout main' here, then continue your work in the worktree (EnterWorktree)."
      fi
    fi
  fi

  # Best-effort: shell file-writes that resolve INTO the tree. Catches the common
  # > / >> / tee / sed -i vectors; not a complete guard (complex pipelines, cp/mv,
  # dd, python -c open(), etc. can still slip through — the Write/Edit block above
  # is the robust layer).
  # The char before '>' must not be 0-9 > & = - : excluding '=' and '-' stops the
  # operators '=>' and '->' (in echo strings, awk/perl/js one-liners) being misread
  # as a redirect into a file named after the following word (false-positive deny).
  #
  # sed -i edge cases (documented, not fixable with regex alone):
  #   - sed -i.bak 's/x/y/' file   → the "last token" heuristic extracts ".bak",
  #     not "file", so the write is missed. The Write/Edit block covers this path.
  #   - sed -i 's/x/y/' file1 file2 → only file2 (the last token) is checked;
  #     file1 is missed. Multi-file sed -i writes are rare but possible.
  CANDS=$(
    printf '%s' "$COMMAND" | grep -oE '(^|[^0-9>&=-])>>?[[:space:]]*[^[:space:]><|&;()]+' | sed -E 's/.*>>?[[:space:]]*//'
    printf '%s' "$COMMAND" | grep -oE '\btee[[:space:]]+(-a[[:space:]]+)?[^[:space:]><|&;()]+' | sed -E 's/.*tee[[:space:]]+(-a[[:space:]]+)?//'
    if printf '%s' "$COMMAND" | grep -qE '\bsed[[:space:]]+(-[a-zA-Z]*i|--in-place)'; then
      printf '%s' "$COMMAND" | grep -oE '[^[:space:]><|&;()]+$'
    fi
  )
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    case "$t" in
      /dev/*|/tmp/*|/var/tmp/*) continue ;;
      \~*) continue ;;
      /*) cabs="$t" ;;
      *)  cabs="$EFFECTIVE_CWD/$t" ;;
    esac
    case "$cabs" in
      "$TOPLEVEL"/*)
        rel="${cabs#"$TOPLEVEL"/}"
        is_allowed_path "$rel" && continue
        emit_deny "Worktree discipline: this Bash command writes into the main checkout ('$t' -> $TOPLEVEL). $ENTER_MSG"
        ;;
    esac
  done <<< "$CANDS"
fi

exit 0

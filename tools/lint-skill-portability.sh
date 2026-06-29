#!/usr/bin/env bash
# lint-skill-portability.sh — heuristic guard: a SKILL.md body must not name a
# Claude-only tool OUTSIDE a "(Claude Code: ...)" hint. Scans body lines that are
# not inside ``` fenced blocks. Advisory but CI-enforced; relax by adding the
# hint or rephrasing in capability terms.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TOOLS_RE='EnterWorktree|ExitWorktree|AskUserQuestion|TodoWrite'
rc=0

for skill_md in "$ROOT"/skills/*/SKILL.md; do
  in_fm=0; seen_fm=0; in_fence=0; lineno=0
  while IFS= read -r line; do
    lineno=$((lineno+1))
    # skip frontmatter
    if [ "$seen_fm" -lt 2 ] && [ "$line" = "---" ]; then seen_fm=$((seen_fm+1)); in_fm=$((in_fm^1)); continue; fi
    [ "$seen_fm" -lt 2 ] && continue
    case "$line" in '```'*) in_fence=$((in_fence^1)); continue ;; esac
    [ "$in_fence" -eq 1 ] && continue
    if printf '%s' "$line" | grep -Eq "$TOOLS_RE"; then
      case "$line" in *"Claude Code"*) : ;; *)
        printf 'FAIL %s:%s names a Claude-only tool without a (Claude Code: ...) hint:\n  %s\n' \
          "${skill_md#"$ROOT"/}" "$lineno" "$line" >&2; rc=1 ;;
      esac
    fi
  done < "$skill_md"
done

[ "$rc" -eq 0 ] && echo "portability lint: clean"
exit "$rc"

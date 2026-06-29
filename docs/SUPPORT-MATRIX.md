# Support matrix

How each skill behaves per harness. **✔ full** · **◐ degraded** (loads and partly works) · **✖ n/a** (Claude-only mechanism). Claude Code is the only first-class, tested target; non-Claude columns are best-effort and, unless noted, smoke-tested at most once — treat them as "should load," not "verified."

| Skill | Claude Code | Codex | Gemini / Antigravity | Copilot | Pi |
|---|---|---|---|---|---|
| configure-worktree | ✔ | ✔ ¹ | ✔ ¹ | ✔ ¹ | ✔ ¹ |
| create-and-enter-worktree | ✔ | ◐ ² | ◐ ² | ◐ ² | ◐ ² |
| exit-and-dispose-worktree | ✔ | ◐ ³ | ◐ ³ | ◐ ³ | ◐ ³ |
| worktree-enforce | ✔ | ◐ ⁴ | ◐ ⁴ | ◐ ⁴ | ◐ ⁴ |
| setup-worktree-discipline | ✔ | ✖ ⁵ | ✖ ⁵ | ✖ ⁵ | ✖ ⁵ |
| teardown-worktree-discipline | ✔ | ✖ ⁵ | ✖ ⁵ | ✖ ⁵ | ✖ ⁵ |

1. Writes the worktree-config marker via a bundled script; the only difference off-Claude is the questions are asked in chat instead of a dedicated question tool.
2. Creates the worktree via `wt-new.sh`, but there is no session-relocation tool outside Claude Code — you `cd` in / open a session in the printed path yourself.
3. `wt-rm.sh` removes the tree with its dirty/unpushed guard, but you leave the worktree session manually (no `ExitWorktree`).
4. Marker management (`in`/`out`/`status`) is portable shell; the enforcement those markers toggle is applied only by the Claude Code `PreToolUse` hook from setup-worktree-discipline.
5. Pure Claude Code mechanism: a `PreToolUse` hook plus `~/.claude` integration. No other harness has an equivalent pre-write enforcement primitive. A git pre-commit/pre-push fallback is a possible future addition (out of scope here).

## Why some behaviour can't port

`SKILL.md` is a cross-vendor format, but two capabilities these skills use have no uniform equivalent: **session relocation** (moving the agent's working directory mid-session) and **pre-tool write enforcement** (denying writes before they happen). Claude Code provides both; most harnesses provide neither. The skills are authored so they still *load* everywhere and degrade to the portable subset.

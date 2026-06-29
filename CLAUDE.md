@AGENTS.md

## Claude-specific notes

This repo ships as a Claude Code marketplace plugin (`.claude-plugin/`), installable with `/plugin install git-worktree-skills@neilwashere`. Claude Code is the first-class target: skills work fully here (session relocation via `EnterWorktree`/`ExitWorktree`, write-enforcement via the `PreToolUse` hook). See `docs/SUPPORT-MATRIX.md` for behaviour on other harnesses.

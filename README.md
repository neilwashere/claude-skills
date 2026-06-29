# git-worktree-skills

Portable git/worktree workflow skills — branch discipline and worktree create / enter / dispose — authored to the open [Agent Skills](https://agentskills.io/specification) (`SKILL.md`) standard. Loadable in Claude Code (first-class), and in Codex, Gemini, Copilot, and Pi (best-effort; see the [support matrix](./docs/SUPPORT-MATRIX.md)).

## Install

**Claude Code (plugin):**

```bash
/plugin marketplace add neilwashere/git-worktree-skills
/plugin install git-worktree-skills@neilwashere
```

For live, git-synced local development: `/plugin marketplace add /path/to/git-worktree-skills`.

**Any other harness (neutral):**

```bash
git clone https://github.com/neilwashere/git-worktree-skills
cd git-worktree-skills && ./install.sh        # symlinks into ~/.agents/skills and ~/.claude/skills
# ./install.sh --copy        # if your environment can't use symlinks
# ./install.sh --uninstall   # remove what it installed
```

Your harness then discovers the skills from `~/.agents/skills/` or `~/.claude/skills/`.

## Skills

**User-invoked** (reachable only when you type them — `disable-model-invocation: true`):

- **[setup-worktree-discipline](./skills/setup-worktree-discipline/SKILL.md)** — *Claude Code only:* install a `PreToolUse` hook making an opted-in main checkout read-only, plus the global CLAUDE.md rule.
- **[teardown-worktree-discipline](./skills/teardown-worktree-discipline/SKILL.md)** — *Claude Code only:* the clean reverse of setup; run before `/plugin uninstall`.
- **[worktree-enforce](./skills/worktree-enforce/SKILL.md)** — opt the current repo `in`/`out`, show `status`, or run `doctor`. Marker management is portable; enforcement is applied by the Claude hook.
- **[configure-worktree](./skills/configure-worktree/SKILL.md)** — guided setup of the worktree-config marker (location, mirrored files, post-create command, branch naming).

**Model-invoked** (model- or user-reachable):

- **[create-and-enter-worktree](./skills/create-and-enter-worktree/SKILL.md)** — create a sibling worktree off `origin/<default>` and relocate into it (auto on Claude Code; `cd` in elsewhere).
- **[exit-and-dispose-worktree](./skills/exit-and-dispose-worktree/SKILL.md)** — after a PR merges, leave the worktree session then remove the tree (refuses if dirty/unpushed).

## Contributing

Contributor guidance lives in **[AGENTS.md](./AGENTS.md)** (read by any harness). It points to **[docs/contributing/closing-the-verification-loop.md](./docs/contributing/closing-the-verification-loop.md)** — the verification habits this repo expects.

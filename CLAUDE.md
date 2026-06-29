This repo is a Claude Code **marketplace** hosting two plugins: `tss-git-skills` (git/worktree workflow skills, invoking as `tss-git-skills:<skill-name>`) and `tss-review-skills` (review → learning corpus skills, invoking as `tss-review-skills:<skill-name>`). Each plugin lives in its own subtree (`./tss-git-skills/`, `./tss-review-skills/`) with a flat `skills/` and its own `README.md`; the repo root holds only the marketplace manifest.

Why the subtree / flat `skills/`: Claude Code auto-scans a plugin's `skills/` at depth-1, so a flat `skills/` is auto-discovered and `tss-git-skills/.claude-plugin/plugin.json` needs no `skills` array (and no `hooks`/`commands` keys unless it ships plugin-level ones).

`tss-git-skills/README.md` lists every skill, grouped **User-invoked** / **Model-invoked**, each name linked to its `SKILL.md`. Every `SKILL.md` is either user-invoked (`disable-model-invocation: true`, reachable only by the human) or model-invoked (model- or user-reachable).

## Install

From GitHub:

```
/plugin marketplace add neilwashere/claude-skills
/plugin install tss-git-skills@neilwashere
```

For live, git-synced local development, point the marketplace at your checkout instead: `/plugin marketplace add /path/to/claude-skills`.

## Contributor guidance

When writing or reviewing code here, follow the [contributor lessons index](./docs/contributing/lessons/INDEX.md): make tests falsifiable (watch them fail before trusting them), verify behaviour by running it rather than describing it, treat tool versions / platform / CI merge-commit semantics as inputs rather than constants, and design the failure path of every destructive operation (guard-then-act, write-to-temp-then-rename, never half-complete or report success on a swallowed error).

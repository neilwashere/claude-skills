This repo is a Claude Code **marketplace** hosting a single plugin, `tss-git-skills`, whose skills invoke as `tss-git-skills:<skill-name>`. The plugin lives in its own subtree `./tss-git-skills/` with a flat `skills/` and its own `README.md`; the repo root holds only the marketplace manifest.

Why the subtree / flat `skills/`: Claude Code auto-scans a plugin's `skills/` at depth-1, so a flat `skills/` is auto-discovered and `tss-git-skills/.claude-plugin/plugin.json` needs no `skills` array (and no `hooks`/`commands` keys unless it ships plugin-level ones).

`tss-git-skills/README.md` lists every skill, grouped **User-invoked** / **Model-invoked**, each name linked to its `SKILL.md`. Every `SKILL.md` is either user-invoked (`disable-model-invocation: true`, reachable only by the human) or model-invoked (model- or user-reachable).

## Install

From GitHub:

```
/plugin marketplace add neilwashere/claude-skills
/plugin install tss-git-skills@threadsafe
```

For live, git-synced local development, point the marketplace at your checkout instead: `/plugin marketplace add /path/to/claude-skills`.

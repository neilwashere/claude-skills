This repo is a Claude Code **marketplace** hosting multiple plugins. `threadsafe` is the general catch-all plugin at the repo root (`source: "."`); its skills invoke as `threadsafe:<skill-name>`. Every **other** domain is its own plugin named `tss-<domain>` (e.g. `tss-git-skills`), living in a self-contained subtree `./tss-<domain>/` with a flat `skills/` and its own `README.md`; its skills invoke as `tss-<domain>:<skill-name>`.

Why the subtree: Claude Code auto-scans each plugin's `skills/` at depth-1. Keeping every `tss-<domain>` plugin in its own subtree means the root `threadsafe` scan never reaches into it, so the two never collide. A flat `skills/` is auto-discovered, so a domain plugin's `plugin.json` needs no `skills` array (and no `hooks`/`commands` keys unless it ships plugin-level ones).

Skills are organized into bucket folders under `skills/`:

- `engineering/` — daily code work
- `productivity/` — daily non-code workflow tools
- `misc/` — kept around but rarely used
- `personal/` — tied to my own setup, not promoted
- `in-progress/` — drafts not yet ready to ship
- `deprecated/` — no longer used

Every skill in `engineering/`, `productivity/`, or `misc/` must have a reference in the top-level `README.md` and an entry in `.claude-plugin/plugin.json`. Skills in `personal/`, `in-progress/`, and `deprecated/` must not appear in either. These bucket rules apply to the `threadsafe` plugin only. A `tss-<domain>` plugin instead uses a flat `skills/` and lists its skills in its own `tss-<domain>/README.md` (no top-level README or threadsafe `plugin.json` entry).

## Subsystems (exception to the bucket rule)

A skill that ships plugin-level **hooks** or **commands** may live at `skills/<name>/` (outside the buckets) when its hook/command paths must stay stable. `skills/continuous-learning-v2/` (the instincts subsystem) is the one such case: its `hooks/hooks.json` references `${CLAUDE_PLUGIN_ROOT}/skills/continuous-learning-v2/...`, so moving it under a bucket would break those paths. Plugin-level `hooks/` and `commands/` sit at the repo root and are wired via the `"hooks"` and `"commands"` keys in `.claude-plugin/plugin.json`. Subsystems are still listed in `plugin.json` and referenced from the top-level `README.md` (under a **Subsystems** heading), but not from a bucket `README.md`.

Each skill entry in the top-level `README.md` must link the skill name to its `SKILL.md`.

Each bucket folder has a `README.md` that lists every skill in the bucket with a one-line description, with the skill name linked to its `SKILL.md`. Bucket `README.md`s and the top-level `README.md` group entries into **User-invoked** and **Model-invoked**.

Every `SKILL.md` is either user-invoked (`disable-model-invocation: true`, reachable only by the human) or model-invoked (model- or user-reachable). For the full definitions, description conventions, and why a user-invoked skill can invoke model-invoked skills but never another user-invoked one, see [docs/invocation.md](./docs/invocation.md).

## Install

From GitHub:

```
/plugin marketplace add neilwashere/claude-skills
/plugin install threadsafe@threadsafe
/plugin install tss-git-skills@threadsafe
```

For live, git-synced local development, point the marketplace at your checkout instead: `/plugin marketplace add /path/to/claude-skills`.

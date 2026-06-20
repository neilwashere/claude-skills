This repo is a **single Claude Code plugin** named `threadsafe`. Every skill here invokes as `threadsafe:<skill-name>` once the plugin is installed.

Skills are organized into bucket folders under `skills/`:

- `engineering/` — daily code work
- `productivity/` — daily non-code workflow tools
- `misc/` — kept around but rarely used
- `personal/` — tied to my own setup, not promoted
- `in-progress/` — drafts not yet ready to ship
- `deprecated/` — no longer used

Every skill in `engineering/`, `productivity/`, or `misc/` must have a reference in the top-level `README.md` and an entry in `.claude-plugin/plugin.json`. Skills in `personal/`, `in-progress/`, and `deprecated/` must not appear in either.

## Subsystems (exception to the bucket rule)

A skill that ships plugin-level **hooks** or **commands** may live at `skills/<name>/` (outside the buckets) when its hook/command paths must stay stable. `skills/continuous-learning-v2/` (the instincts subsystem) is the one such case: its `hooks/hooks.json` references `${CLAUDE_PLUGIN_ROOT}/skills/continuous-learning-v2/...`, so moving it under a bucket would break those paths. Plugin-level `hooks/` and `commands/` sit at the repo root and are wired via the `"hooks"` and `"commands"` keys in `.claude-plugin/plugin.json`. Subsystems are still listed in `plugin.json` and referenced from the top-level `README.md` (under a **Subsystems** heading), but not from a bucket `README.md`.

Each skill entry in the top-level `README.md` must link the skill name to its `SKILL.md`.

Each bucket folder has a `README.md` that lists every skill in the bucket with a one-line description, with the skill name linked to its `SKILL.md`. Bucket `README.md`s and the top-level `README.md` group entries into **User-invoked** and **Model-invoked**.

Every `SKILL.md` is either user-invoked (`disable-model-invocation: true`, reachable only by the human) or model-invoked (model- or user-reachable). For the full definitions, description conventions, and why a user-invoked skill can invoke model-invoked skills but never another user-invoked one, see [docs/invocation.md](./docs/invocation.md).

## Install

Local-directory marketplace (edits are live, git-synced):

```
/plugin marketplace add /home/neil/code/threadsafe/claude-skills
/plugin install threadsafe@threadsafe
```

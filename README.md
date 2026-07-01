# claude-skills

A Claude Code **marketplace** hosting the `tss-git-skills` plugin — a curated set of
git worktree workflow skills that enforce branch discipline and streamline
worktree create / enter / dispose.

Skills invoke as `tss-git-skills:<skill>` once the plugin is installed.

## Install

From GitHub:

```bash
/plugin marketplace add neilwashere/claude-skills
/plugin install tss-git-skills@neilwashere
```

For live, git-synced local development, point the marketplace at your checkout:

```bash
/plugin marketplace add /path/to/claude-skills
```

## Skills

See **[tss-git-skills/README.md](./tss-git-skills/README.md)** for the full
reference — user-invoked skills (setup, teardown, enforcement, config) and
model-invoked skills (create-and-enter, exit-and-dispose), plus configuration
details.

## Contributing

Before opening a PR, read the
**[contributor lessons index](./docs/contributing/lessons/INDEX.md)**
— atomic lessons on the verification habits this repo expects: tests that
can actually fail, behaviour that's observed rather than described, treating tool
versions / platform / CI semantics as inputs, and designing the failure path of
every destructive operation.

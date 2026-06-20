# Threadsafe Skills

My personal Claude Code skills — engineering and productivity workflows I use day to day.

This repo is a **single plugin** named `threadsafe`, so every skill invokes as `threadsafe:<skill>` (e.g. `threadsafe:tdd`, `threadsafe:review`). Skills are small, composable, and meant to be hacked on.

## Install

Install as a local-directory marketplace so your edits stay live and git-synced:

```bash
/plugin marketplace add /home/neil/code/threadsafe/claude-skills
/plugin install threadsafe@threadsafe
```

## Reference

Skills are split into **User-invoked** (reachable only when you type them — `disable-model-invocation: true`) and **Model-invoked** (model- or user-reachable). See [docs/invocation.md](./docs/invocation.md) for the distinction.

### Engineering

_No skills yet._

### Productivity

_No skills yet._

### Misc

_No skills yet._

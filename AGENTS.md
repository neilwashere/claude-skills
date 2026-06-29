# Repository guide for agents

This repo hosts **git-worktree-skills** — portable git/worktree workflow skills authored to the open Agent Skills (`SKILL.md`) standard, loadable across Claude Code, Codex, Gemini, Copilot, and Pi.

## Layout

- `skills/<skill>/SKILL.md` — one skill each; bundled scripts under `scripts/`. The repo root *is* the Claude plugin root, so Claude auto-discovers `skills/` at depth-1.
- `lib/worktree-config.sh` — shared config resolver, sourced by the worktree scripts.
- `.claude-plugin/` — Claude marketplace + plugin manifests (the Claude packaging layer).
- `install.sh` — neutral installer for every other harness (symlinks/copies skills into `~/.agents/skills/` and `~/.claude/skills/`).
- `docs/SUPPORT-MATRIX.md` — per-skill × per-harness behaviour. `docs/harness-tools.md` — capability → tool-name map.

## Portability rules (when editing skills)

- Write SKILL.md **bodies in capabilities**, not tool names. Mark anything harness-specific as `(Claude Code: <tool/command>)`. Never make `$CLAUDE_PLUGIN_ROOT` the only way to find a bundled script.
- Keep frontmatter to the open standard: `name` (== dir name), `description` (≤1024), optional `license`/`compatibility` (≤500)/`metadata`. `disable-model-invocation` is Claude-only but kept on the four user-invoked skills.
- Bundled `scripts/*.sh` are the portability layer — push harness-specific behaviour into them; they self-locate `lib/` (`pwd -P`, with a vendored sibling fallback for `--copy`).

## Verification expectations

Follow [docs/contributing/closing-the-verification-loop.md](./docs/contributing/closing-the-verification-loop.md): make tests falsifiable (watch them fail first), verify behaviour by running it, treat tool versions / platform / CI semantics as inputs, and design the failure path of every destructive operation (guard-then-act, write-to-temp-then-rename, never half-complete or report success on a swallowed error). Before a PR: `bash tests/run.sh`, `bash tools/validate-frontmatter.sh`, `bash tools/lint-skill-portability.sh`, and shellcheck all `*.sh`.

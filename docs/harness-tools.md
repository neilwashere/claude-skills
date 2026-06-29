# Harness tool map

Skill bodies speak in **capabilities**, not tool names. This is the lookup from capability to each harness's tool, so a reader can translate. Claude Code is authoritative (first-class target); other columns are best-effort pointers from public docs and may drift.

| Capability | Claude Code | Codex CLI | Gemini CLI | Copilot CLI |
|---|---|---|---|---|
| Run a shell command | `Bash` | `shell` | `run_shell_command` | `bash` |
| Read a file | `Read` | `shell` (cat) | `read_file` | `view` |
| Create a file | `Write` | `apply_patch` | `write_file` | `apply_patch` |
| Edit a file | `Edit` | `apply_patch` | `replace` | `apply_patch` |
| Ask the user a question | `AskUserQuestion` | (prompt in chat) | (prompt in chat) | (prompt in chat) |
| Invoke another skill | `Skill` | native / `$name` | `activate_skill` | `skill` |
| Relocate the session (cwd) | `EnterWorktree` / `ExitWorktree` | — (none; `cd`) | — (none; `cd`) | — (none; `cd`) |
| Track a checklist | `TodoWrite` | `update_plan` | `write_todos` | `update_todo` |

**The two rows that matter for this repo** are session relocation (no tool outside Claude Code) and pre-tool enforcement (a Claude Code `PreToolUse` hook, no row above because no harness exposes it as a callable tool). Everything else is reachable everywhere via *some* shell, which is why the bundled `scripts/*.sh` are the real portability layer.

Sources: per-vendor skill docs current to mid-2026; see the design spec `docs/superpowers/specs/2026-06-29-harness-agnostic-skills-design.md`.

# AGENTS.md

ark.nvim: Neovim plugin (Lua, Neovim ≥ 0.11.7) that sends editor context to a coding agent CLI running in an adjacent tmux pane. See `README.md` for behavior.

## Project Instructions

- Fail loudly with `error("ark: ...")`. Do not add silent fallbacks.
- Keep harness-specific differences inside the adapters in `harnesses.lua`.
- User-facing changes (commands, keymaps, options, adapter fields) must be reflected in `README.md`.

## Layout

- `plugin/ark.lua`: user commands only. Lazily requires the modules.
- `lua/ark/init.lua`: `setup` (including default keymaps), `edit`, `chat`, `pick_harness`, and harness launch.
- `lua/ark/config.lua`: defaults and option merging.
- `lua/ark/harnesses.lua`: built-in harness adapters (claude, codex, agy, pi). The field contract is documented at the top.
- `lua/ark/picker.lua`: multi-step Telescope picker. Steps swap in the same window.
- `lua/ark/state.lua`: the persisted harness/model/effort selection (`stdpath("state")/ark.json`).
- `lua/ark/context.lua`: builds the `<editor_context>` block.
- `lua/ark/tmux.lua`: all tmux calls. The agent pane is found via the `@ark_root` pane option, with no in-memory session state.
- `lua/ark/sync.lua`: `checktime` timer for reloading agent-edited buffers.
- `instructions.md`: static instructions given to every agent at launch.
- `.agents/skills/`: repo skills (`.claude/skills` links to it).

## Testing

Run `python3 tests/run.py` (requires Neovim, tmux, Python 3, Git and network access). It downloads Telescope and Plenary into a temporary directory and exercises the plugin with a fake agent on an isolated tmux server. `.github/workflows/ci.yml` runs the suite on Linux and macOS with Neovim 0.11.7 and stable. Keep checks credential-free; real-agent runs are manual.

## Changelog

`CHANGELOG.md`. Add an entry under `## [Unreleased]` with every user-facing change, in the subsections `### Breaking Changes`, `### Added`, `### Changed`, `### Fixed`, `### Removed`. Read the section first and append to existing subsections. Released sections (`## [X.Y.Z] - date`) are immutable.

## Releasing

For versioning, release preparation, publishing, or recovering a failed release, load and follow [.agents/skills/release/SKILL.md](.agents/skills/release/SKILL.md).

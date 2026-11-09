# Changelog

## [Unreleased]

### Breaking Changes

- Replaced adjacent agent panes with detached background sessions shared by working directory on the tmux server; `:ArkChat` now opens a centered floating terminal
- Replaced `pane.size` with fractional `window.width` and `window.height` options (defaults 0.85 and 0.8); the removed `pane` option raises an error

### Added

- Added Ctrl-C to hide the agent window in terminal/normal mode, and normal-mode `q` to hide it; hiding leaves the agent working
- Added a resizable floating terminal viewer that reconnects to the background conversation after hiding or restarting Neovim

- Added `:ArkStatus` for the project, live pane, running selection, saved preference and last errors, plus `:checkhealth ark` for dependency and configuration checks
- Added `:ArkReview` with preserved editor/before and disk snapshots in read-only diff tabs, and confirmed `:ArkResolve disk|buffer` actions that reject changes made during confirmation and can recreate deleted files from the buffer
- Added `:ArkHarness!` to refresh the selected harness's model catalog and `catalog_timeout_ms` (default 10000)
- Added root-scoped sync lifecycle/status APIs and `ArkSyncConflict`/`ArkSyncReload` events, including previous buffer lines on reload
- Added credential-free focused sync tests and a deterministic work regression check across 256 loaded files

### Changed

- Unified opening the agent under `:ArkChat` (`<leader>ao`), inserting file context only when the file differs from the last successful context delivery; selection requests update that file too, and tracking survives Neovim restarts

- Changed model catalogs to load asynchronously only for the selected harness, cache successful results for the Neovim session, and cancel when the picker closes
- Changed harness replacement to prepare the new launch, ask before ending a conversation, validate a candidate and save the preference before removing the existing pane, with rollback/cleanup attempts on failure; selecting the saved preference again is a no-op
- Changed tmux operations to run asynchronously with deadlines, serialize input per pane, and use unique paste buffers with cleanup
- Scoped file sync to loaded buffers under active project roots, coalesced pending callbacks, and stopped sync when asynchronous checks find a missing or dead agent pane
- Changed saved preferences to use validated, atomic writes and report invalid state explicitly

### Removed

- Removed `:ArkFocus`, the Lua `focus()` entry point and `keymaps.focus`; use `:ArkChat` to summon the agent

### Fixed

- Preserved unsaved buffer edits when files change or disappear on disk, with explicit conflict status and review snapshots
- Removed sync's global `autoread` side effect; buffer-local settings also remain unchanged
- Avoided repeated `checktime` commands for unchanged files and removed sync timers, autocommands and queued work when the last project stops
- Captured edit buffer/range/project before asynchronous prompts, rejected intervening buffer changes, and generated selection context after saving

## [0.2.0] - 2026-10-07

### Breaking Changes

- Custom harnesses must now be listed in `harness_order`

### Added

- Added the current file path to `:ArkChat` (`<leader>ao`), pasted into a running agent's input without submitting it, or given to a new agent with its startup instructions
- Added the `harness_order` option, which orders the `:ArkHarness` harness list below the current harness (default: claude, codex, pi, agy)

### Changed

- Changed `:ArkHarness` to list the current harness first, and to open the model and effort steps with the cursor on the current value, or on `medium` for an effort list with no current entry

## [0.1.1] - 2026-10-03

### Changed

- Updated README name formatting and capitalization, and removed the commercial-license contact text

## [0.1.0] - 2026-10-03

### Breaking Changes

- Raised the documented minimum Neovim version to 0.11.7 to match Telescope's requirements

### Added

- Added `:ArkEdit` (`<leader>ai` in visual mode), which sends the selected lines, their file and diagnostics, and an instruction to the project's agent pane, starting it if needed while focus stays in Neovim
- Added `:ArkChat` (`<leader>ao`), which opens and focuses the project's agent pane
- Added `:ArkHarness` (`<leader>ah`), a single Telescope picker for the harness, model and effort level, with model catalogs fetched from each CLI in the background
- Added harness adapters for Claude Code, Codex, Antigravity (`agy`) and Pi
- Added one agent pane per working directory, tracked by the tmux pane option `@ark_root`
- Added automatic reloading of buffers the agent changes on disk
- Added credential-free integration tests and GitHub Actions CI for Linux and macOS on Neovim 0.11.7 and stable
- Documented Linux and macOS as target platforms, native Windows as unsupported, and WSL as untested

### Fixed

- Fixed the installation example to include Telescope's Plenary dependency
- Fixed Pi model selection to skip the effort picker for models without reasoning support

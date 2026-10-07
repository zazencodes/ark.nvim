# Changelog

## [Unreleased]

### Added

- Added the current file path to `:ArkChat` (`<leader>ao`), pasted into the agent's input without submitting it, including for a newly started agent

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

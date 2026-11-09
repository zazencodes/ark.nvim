# `ark.nvim` Agent Harness Bridge

<p align="center">
  <a href="https://github.com/zazencodes/ark.nvim/releases/latest"><img src="https://img.shields.io/github/v/release/zazencodes/ark.nvim" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPLv3-blue" alt="License: GPLv3"></a>
  <img src="https://img.shields.io/badge/Neovim-0.11.7%2B-57A143?logo=neovim&logoColor=white" alt="Neovim 0.11.7+">
  <img src="https://img.shields.io/badge/tmux-required-1BB91F?logo=tmux&logoColor=white" alt="tmux required">
  <img src="https://img.shields.io/badge/Lua-2C2D72?logo=lua&logoColor=white" alt="Lua">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Claude%20Code-ready-D97757?logo=claude&logoColor=white" alt="Claude Code ready">
  <img src="https://img.shields.io/badge/Codex-ready-000000?logo=data:image/svg%2bxml;base64,PHN2ZyBmaWxsPSJ3aGl0ZSIgcm9sZT0iaW1nIiB2aWV3Qm94PSIwIDAgMjQgMjQiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI%2BPHRpdGxlPk9wZW5BSTwvdGl0bGU%2BPHBhdGggZD0iTTIyLjI4MTkgOS44MjExYTUuOTg0NyA1Ljk4NDcgMCAwIDAtLjUxNTctNC45MTA4IDYuMDQ2MiA2LjA0NjIgMCAwIDAtNi41MDk4LTIuOUE2LjA2NTEgNi4wNjUxIDAgMCAwIDQuOTgwNyA0LjE4MThhNS45ODQ3IDUuOTg0NyAwIDAgMC0zLjk5NzcgMi45IDYuMDQ2MiA2LjA0NjIgMCAwIDAgLjc0MjcgNy4wOTY2IDUuOTggNS45OCAwIDAgMCAuNTExIDQuOTEwNyA2LjA1MSA2LjA1MSAwIDAgMCA2LjUxNDYgMi45MDAxQTUuOTg0NyA1Ljk4NDcgMCAwIDAgMTMuMjU5OSAyNGE2LjA1NTcgNi4wNTU3IDAgMCAwIDUuNzcxOC00LjIwNTggNS45ODk0IDUuOTg5NCAwIDAgMCAzLjk5NzctMi45MDAxIDYuMDU1NyA2LjA1NTcgMCAwIDAtLjc0NzUtNy4wNzI5em0tOS4wMjIgMTIuNjA4MWE0LjQ3NTUgNC40NzU1IDAgMCAxLTIuODc2NC0xLjA0MDhsLjE0MTktLjA4MDQgNC43NzgzLTIuNzU4MmEuNzk0OC43OTQ4IDAgMCAwIC4zOTI3LS42ODEzdi02LjczNjlsMi4wMiAxLjE2ODZhLjA3MS4wNzEgMCAwIDEgLjAzOC4wNTJ2NS41ODI2YTQuNTA0IDQuNTA0IDAgMCAxLTQuNDk0NSA0LjQ5NDR6bS05LjY2MDctNC4xMjU0YTQuNDcwOCA0LjQ3MDggMCAwIDEtLjUzNDYtMy4wMTM3bC4xNDIuMDg1MiA0Ljc4MyAyLjc1ODJhLjc3MTIuNzcxMiAwIDAgMCAuNzgwNiAwbDUuODQyOC0zLjM2ODV2Mi4zMzI0YS4wODA0LjA4MDQgMCAwIDEtLjAzMzIuMDYxNUw5Ljc0IDE5Ljk1MDJhNC40OTkyIDQuNDk5MiAwIDAgMS02LjE0MDgtMS42NDY0ek0yLjM0MDggNy44OTU2YTQuNDg1IDQuNDg1IDAgMCAxIDIuMzY1NS0xLjk3MjhWMTEuNmEuNzY2NC43NjY0IDAgMCAwIC4zODc5LjY3NjVsNS44MTQ0IDMuMzU0My0yLjAyMDEgMS4xNjg1YS4wNzU3LjA3NTcgMCAwIDEtLjA3MSAwbC00LjgzMDMtMi43ODY1QTQuNTA0IDQuNTA0IDAgMCAxIDIuMzQwOCA3Ljg3MnptMTYuNTk2MyAzLjg1NThMMTMuMTAzOCA4LjM2NCAxNS4xMTkyIDcuMmEuMDc1Ny4wNzU3IDAgMCAxIC4wNzEgMGw0LjgzMDMgMi43OTEzYTQuNDk0NCA0LjQ5NDQgMCAwIDEtLjY3NjUgOC4xMDQydi01LjY3NzJhLjc5Ljc5IDAgMCAwLS40MDctLjY2N3ptMi4wMTA3LTMuMDIzMWwtLjE0Mi0uMDg1Mi00Ljc3MzUtMi43ODE4YS43NzU5Ljc3NTkgMCAwIDAtLjc4NTQgMEw5LjQwOSA5LjIyOTdWNi44OTc0YS4wNjYyLjA2NjIgMCAwIDEgLjAyODQtLjA2MTVsNC44MzAzLTIuNzg2NmE0LjQ5OTIgNC40OTkyIDAgMCAxIDYuNjgwMiA0LjY2ek04LjMwNjUgMTIuODYzbC0yLjAyLTEuMTYzOGEuMDgwNC4wODA0IDAgMCAxLS4wMzgtLjA1NjdWNi4wNzQyYTQuNDk5MiA0LjQ5OTIgMCAwIDEgNy4zNzU3LTMuNDUzN2wtLjE0Mi4wODA1TDguNzA0IDUuNDU5YS43OTQ4Ljc5NDggMCAwIDAtLjM5MjcuNjgxM3ptMS4wOTc2LTIuMzY1NGwyLjYwMi0xLjQ5OTggMi42MDY5IDEuNDk5OHYyLjk5OTRsLTIuNTk3NCAxLjQ5OTctMi42MDY3LTEuNDk5N1oiLz48L3N2Zz4%3D" alt="Codex ready">
  <img src="https://img.shields.io/badge/Antigravity-ready-4285F4?logo=googlegemini&logoColor=white" alt="Antigravity ready">
  <img src="https://img.shields.io/badge/Pi-ready-111111?logo=data:image/svg%2bxml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA1NjAgNTYwIiBmaWxsPSJ3aGl0ZSI%2BPHBhdGggZD0iTTQyMCAyODBIMjgwVjE0MEgwVjBINDIwVjI4MFoiLz48cGF0aCBkPSJNNTYwIDU2MEg0MjBWMjgwSDU2MFY1NjBaIi8%2BPHBhdGggZD0iTTE0MCA1NjBIMFYxNDBIMTQwVjI4MEgyODBWNDIwSDE0MFY1NjBaIi8%2BPC9zdmc%2B" alt="Pi ready">
  <a href="https://zazencodes.com/"><img src="https://img.shields.io/badge/made%20by-ZazenCodes-black" alt="Made by ZazenCodes"></a>
</p>

Select code in Neovim, say what you want, and let a coding agent edit the file in the background.

Ark keeps one agent conversation per working directory, shared across files. Summon its normal interactive terminal in a centered, Telescope-style floating window whenever you want to read progress or keep talking. Press Ctrl-C to hide it and return to your file; the agent keeps working.

## Features

- **Edit from a selection.** Visually select lines, press `<leader>ai`, type an instruction. The agent gets the file, the selected lines and their diagnostics, and edits the file on disk. Your cursor stays in Neovim.
- **A persistent background conversation.** Every edit goes to the same agent. `<leader>ao` summons its floating terminal, even before your first selection. It adds the current file path only when that file differs from the last context Ark delivered; reopening from the same file leaves the input untouched. Ctrl-C hides the window in terminal or normal mode; `q` also hides it in normal mode. To interrupt an agent, use its own controls (for example Escape where supported); Ctrl-C is reserved for hiding the viewer.
- **Swap harness, model and effort.** `<leader>ah` opens one Telescope picker: harness, then model, then effort level. The model lists come from the CLIs themselves, so they stay current.
- **Review disk changes.** `:ArkReview` compares preserved editor and disk versions. Conflicts keep your edits intact until you choose which version to keep.
- **Inspect the connection.** `:ArkStatus` shows the project, agent pane, running selection, saved preference and last errors. `:checkhealth ark` checks dependencies and configuration.

## Requirements

- Neovim 0.11.7 or later, running inside tmux
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) and [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- At least one agent CLI on your `PATH`

## Platform support

`ark.nvim` targets Linux and macOS. GitHub Actions runs the test suite on Ubuntu 24.04 and macOS 15 with Neovim 0.11.7 and the latest stable version. Other OS versions and Linux distributions are not covered by that matrix.

Native Windows is unsupported: Ark requires tmux and a POSIX shell. WSL is untested; run Neovim, tmux and the agent CLI inside the same Linux environment if you try it. Each agent CLI has its own platform requirements.

## Testing

Run `python3 tests/run.py` with Neovim, tmux, Python 3 and Git installed. The runner downloads Telescope and Plenary into a temporary directory, so it needs network access. It uses an isolated tmux server and Neovim directories, leaving your sessions and saved harness selection alone.

The suite exercises all four adapters with a fake agent, initial and follow-up prompts, selected diagnostics, save-before-send, background session reuse, floating terminal input and hide/reopen, the real Telescope picker, Pi effort selection, buffer reloads and state persistence. It requires no agent installations, credentials or paid API calls. These checks verify Ark's integration behavior; they do not verify live agents or detect changes to their CLI flags and catalog formats.

Run `nvim --headless -u NONE -l tests/sync.lua` for focused sync checks without tmux or network access. It tests scoped reloads, conflict preservation, lifecycle cleanup, callback coalescing and a real timer. Its work regression check compares global `checktime` invocations with scoped stats and reload commands across 256 loaded files. It measures work counts, not live CPU usage.

CI runs on pushes and pull requests, including version-tag pushes, and can also be started manually. It does not publish releases. Check that the matrix passes before publishing a release.

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "zazencodes/ark.nvim",
  version = "*", -- latest release
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
  },
  opts = {},
}
```

`setup()` (called by `opts`) creates the default keymaps. Until you pick something, Ark starts Claude Code with its own default model and effort.

## Usage

| Key | Mode | Command | Action |
| --- | --- | --- | --- |
| `<leader>ai` | visual | `:ArkEdit` | Ask the agent to edit the selected lines. Saves the buffer first and starts the background agent if needed. Focus stays in Neovim. |
| `<leader>ao` | normal | `:ArkChat` | Open the floating agent terminal, starting the background agent if needed. When the current file differs from the last context delivered to this agent, Ark inserts its file path into the input without submitting it. Reopening from the same file leaves input untouched. A new agent receives the file context in its startup instructions. |
| `<leader>ah` | normal | `:ArkHarness` | Pick the harness, model and effort. Replacing a running agent requires confirmation to end its conversation. Selecting the saved preference again does nothing. |
| Unmapped | normal | `:ArkHarness!` | Pick a harness and refresh its model catalog for this selection. |
| Unmapped | normal | `:ArkStatus` | Show the project, pane, running selection, saved preference and last errors. |
| Unmapped | normal | `:ArkReview` | Open a read-only diff tab with preserved editor/before and disk versions. |
| Unmapped | normal | `:ArkResolve disk` | Confirm replacing the original buffer's edits with the disk version. |
| Unmapped | normal | `:ArkResolve buffer` | Confirm writing the original buffer over the disk file, recreating a deleted file if needed. |

Hiding the window keeps the process and conversation alive, including while it edits files. Closing Neovim detaches the viewer; reopening Neovim in the same working directory on the same tmux server reconnects to that agent. Agents are shared across Neovim instances on that server. Exiting the agent ends its session; the next request starts a fresh one. Killing the tmux server ends its agents.

To start a new conversation, use the agent's own conversation-reset command. To end it, exit the agent from its terminal. Background requests can wait for trust, login, or permission prompts: open the terminal to answer them.

`ArkReview` works from the original buffer or either review snapshot. It opens the latest captured change and errors when none was captured; it does not provide a complete change history. The diff leaves the original buffer untouched. `ArkResolve` asks before replacing either version and checks that neither the buffer nor disk changed during confirmation. To recover a deleted file, use `ArkResolve buffer`. Review snapshots use `ark://review/...` buffer names and remain hidden when their windows close, for the rest of the Neovim session. They are session memory, so save any versions you need before exiting Neovim.

## Harnesses

| Harness | Models offered | Effort levels |
| --- | --- | --- |
| `claude` | `fable`, `opus`, `sonnet`, `haiku`. Claude Code has no listing command; these aliases track the latest model of each family. | `--effort`, low to max |
| `codex` | Listed models from `codex debug models` | Per model, from the same catalog |
| `agy` | `agy models` | Part of the model id, e.g. `gemini-3.1-pro-high` |
| `pi` | `pi --list-models` | `--thinking`, off to max, for models that support it |

The picker lists the current harness first, then the others in `harness_order`. Every model and effort list starts with `default`, which passes no flag, so the CLI uses its own configured default. The cursor starts on the current model and effort, or on `medium` when the effort list has no current entry. The selection is saved in `stdpath("state")/ark.json` and applies to every project.

Only the selected harness's catalog runs, asynchronously. The picker stays responsive while it loads; closing it cancels the request. Successful catalogs are cached for the Neovim session. Use `:ArkHarness!` to refresh the harness you select. Catalog requests time out after `catalog_timeout_ms`.

For a running pane, Ark prepares the new launch before asking to end the conversation, starts and validates a candidate pane, saves the preference, then removes the old pane. Cancellation or candidate/preference-save failure keeps the existing conversation; a failed preference save triggers candidate cleanup. If removing the old pane fails, Ark attempts to restore the preference and remove the candidate. Rollback or cleanup failures are reported explicitly; inspect `:ArkStatus` and the panes before retrying. `:ArkStatus` distinguishes the pane's running selection from the global preference; existing panes in other projects keep their running selection.

## Configuration

These are the defaults. Pass only what you want to change.

```lua
require("ark").setup({
  harnesses = {
    -- Override any field of a built-in adapter, typically `cmd`:
    -- claude = { cmd = { "claude", "--dangerously-skip-permissions" } },
  },
  harness_order = { "claude", "codex", "pi", "agy" }, -- order in :ArkHarness; must list every harness
  keymaps = {
    edit = "<leader>ai", chat = "<leader>ao", harness = "<leader>ah",
  }, -- false disables a default mapping
  window = { width = 0.85, height = 0.8 }, -- fractions of the editor size
  checktime_interval = 1000, -- ms between scoped checks for files changed on disk
  catalog_timeout_ms = 10000, -- deadline for a selected harness's model catalog
})
```

A harness `cmd` can be a wrapper. This one loads an API key from a file before starting Pi, and also applies to the model listing:

```lua
pi = { cmd = { "sh", "-c", 'OPENCODE_API_KEY=$(cat ~/.secrets/opencode) exec pi "$@"', "pi" } },
```

To add a harness, write an adapter with the fields documented at the top of [`lua/ark/harnesses.lua`](lua/ark/harnesses.lua) and add it under `harnesses` and to `harness_order`.

Window dimensions must be fractions greater than 0 and at most 1; the window resizes with Neovim. The old `pane` option has been removed and raises an error. Intervals must be positive integers. Harness commands must be nonempty argv lists, and every adapter needs a `catalog()` function. Invalid configuration or saved state raises an error. Saved preferences are validated and replaced atomically; an invalid `ark.json` must be repaired or removed before retrying.

## How it works

- **Background sessions.** Ark creates a detached tmux session and tags its agent pane with `@ark_root`. Discovery searches the tmux server for that working directory, so the link survives a Neovim restart. No adjacent split is created.
- **Floating terminal.** A Neovim terminal attaches a tmux client to that session. Hiding the window keeps its terminal buffer; deleting the buffer or exiting Neovim detaches the client. The underlying agent continues running. The viewer uses the same server socket explicitly and leaves the editor's outer tmux pane selected. The floating terminal displays the CLI directly; the harness/model picker uses Telescope.
- **Instructions.** [`instructions.md`](instructions.md) tells the agent it is driven from Neovim and should edit files on disk. It is passed at launch as a system prompt (`--append-system-prompt-file` for Claude, `developer_instructions` for Codex, `--append-system-prompt` for Pi). agy has no such flag, so it receives the instructions as its first message.
- **Chat context.** `:ArkChat` inserts an `<editor_context>` block with the file path only when opening from a different file. The block stays in the input for your next message. Reopening from the same file preserves your draft. Selection requests also update the last file, so opening after `:ArkEdit` adds no duplicate context. Ark remembers that file in the agent's `@ark_file` pane option across Neovim restarts. A new agent receives context in its startup instructions (for Antigravity, its first prompt). Opening from a non-file buffer adds no context. Switching buffers alone sends nothing. If you manually erase a context block in the agent input, Ark still remembers having inserted it.
- **Requests.** Each edit sends an `<editor_context>` block (workspace, file, numbered selected lines, diagnostics) and a `<request>` block. The first one is the agent's startup prompt; later ones are pasted into the pane as one bracketed paste.
- **Transport.** tmux operations run asynchronously with deadlines and actionable errors. Input to each pane is serialized and uses a unique named paste buffer, which Ark removes after use. Edit requests capture the file, range and project before prompting, reject changes made during the prompt, then build context after saving.
- **Reloads.** Each active project checks only its loaded file buffers, including hidden buffers. An initial scoped `checktime` catches earlier changes; subsequent ticks stat those files and run buffer-specific `checktime` only when their disk signature changes. Callbacks coalesce while one is pending. Ark leaves global and buffer-local `autoread` settings unchanged.
- **Conflicts.** Reloads initiated by Ark preserve a before/disk snapshot. Modified buffers and deleted files detected by Ark produce a conflict, preserve the buffer, and expose both versions through `:ArkReview`. Conflicts are reported once per observed disk version and clear after an explicit read or write. Neovim's own `autoread` checks or another plugin can reload a file first; those reloads bypass Ark's before snapshot.
- **Lifecycle.** An asynchronous pane check runs once a second for used projects. A missing or dead pane stops that project's sync. Stopping the last project or exiting Neovim closes sync timers, removes its autocommands and cancels queued sync work.

### Sync integration

`require("ark.sync").start(root, interval_ms)` registers an absolute project root; calling it again updates the interval. `stop(root)` removes one root and `stop()` removes all roots. Overlapping roots use the most specific root for each buffer. `status()` returns a detached table with `running`, `pending`, `roots` (path to interval), and `buffers`, `conflicts`, `reloads` (buffer number to record).

`User` events `ArkSyncConflict` and `ArkSyncReload` carry `ev.data = { buf, path, root, reason }`; `reason` is `changed` or `deleted`. Reload events and status records also include `previous_lines`, captured before reloading. Register listeners before starting sync. Pane liveness belongs to the caller; sync itself starts no subprocesses.

## Notes

- The first launch in a new folder shows the agent's own folder-trust prompt. Answer it in the floating terminal, and the request then runs.
- Codex prints a startup warning that `-c` overrides force "embedded mode". It is harmless.

## Changelog

See [CHANGELOG.md](CHANGELOG.md). Releases are tagged `vX.Y.Z`. A patch release adds features or fixes bugs; a minor release contains breaking changes.

## License

[GPLv3](LICENSE). You can use, modify and share this code, and any version you distribute must also be released under GPLv3.

<p align="center">
  <a href="https://zazencodes.com/?utm_source=github&utm_medium=referral&utm_campaign=ark-nvim">
    <img
      src="docs/assets/zazencodes-banner.png"
      alt="ZazenCodes — Engineering for the Agentic Era"
      width="100%"
    >
  </a>
  <br>
  Created by <a href="https://zazencodes.com/">ZazenCodes</a>
</p>

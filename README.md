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

Select code in Neovim, say what you want, and a coding agent in the tmux pane next to you edits the file.

Ark connects Neovim to your agent CLI. The agent runs in its own tmux pane with its normal interface, so you keep its full chat, tool calls and history, and talk to it from your editor.

```text
┌──────────────────────────────┬──────────────────────┐
│ Neovim                       │ claude / codex /     │
│                              │ agy / pi             │
│ select → <leader>ai ─────────┼─→ edits the file     │
│ buffer reloads ←─────────────┼── on disk            │
│                              │                      │
│                              │ keep chatting here   │
└──────────────────────────────┴──────────────────────┘
```

## Features

- **Edit from a selection.** Visually select lines, press `<leader>ai`, type an instruction. The agent gets the file, the selected lines and their diagnostics, and edits the file on disk. Your cursor stays in Neovim.
- **A real conversation beside your code.** Every edit goes into the same agent session in a side pane, so you can follow up there ("make it async", "undo that"). `<leader>ao` jumps to it.
- **Swap harness, model and effort.** `<leader>ah` opens one Telescope picker: harness, then model, then effort level. The model lists come from the CLIs themselves, so they stay current.

## Requirements

- Neovim 0.11.7 or later, running inside tmux
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) and [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- At least one agent CLI on your `PATH`

## Platform support

`ark.nvim` targets Linux and macOS. GitHub Actions runs the test suite on Ubuntu 24.04 and macOS 15 with Neovim 0.11.7 and the latest stable version. Other OS versions and Linux distributions are not covered by that matrix.

Native Windows is unsupported: Ark requires tmux and a POSIX shell. WSL is untested; run Neovim, tmux and the agent CLI inside the same Linux environment if you try it. Each agent CLI has its own platform requirements.

## Testing

Run `python3 tests/run.py` with Neovim, tmux, Python 3 and Git installed. The runner downloads Telescope and Plenary into a temporary directory, so it needs network access. It uses an isolated tmux server and Neovim directories, leaving your sessions and saved harness selection alone.

The suite exercises all four adapters with a fake agent, initial and follow-up prompts, selected diagnostics, save-before-send, pane reuse and focus, the real Telescope picker, Pi effort selection, buffer reloads and state persistence. It requires no agent installations, credentials or paid API calls. These checks verify Ark's integration behavior; they do not verify live agents or detect changes to their CLI flags and catalog formats.

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
| `<leader>ai` | visual | `:ArkEdit` | Ask the agent to edit the selected lines. Saves the buffer first and starts the agent pane if needed. Focus stays in Neovim. |
| `<leader>ao` | normal | `:ArkChat` | Open the agent pane and focus it, starting the agent if needed. |
| `<leader>ah` | normal | `:ArkHarness` | Pick the harness, model and effort. Restarts a running agent pane, which ends its conversation. |

To start a new conversation, use the agent's own `/clear`. To end it, exit the agent; its pane closes.

## Harnesses

| Harness | Models offered | Effort levels |
| --- | --- | --- |
| `claude` | `fable`, `opus`, `sonnet`, `haiku`. Claude Code has no listing command; these aliases track the latest model of each family. | `--effort`, low to max |
| `codex` | Listed models from `codex debug models` | Per model, from the same catalog |
| `agy` | `agy models` | Part of the model id, e.g. `gemini-3.1-pro-high` |
| `pi` | `pi --list-models` | `--thinking`, off to max, for models that support it |

Every model and effort list starts with `default`, which passes no flag, so the CLI uses its own configured default. The selection is saved in `stdpath("state")/ark.json` and applies to every project.

## Configuration

These are the defaults. Pass only what you want to change.

```lua
require("ark").setup({
  harnesses = {
    -- Override any field of a built-in adapter, typically `cmd`:
    -- claude = { cmd = { "claude", "--dangerously-skip-permissions" } },
  },
  keymaps = { edit = "<leader>ai", chat = "<leader>ao", harness = "<leader>ah" }, -- false disables one
  pane = { size = "40%" },   -- width of the agent pane
  checktime_interval = 1000, -- ms between checks for files changed on disk
})
```

A harness `cmd` can be a wrapper. This one loads an API key from a file before starting Pi, and also applies to the model listing:

```lua
pi = { cmd = { "sh", "-c", 'OPENCODE_API_KEY=$(cat ~/.secrets/opencode) exec pi "$@"', "pi" } },
```

To add a harness, write an adapter with the fields documented at the top of [`lua/ark/harnesses.lua`](lua/ark/harnesses.lua) and add it under `harnesses`.

## How it works

- **Panes.** Ark splits a pane beside Neovim with `tmux split-window` and tags it with the pane option `@ark_root`. tmux is the only record of which pane belongs to which project, so the link survives a Neovim restart.
- **Instructions.** [`instructions.md`](instructions.md) tells the agent it is driven from Neovim and should edit files on disk. It is passed at launch as a system prompt (`--append-system-prompt-file` for Claude, `developer_instructions` for Codex, `--append-system-prompt` for Pi). agy has no such flag, so it receives the instructions as its first message.
- **Requests.** Each edit sends an `<editor_context>` block (workspace, file, numbered selected lines, diagnostics) and a `<request>` block. The first one is the agent's startup prompt; later ones are pasted into the pane as one bracketed paste.
- **Reloads.** A timer runs `:checktime` every second once an agent is in use.

## Notes

- The first launch in a new folder shows the agent's own folder-trust prompt. Answer it in the pane, and the request then runs.
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

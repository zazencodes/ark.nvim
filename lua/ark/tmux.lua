-- tmux transport. The agent pane for a project is found by the @ark_root
-- pane option, so tmux itself is the session registry.
local M = {}

local ROOT_OPTION = "@ark_root"

-- bracket_paste_flag, used by wait_for_input, first appeared in tmux 3.7.
local function check_version()
  local out = vim.system({ "tmux", "-V" }, { text = true }):wait().stdout
  local major, minor = out:match("(%d+)%.(%d+)")
  if not major then
    error(("ark: could not parse tmux version from %q"):format(vim.trim(out)))
  end
  if tonumber(major) < 3 or (tonumber(major) == 3 and tonumber(minor) < 7) then
    error(("ark: tmux 3.7 or later is required, found %s"):format(vim.trim(out)))
  end
end

local version_checked = false

local function tmux(args, stdin)
  if not version_checked then
    check_version()
    version_checked = true
  end
  local result = vim.system(vim.list_extend({ "tmux" }, args), { stdin = stdin, text = true }):wait()
  if result.code ~= 0 then
    error(("ark: tmux %s failed: %s"):format(args[1], vim.trim(result.stderr)))
  end
  return vim.trim(result.stdout)
end

local function nvim_pane()
  local pane = vim.env.TMUX_PANE
  if not vim.env.TMUX or not pane then
    error("ark: Neovim must be running inside tmux")
  end
  return pane
end

-- Returns the pane id of the agent for `root` in the current tmux session, or nil.
function M.find_pane(root)
  local out = tmux({ "list-panes", "-s", "-t", nvim_pane(), "-F", "#{pane_id}\t#{" .. ROOT_OPTION .. "}" })
  for line in vim.gsplit(out, "\n", { plain = true }) do
    local id, pane_root = line:match("^(%%%d+)\t(.*)$")
    if pane_root == root then
      return id
    end
  end
end

-- Splits a new pane beside Neovim running `argv`, tags it with `root`, and
-- returns its id. Focus stays in Neovim.
function M.spawn(root, argv, size)
  local args = { "split-window", "-h", "-d", "-l", size, "-t", nvim_pane(), "-c", root, "-P", "-F", "#{pane_id}" }
  local id = tmux(vim.list_extend(args, argv))
  tmux({ "set-option", "-p", "-t", id, ROOT_OPTION, root })
  return id
end

-- Blocks until the program in the pane enables bracketed paste, which agent
-- TUIs do once they read input. Errors after `timeout` ms.
function M.wait_for_input(pane, timeout)
  local ready = vim.wait(timeout, function()
    return tmux({ "display-message", "-p", "-t", pane, "#{bracket_paste_flag}" }) == "1"
  end, 50)
  if not ready then
    error(("ark: agent in pane %s did not accept input within %d ms"):format(pane, timeout))
  end
end

-- Pastes `text` into the pane's input as a single bracketed paste.
function M.paste(pane, text)
  local buffer = "ark"
  tmux({ "load-buffer", "-b", buffer, "-" }, text)
  tmux({ "paste-buffer", "-p", "-r", "-d", "-b", buffer, "-t", pane })
end

-- Pastes `text` into the pane and submits it.
function M.send(pane, text)
  M.paste(pane, text)
  tmux({ "send-keys", "-t", pane, "Enter" })
end

function M.kill(pane)
  tmux({ "kill-pane", "-t", pane })
end

function M.focus(pane)
  tmux({ "select-window", "-t", pane })
  tmux({ "select-pane", "-t", pane })
end

return M

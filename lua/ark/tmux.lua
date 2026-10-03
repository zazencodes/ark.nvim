-- tmux transport. The agent pane for a project is found by the @ark_root
-- pane option, so tmux itself is the session registry.
local M = {}

local ROOT_OPTION = "@ark_root"

local function tmux(args, stdin)
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

-- Pastes `text` into the pane as a single bracketed paste and submits it.
function M.send(pane, text)
  local buffer = "ark"
  tmux({ "load-buffer", "-b", buffer, "-" }, text)
  tmux({ "paste-buffer", "-p", "-r", "-d", "-b", buffer, "-t", pane })
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

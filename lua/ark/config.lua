local M = {}

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")

-- Static behavioral instructions given to every harness at launch.
M.instructions_path = plugin_root .. "/instructions.md"

M.defaults = {
  -- Adapters for the harnesses offered by :ArkHarness. See ark/harnesses.lua.
  harnesses = require("ark.harnesses"),
  -- Set by setup(). Set a key to false to leave it unmapped.
  keymaps = {
    edit = "<leader>ai",
    chat = "<leader>ao",
    harness = "<leader>ah",
  },
  pane = {
    -- Width of the agent pane, passed to `tmux split-window -l`.
    size = "40%",
  },
  -- How often (ms) Neovim checks for files changed on disk by the agent.
  checktime_interval = 1000,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

function M.harness(name)
  local harness = M.options.harnesses[name]
  if not harness then
    error(("ark: unknown harness %q (configured: %s)"):format(
      name,
      table.concat(vim.tbl_keys(M.options.harnesses), ", ")
    ))
  end
  return harness
end

return M

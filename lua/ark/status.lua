local M = {}
local failures = {}

function M.record(root, message)
  failures[root] = { message = tostring(message), time = os.date("%Y-%m-%d %H:%M:%S") }
end

function M.last_error(root)
  return vim.deepcopy(failures[root])
end

function M.snapshot(root, done)
  local transport = require("ark.tmux")
  local preference = require("ark.state").load()
  local result = {
    root = root, preference = preference, last_error = M.last_error(root),
    transport = transport.status(), sync = require("ark.sync").status(),
  }
  transport.find_pane(root, function(err, pane)
    if err then result.pane_error = err; return done(nil, result) end
    if not pane then return done(nil, result) end
    transport.inspect(pane, function(inspect_err, runtime)
      if inspect_err then result.pane_error = inspect_err else result.runtime = runtime end
      done(nil, result)
    end)
  end)
end

function M.open(root)
  M.snapshot(root, function(err, result)
    if err then M.record(root, err); error(err) end
    local state = require("ark.state")
    local runtime = result.runtime
    local lines = {
      "Ark status", "", "Project: " .. result.root,
      "Pane: " .. (runtime and runtime.id or "none"),
      "Running selection: " .. (runtime and runtime.selection and state.describe(runtime.selection) or "unknown"),
      "Saved preference: " .. state.describe(result.preference),
      "Sync roots: " .. table.concat(vim.tbl_keys(result.sync.roots or {}), ", "),
      "",
      "Last workflow error: " .. (result.last_error and (result.last_error.time .. " " .. result.last_error.message) or "none"),
      "Pane error: " .. (result.pane_error or "none"),
      "Last transport error: " .. (result.transport.last_failure and result.transport.last_failure.message or "none"),
    }
    vim.cmd("botright new")
    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = "arkstatus"
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
  end)
end

return M
